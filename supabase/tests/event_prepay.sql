-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Коли платять — 20261125190000_event_prepay: передоплата чи на зустрічі; без ціни — завжди false.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.paid',gen_random_uuid()::text,true),
 set_config('test.free',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-prepay-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','adult_confirmed',true));

set local role authenticated;
do $$
declare v record; p uuid := current_setting('test.paid')::uuid;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.create_event(p,'Paid board games','Prepay as the organizer asks in the chat','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',300,null,null,true);
 select * into v from public.event_details(p);
 assert v.prepay,'paid event with prepay';
 -- Старий клієнт без p_prepay — не чіпає.
 perform public.update_event(p,'Paid board games','Prepay as the organizer asks in the chat','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,300);
 select * into v from public.event_details(p);
 assert v.prepay,'null keeps prepay';
 perform public.update_event(p,'Paid board games','Prepay as the organizer asks in the chat','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,300,null,null,false);
 select * into v from public.event_details(p);
 assert not v.prepay,'back to paying at the meeting';
 -- Ціну прибрали — передоплати нема.
 perform public.update_event(p,'Paid board games','Prepay as the organizer asks in the chat','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,0,null,null,true);
 select * into v from public.event_details(p);
 assert not v.prepay and v.price_min is null,'free event never prepaid';
 perform public.create_event(current_setting('test.free')::uuid,'Free walk in the park','Meet at the entrance and walk','outdoors','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',null,null,null,true);
 select * into v from public.event_details(current_setting('test.free')::uuid);
 assert not v.prepay,'no price — no prepay';
end $$;
reset role;
rollback;

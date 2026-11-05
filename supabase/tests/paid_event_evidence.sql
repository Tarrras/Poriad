-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Платні події без оплати онлайн — 20261125180000_paid_event_evidence: «Новий організатор» і знімок при видаленні акаунта.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.paid',gen_random_uuid()::text,true),set_config('test.free',gen_random_uuid()::text,true),
 set_config('test.past',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-evid-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','adult_confirmed',true)),
 (current_setting('test.guest')::uuid,'poruch-evid-guest-'||current_setting('test.guest')||'@example.invalid',jsonb_build_object('display_name','Guest','adult_confirmed',true));

set local role authenticated;
do $$
declare v record;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.create_event(current_setting('test.paid')::uuid,'Paid board games','Pay at the door or as agreed in the chat','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,'https://t.me/boardgames_kyiv',null,'web',300);
 perform public.create_event(current_setting('test.free')::uuid,'Free walk in the park','Meet at the entrance and walk','outdoors','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',null);
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 select * into v from public.event_details(current_setting('test.paid')::uuid);
 assert v.organizer_new,'paid event of a new organizer is marked';
 select * into v from public.event_details(current_setting('test.free')::uuid);
 assert v.organizer_new is null,'free events are not marked';
end $$;
reset role;

-- Проведена подія з учасником — уже не новий.
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,status)
values (current_setting('test.past')::uuid,current_setting('test.host')::uuid,'Past games meetup','Board games evening that already happened','games','Kyiv','Podil',50.46,30.52,
 now()-interval '3 days',now()-interval '3 days'+interval '2 hours','Europe/Kyiv',10,'published');
insert into public.event_members(event_id,user_id,status) values (current_setting('test.past')::uuid,current_setting('test.guest')::uuid,'approved');
set local role authenticated;
do $$
declare v record;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 select * into v from public.event_details(current_setting('test.paid')::uuid);
 assert not v.organizer_new,'held an event — not new anymore';
end $$;
reset role;

-- Видалення акаунта: платні події лишаються знімком на 180 днів (безкоштовні — ні).
do $$
declare s jsonb;
begin
 perform private.prepare_account_deletion(current_setting('test.host')::uuid);
 select snapshot into s from private.payment_evidence where deleted_user_id=current_setting('test.host')::uuid and snapshot->>'kind'='paid_event';
 assert s->'event'->>'contact_url'='https://t.me/boardgames_kyiv' and s->'organizer'->>'name'='Host' and (s->'event'->>'price')::numeric=300,'snapshot: '||s::text;
 assert (select count(*) from private.payment_evidence where deleted_user_id=current_setting('test.host')::uuid and snapshot->>'kind'='paid_event')=1,'only the paid event';
end $$;
rollback;

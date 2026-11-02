-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Ціна події від людей — 20261124120000_event_price: лише ціна, оплата — з організатором напряму.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.paid',gen_random_uuid()::text,true),set_config('test.free',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-price-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','birth_date','1990-01-01')),
 (current_setting('test.guest')::uuid,'poruch-price-guest-'||current_setting('test.guest')||'@example.invalid',jsonb_build_object('display_name','Guest','adult_confirmed',true));

set local role authenticated;
do $$
declare v record;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.create_event(current_setting('test.paid')::uuid,'Paid board games','Pay the host at the door','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'app',300);
 -- 0 і без ціни — безкоштовно.
 perform public.create_event(current_setting('test.free')::uuid,'Free board games','Just come and play','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',0);
 begin perform public.create_event(gen_random_uuid(),'Bad','Too expensive event','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'app',100001);
  raise exception 'price above the limit accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PRICE','price up to 100 000'; end;
 begin perform public.create_event(gen_random_uuid(),'Bad','Negative price event','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'app',-5);
  raise exception 'negative price accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PRICE','no negative price'; end;

 -- Ціну бачать усі, хто бачить подію.
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 select * into v from public.event_details(current_setting('test.paid')::uuid);
 assert v.price_min=300,'price is public';
 select * into v from public.event_details(current_setting('test.free')::uuid);
 assert v.price_min is null,'0 means free';

 -- Старий клієнт (без p_price) ціну не чіпає; 0 — безкоштовно; нова ціна — замість старої.
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.update_event(current_setting('test.paid')::uuid,'Paid board games','Pay the host at the door','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false);
 select * into v from public.event_details(current_setting('test.paid')::uuid);
 assert v.price_min=300,'old client keeps the price';
 perform public.update_event(current_setting('test.paid')::uuid,'Paid board games','Pay the host at the door','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,450);
 select * into v from public.event_details(current_setting('test.paid')::uuid);
 assert v.price_min=450,'new price';
 perform public.update_event(current_setting('test.paid')::uuid,'Paid board games','Pay the host at the door','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,0);
 select * into v from public.event_details(current_setting('test.paid')::uuid);
 assert v.price_min is null,'free again';
 begin perform public.update_event(current_setting('test.paid')::uuid,'Paid board games','Pay the host at the door','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,100001);
  raise exception 'update above the limit accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PRICE','update checks the price too'; end;
end $$;
reset role;

do $$ begin
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_event'),'one create_event for PostgREST';
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='update_event'),'one update_event for PostgREST';
end $$;
select 'PASS: event_price' as result;
rollback;

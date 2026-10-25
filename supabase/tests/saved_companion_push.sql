-- Запускати адміністратором бази. Усе відкочується. Пуш «Хтось шукає компанію на вашу збережену подію»: кому (зберіг
-- до збору, токен знає пуш, не організатор, не в зборі, не заблокований), один на людину на афішу, кілька зборів —
-- один пуш, стеля на добу, тихі години, повний збір, права, видалення акаунта.
begin;

-- Пуші ловимо в таблицю замість pg_net, адреса функції підроблена, тихі години — за прапорцем тесту.
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select 'https://example.invalid'::text, 'x'::text $$;
select set_config('test.quiet','off',false);
create or replace function private.quiet_hours(p_at timestamptz default now()) returns boolean language sql set search_path='' as $$
 select current_setting('test.quiet') = 'on';
$$;
-- У базі можуть бути справжні збори й закладки: прогін без афіші бачив би й їх.
delete from private.companion_pushes;

select set_config('test.host',gen_random_uuid()::text,true),set_config('test.host2',gen_random_uuid()::text,true),
 set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.c',gen_random_uuid()::text,true),set_config('test.d',gen_random_uuid()::text,true),
 set_config('test.e',gen_random_uuid()::text,true),set_config('test.g',gen_random_uuid()::text,true),
 set_config('test.p1',gen_random_uuid()::text,true),set_config('test.p2',gen_random_uuid()::text,true),
 set_config('test.p3',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select current_setting('test.'||k)::uuid,'poruch-savedcomp-'||k||'-'||current_setting('test.'||k)||'@example.invalid',
 jsonb_build_object('display_name','S','birth_date','1990-01-01')
from unnest(array['host','host2','a','b','c','d','e','g']) k;
-- Токени: b — лише застосунок без цього пуша (1.3.1), решта знають `companion`.
insert into public.push_tokens(token,user_id,platform,features)
select 'savedcomp-test-'||k||'-0123456789',current_setting('test.'||k)::uuid,'android',
 case when k='b' then array['companion_decision'] else array['companion_decision','companion'] end
from unnest(array['host','host2','a','b','c','d','e','g']) k;

insert into public.event_sources(slug,name,kind,base_url) values ('test_savedcomp','Test','manual','https://example.invalid');
insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,origin,source_id,source_uid,import_status,quality)
select current_setting('test.'||k)::uuid,'Афіша '||k,'','music','Ocean','Buoy, 1',-40.5,-30.5,date_trunc('hour',now())+d,date_trunc('hour',now())+d+interval '3 hours',
 'Europe/Kyiv','import',(select id from public.event_sources where slug='test_savedcomp'),'sc-'||k,'live',0.9
from (values ('p1',interval '2 days'),('p2',interval '3 days'),('p3',interval '4 days')) v(k,d);

-- Закладки годину тому, до будь-якого збору. c зберігає вже після: про збір, який бачив, не кажемо.
insert into public.saved_events(user_id,event_id,created_at)
select current_setting('test.'||u)::uuid,current_setting('test.'||p)::uuid,now()-interval '1 hour'
from (values ('host','p1'),('a','p1'),('b','p1'),('d','p1'),('e','p1'),('a','p2'),('g','p3')) v(u,p);
insert into public.saved_events(user_id,event_id,created_at) values (current_setting('test.c')::uuid,current_setting('test.p1')::uuid,now()+interval '1 minute');
-- host заблокував d: збори host d не бачить.
insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.host')::uuid,current_setting('test.d')::uuid);

create function pg_temp.companion(p_who text,p_parent text,p_before interval,p_capacity integer default 4) returns uuid language plpgsql as $$
declare v uuid;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.'||p_who),true);
 set local role authenticated;
 v := public.create_companion(current_setting('test.'||p_parent)::uuid,
  (select starts_at from public.events where id=current_setting('test.'||p_parent)::uuid)-p_before,null,p_capacity);
 reset role;
 return v;
end $$;

-- Ніч: e збирає компанію на p1 — пуша нема, нікого не записано.
select set_config('test.quiet','on',false);
select set_config('test.e1',pg_temp.companion('e','p1',interval '2 hours')::text,true);
do $$ begin
 assert not exists(select 1 from pg_temp.sent where payload->>'type'='companion'),'quiet hours: nothing is sent at night';
 assert not exists(select 1 from private.companion_pushes),'and nobody is marked as told';
end $$;

-- День: host збирає свою на p1. Обидва збори — один пуш на людину: a бачить обидва, d (заблокований host) — лише e.
select set_config('test.quiet','off',false);
select set_config('test.h1',pg_temp.companion('host','p1',interval '1 hour')::text,true);
do $$ declare v_a jsonb; v_d jsonb; begin
 assert (select count(*)=2 from pg_temp.sent where payload->>'type'='companion'),'one call per distinct list of companions';
 select payload into v_a from pg_temp.sent where payload->'user_ids' ? current_setting('test.a');
 select payload into v_d from pg_temp.sent where payload->'user_ids' ? current_setting('test.d');
 assert v_a = jsonb_build_object('type','companion','event_id',current_setting('test.p1'),
  'companion_ids',jsonb_build_array(current_setting('test.e1'),current_setting('test.h1')),'user_ids',jsonb_build_array(current_setting('test.a'))),
  'a: both companions, the nearest meet first';
 assert v_d->'companion_ids' = jsonb_build_array(current_setting('test.e1')) and v_d->'user_ids' = jsonb_build_array(current_setting('test.d')),
  'd does not see the companion of someone who blocked them';
 -- b — без токена з прапорцем, c — зберіг після збору, host і e — уже шукають компанію самі.
 assert (select array_agg(user_id order by user_id) from private.companion_pushes)
  = array(select x::uuid from unnest(array[current_setting('test.a'),current_setting('test.d')]) x order by 1),'only a and d are told';
 assert (select companion_id=current_setting('test.e1')::uuid and companions=2 from private.companion_pushes where user_id=current_setting('test.a')::uuid),
  'the log keeps where the tap led and how many companions were named';
end $$;
delete from pg_temp.sent;

-- Ще збір на ту саму афішу: людям, яким уже казали, не кажемо вдруге.
select set_config('test.h2',pg_temp.companion('host2','p1',interval '30 minutes')::text,true);
do $$ begin
 assert not exists(select 1 from pg_temp.sent where payload->>'type'='companion'),'one push per person per event';
end $$;

-- Стеля: a за добу вже мав такий пуш — збір на p2 чекає; минуло 25 годин — годинний прогін його доставляє.
select set_config('test.h3',pg_temp.companion('host','p2',interval '1 hour')::text,true);
do $$ begin
 assert not exists(select 1 from pg_temp.sent where payload->>'type'='companion'),'daily ceiling: the second event waits';
 assert private.notify_saved_companions()=0,'the hourly run respects it too';
end $$;
update private.companion_pushes set sent_at=now()-interval '25 hours' where user_id=current_setting('test.a')::uuid;
do $$ begin
 assert private.notify_saved_companions()=1,'a day later the waiting event goes';
 assert (select count(*)=1 and bool_and(payload->'user_ids'=jsonb_build_array(current_setting('test.a'))
  and payload->>'event_id'=current_setting('test.p2') and payload->'companion_ids'=jsonb_build_array(current_setting('test.h3')))
  from pg_temp.sent where payload->>'type'='companion'),'a hears about p2';
 assert private.notify_saved_companions()=0,'and only once';
end $$;
delete from pg_temp.sent;

-- Повний збір не кличе: місце звільнилось — кличе.
select set_config('test.quiet','on',false);
select set_config('test.h4',pg_temp.companion('host','p3',interval '1 hour',2)::text,true);
insert into public.event_members(event_id,user_id,status) values
 (current_setting('test.h4')::uuid,current_setting('test.b')::uuid,'approved'),(current_setting('test.h4')::uuid,current_setting('test.c')::uuid,'approved');
select set_config('test.quiet','off',false);
do $$ begin
 assert private.notify_saved_companions()=0,'a full companion is not announced';
end $$;
delete from public.event_members where event_id=current_setting('test.h4')::uuid and user_id=current_setting('test.c')::uuid;
do $$ begin
 assert private.notify_saved_companions()=1,'a seat freed up: g is told';
 assert (select payload->'user_ids'=jsonb_build_array(current_setting('test.g')) from pg_temp.sent where payload->>'type'='companion'),'g';
end $$;
delete from pg_temp.sent;

-- Без адреси функції нічого не пишемо: людина значилась би сповіщеною.
delete from private.companion_pushes where user_id=current_setting('test.g')::uuid;
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select null::text, null::text $$;
do $$ begin
 assert private.notify_saved_companions()=0 and not exists(select 1 from private.companion_pushes where user_id=current_setting('test.g')::uuid),
  'no endpoint: nothing is logged';
end $$;

-- Клієнтам — ні розсилки, ні журналу.
do $$ begin
 assert not has_function_privilege('authenticated','private.notify_saved_companions(uuid)','execute'),'clients cannot run the push';
 assert not has_table_privilege('authenticated','private.companion_pushes','select'),'the log is private';
 assert not has_table_privilege('anon','private.companion_pushes','select'),'for guests too';
end $$;

-- Видалення акаунта забирає записи журналу.
delete from auth.users where id=current_setting('test.a')::uuid;
do $$ begin
 assert not exists(select 1 from private.companion_pushes where user_id=current_setting('test.a')::uuid),'the log goes with the account';
end $$;

select 'PASS: saved companion push: who, once per event, one push for several companions, daily ceiling, quiet hours, full, rights' as result;
rollback;

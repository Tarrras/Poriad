-- Запускати адміністратором бази. Усе відкочується. Підписки: рядки лише власника й лише через RPC, правила
-- підписки, пуш організатора одразу, один пуш на людину по закладах (що нове, ліміт на добу, прокат, токен,
-- адреса функції), список і головна.
begin;

-- Ізоляція: у базі можуть бути справжні підписки, а зведення обробляє всіх. Усе відкотиться.
delete from public.follows;
delete from private.follow_pushes;
delete from private.follow_announced;

-- Пуші ловимо в таблицю замість pg_net: заміна функції відкотиться разом з рештою. Адреса функції теж підроблена:
-- без неї зведення нічого не робить (перевіряємо окремо).
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select 'https://example.invalid'::text, 'x'::text $$;
create temp table fx(id uuid primary key) on commit drop;

select set_config('test.host',gen_random_uuid()::text,true),set_config('test.a',gen_random_uuid()::text,true),
 set_config('test.b',gen_random_uuid()::text,true),set_config('test.c',gen_random_uuid()::text,true),
 set_config('test.d',gen_random_uuid()::text,true),set_config('test.e',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-follows-'||id||'@example.invalid',jsonb_build_object('display_name','F','birth_date','1990-01-01')
from unnest(array[current_setting('test.host'),current_setting('test.a'),current_setting('test.b'),current_setting('test.c'),
 current_setting('test.d'),current_setting('test.e')]) id;
-- Пристрої: a і b мають токен, d — ні (додамо пізніше).
insert into public.push_tokens(token,user_id,platform) values
 ('follow-test-a-0123456789',current_setting('test.a')::uuid,'android'),('follow-test-b-0123456789',current_setting('test.b')::uuid,'ios');

insert into public.places(name,city,address,latitude,longitude,source) values
 ('Клуб Follow-1','Ocean','Buoy, 1',-41.1,-31.1,'osm'),('Клуб Follow-2','Ocean','Buoy, 2',-41.2,-31.2,'osm');
select set_config('test.p1',(select id::text from public.places where name='Клуб Follow-1'),true),
 set_config('test.p2',(select id::text from public.places where name='Клуб Follow-2'),true);
insert into public.event_sources(slug,name,kind,base_url) values ('test_follows','Test','manual','https://example.invalid');

-- Афіша: ім'я фікстури, назва, заклад, початок і «коли з'явилась» (відносно зараз).
create function pg_temp.imp(p_name text,p_title text,p_place text,p_start interval,p_created interval,
 p_end interval default null,p_status text default 'live',p_quality numeric default 0.9) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
 insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
  origin,source_id,source_uid,import_status,quality,place_id,created_at)
 select v_id,p_title,'','music','Ocean','Buoy',pl.latitude,pl.longitude,now()+p_start,now()+coalesce(p_end,p_start+interval '2 hours'),'UTC',
  'import',(select id from public.event_sources where slug='test_follows'),p_name,p_status,p_quality,pl.id,now()+p_created
 from public.places pl where pl.name=p_place;
 perform set_config('test.'||p_name,v_id::text,true);
 insert into pg_temp.fx values (v_id);
 return v_id;
end $$;
select pg_temp.imp('n1','Стендап А','Клуб Follow-1',interval '1 day',interval '-1 hour');
select pg_temp.imp('n2','Джем Б','Клуб Follow-1',interval '2 days',interval '-1 hour');
-- Другий сеанс тієї ж вистави: прокат рахується один раз.
select pg_temp.imp('n3','Стендап А','Клуб Follow-1',interval '3 days',interval '-1 hour');
-- З'явилась до підписки: не нова.
select pg_temp.imp('old1','Старий концерт','Клуб Follow-1',interval '4 days',interval '-3 hours');
-- Минула, знята джерелом і слабка за якістю: у видачі їх нема, у пуші теж.
select pg_temp.imp('past1','Минулий','Клуб Follow-1',interval '-5 hours',interval '-1 hour',interval '-3 hours');
select pg_temp.imp('stale1','Знятий','Клуб Follow-1',interval '5 days',interval '-1 hour',null,'stale');
select pg_temp.imp('weak1','Слабкий','Клуб Follow-1',interval '5 days',interval '-1 hour',null,'live',0.3);
select pg_temp.imp('q1','Квартирник','Клуб Follow-2',interval '1 day 1 hour',interval '-1 hour');
-- Давно скінчилась: запис про неї в журналі «названого» зайвий, зведення його прибере.
select pg_temp.imp('ancient','Давній','Клуб Follow-1',interval '-4 days',interval '-5 days',interval '-3 days');

-- Спільнотні: дві події організатора з однією назвою (щочетверга — різні вечори) і супутник афіші (ні пуша, ні лічильників).
select set_config('test.h1',gen_random_uuid()::text,true),set_config('test.h1b',gen_random_uuid()::text,true),
 set_config('test.comp',gen_random_uuid()::text,true);
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,created_at)
values (current_setting('test.h1')::uuid,current_setting('test.host')::uuid,'Зустріч','Test description','social','Ocean','Buoy',-41.1,-31.1,
 now()+interval '6 days',now()+interval '6 days 2 hours','UTC',10,now()-interval '1 hour'),
 (current_setting('test.h1b')::uuid,current_setting('test.host')::uuid,'Зустріч','Test description','social','Ocean','Buoy',-41.1,-31.1,
 now()+interval '7 days',now()+interval '7 days 2 hours','UTC',10,now()-interval '1 hour');
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,
 place_id,companion_of,created_at)
values (current_setting('test.comp')::uuid,current_setting('test.host')::uuid,'Йдемо разом: Стендап А','Test description','music','Ocean','Buoy',-41.1,-31.1,
 now()+interval '1 day',now()+interval '1 day 2 hours','UTC',4,current_setting('test.p1')::uuid,current_setting('test.n1')::uuid,now()-interval '1 hour');
insert into pg_temp.fx values (current_setting('test.h1')::uuid),(current_setting('test.h1b')::uuid),(current_setting('test.comp')::uuid);

do $$ begin
 assert (select count(*)=2 from pg_temp.sent),'only the organizer''s own events push: imports and companions do not';
 assert (select bool_and(payload->>'type'='follow' and payload->>'kind'='organizer') from pg_temp.sent),'organizer payload';
 assert (select array_agg(payload->>'event_id' order by payload->>'event_id') from pg_temp.sent)
  =array(select x from unnest(array[current_setting('test.h1'),current_setting('test.h1b')]) x order by x),'one push per event';
end $$;
delete from pg_temp.sent;

-- Гість: ні таблиці, ні RPC.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.follow('place',current_setting('test.p1')::uuid); raise exception 'anon followed';
 exception when insufficient_privilege then null; end;
 begin perform public.my_follows(); raise exception 'anon listed';
 exception when insufficient_privilege then null; end;
 begin perform public.follow_events(); raise exception 'anon read the feed';
 exception when insufficient_privilege then null; end;
 begin perform count(*) from public.follows; raise exception 'anon read the table';
 exception when insufficient_privilege then null; end;
end $$;
reset role;

-- Підписка: заклад і організатор; повтор — тиша; недоречні цілі відхиляються.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
select public.follow('place',current_setting('test.p1')::uuid);
select public.follow('place',current_setting('test.p1')::uuid);
select public.follow('organizer',current_setting('test.host')::uuid);
do $$ begin
 assert (select count(*)=2 from public.follows),'a place and an organizer, the repeat is a no-op';
 begin perform public.follow('star',gen_random_uuid()); raise exception 'unknown kind accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_FOLLOW'; end;
 begin perform public.follow('place',gen_random_uuid()); raise exception 'missing place accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='FOLLOW_UNAVAILABLE'; end;
 begin perform public.follow('organizer',current_setting('test.a')::uuid); raise exception 'self follow accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='FOLLOW_UNAVAILABLE'; end;
 begin perform public.follow('organizer',current_setting('test.c')::uuid); raise exception 'non-organizer accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='FOLLOW_UNAVAILABLE'; end;
 -- Писати напряму не можна навіть у свій рядок: лише RPC.
 begin insert into public.follows(user_id,target_kind,target_id) values (current_setting('test.a')::uuid,'place',gen_random_uuid()); raise exception 'direct insert accepted';
 exception when insufficient_privilege then null; end;
 begin delete from public.follows; raise exception 'direct delete accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
 assert not has_function_privilege('authenticated','private.notify_place_follows()','execute'),'clients cannot run the digest';
 assert not has_function_privilege('authenticated','private.follow(text,uuid)','execute') is null,'private wrappers are granted only for the invoker wrappers';
 assert not has_table_privilege('authenticated','private.follow_announced','select'),'the announced log is private';
 assert not has_table_privilege('authenticated','private.follow_pushes','select'),'so is the push log';
end $$;

-- b стежить за обома закладами, d — за першим (без токена). Чужих рядків не бачить ніхто.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
select public.follow('place',current_setting('test.p1')::uuid);
select public.follow('place',current_setting('test.p2')::uuid);
do $$ begin
 assert (select count(*)=2 and bool_and(user_id=current_setting('test.b')::uuid) from public.follows),'b sees only its own rows';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.d'),true);
select public.follow('place',current_setting('test.p1')::uuid);
reset role;
-- Підписки давніші за «нове»: усе, що з'явилось годину тому, — після них.
update public.follows set created_at=now()-interval '2 hours';

-- Список і головна.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
do $$ declare v jsonb; begin
 assert (select count(*)=2 from public.follows),'a sees only its own rows';
 v := public.my_follows();
 assert jsonb_array_length(v)=2,'a follows a place and an organizer';
 assert (select x->>'name' from jsonb_array_elements(v) x where x->>'kind'='place')='Клуб Follow-1','place name';
 assert (select (x->>'upcoming')::int from jsonb_array_elements(v) x where x->>'kind'='place')=3,'three runs ahead, a two-session run counts once';
 assert (select (x->>'upcoming')::int from jsonb_array_elements(v) x where x->>'kind'='organizer')=2,'the organizer has two events (one title, two evenings); the companion is not counted';
 v := public.follow_events(10);
 assert (select array_agg(x->>'title' order by ord) from jsonb_array_elements(v) with ordinality t(x,ord))
  =array['Стендап А','Джем Б','Старий концерт','Зустріч','Зустріч'],'home feed: closest first, a run of an act is one card, the organizer''s evenings are not folded';
 assert jsonb_array_length(public.follow_events(1))=1,'limit';
end $$;
reset role;

-- Пуш організатора з реального шляху створення події.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select set_config('test.h2',gen_random_uuid()::text,true);
select public.create_event(current_setting('test.h2')::uuid,'Ще зустріч','Description here','games','Ocean','Buoy',-41.1,-31.1,
 now()+interval '7 days',now()+interval '8 days','UTC',5,null,18,null,false);
reset role;
do $$ begin
 assert (select count(*)=1 and bool_and(payload=jsonb_build_object('type','follow','kind','organizer','event_id',current_setting('test.h2'))) from pg_temp.sent),
  'create_event pushes once';
end $$;
delete from pg_temp.sent;

-- Без адреси функції зведення нічого не робить і нічого не витрачає: пуш нікуди не піде.
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select null::text, null::text $$;
do $$ begin
 assert private.notify_place_follows()=0,'no endpoint, no digest';
 assert not exists(select 1 from private.follow_announced) and not exists(select 1 from private.follow_pushes),'and nothing is spent';
end $$;
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select 'https://example.invalid'::text, 'x'::text $$;

-- Зведення: одна людина — один пуш. Нове: після підписки, ще попереду, видиме, про що ще не казали; прокат — раз.
-- d нового не отримує: пристрою нема.
do $$ declare a text := current_setting('test.a'); b text := current_setting('test.b');
 p1 text := current_setting('test.p1'); p2 text := current_setting('test.p2'); begin
 assert private.notify_place_follows()=2,'one push per person; d has no device';
 assert (select count(*)=2 from pg_temp.sent where payload->>'kind'='place'),'two pushes';
 assert (select payload from pg_temp.sent where payload->>'user_id'=a)=jsonb_build_object('type','follow','kind','place','user_id',a,
  'total',2,'place_count',1,'places',jsonb_build_array(jsonb_build_object('id',p1,'n',2)),
  'event_ids',jsonb_build_array(current_setting('test.n1'),current_setting('test.n2'))),
  'a: two runs at one place; the old, past, stale, weak and companion events are not new';
 assert (select payload from pg_temp.sent where payload->>'user_id'=b)=jsonb_build_object('type','follow','kind','place','user_id',b,
  'total',3,'place_count',2,'places',jsonb_build_array(jsonb_build_object('id',p1,'n',2),jsonb_build_object('id',p2,'n',1)),
  'event_ids',jsonb_build_array(current_setting('test.n1'),current_setting('test.q1'),current_setting('test.n2'))),
  'b: three runs at two places, the busier place first, three closest events';
 assert (select count(*)=3 from private.follow_announced where user_id=a::uuid),'a was told about all three sessions, not only the named ones';
 assert (select count(*)=4 from private.follow_announced where user_id=b::uuid),'b: three at the first place, one at the second';
 assert not exists(select 1 from private.follow_announced where user_id=current_setting('test.d')::uuid) and
  not exists(select 1 from private.follow_pushes where user_id=current_setting('test.d')::uuid),'no device: nothing announced, no daily slot spent';
 -- Те, про що вже сказали, вдруге не рахується.
 assert private.notify_place_follows()=0,'nothing new: silence';
end $$;

-- Нова подія після пуша: ліміт раз на добу тримає її, вона лишається «новою». Запис про давню подію зникає.
delete from pg_temp.sent;
select pg_temp.imp('n4','Новий вечір','Клуб Follow-1',interval '8 days',interval '1 minute');
insert into private.follow_announced(user_id,event_id) values (current_setting('test.a')::uuid,current_setting('test.ancient')::uuid);
do $$ begin
 assert private.notify_place_follows()=0,'at most one push a day per person';
 assert not exists(select 1 from pg_temp.sent),'the limit sends nothing';
 assert not exists(select 1 from private.follow_announced where event_id=current_setting('test.n4')::uuid),'and does not use the event up';
 assert not exists(select 1 from private.follow_announced where event_id=current_setting('test.ancient')::uuid),'the log forgets events that ended long ago';
end $$;

-- d отримав пристрій: усе, що було, лишилось «новим», і йде одним пушем.
insert into public.push_tokens(token,user_id,platform) values ('follow-test-d-0123456789',current_setting('test.d')::uuid,'android');
do $$ declare d text := current_setting('test.d'); begin
 assert private.notify_place_follows()=1,'the device turned up: d gets what was held back';
 assert (select payload from pg_temp.sent where payload->>'user_id'=d)=jsonb_build_object('type','follow','kind','place','user_id',d,
  'total',3,'place_count',1,'places',jsonb_build_array(jsonb_build_object('id',current_setting('test.p1'),'n',3)),
  'event_ids',jsonb_build_array(current_setting('test.n1'),current_setting('test.n2'),current_setting('test.n4'))),
  'd: three runs at one place';
end $$;

-- Минула доба: ліміт знято, лишається лише те, чого ще не казали.
delete from pg_temp.sent;
update private.follow_pushes set sent_at=sent_at-interval '25 hours' where user_id in (current_setting('test.a')::uuid,current_setting('test.b')::uuid);
do $$ declare a text := current_setting('test.a'); begin
 assert private.notify_place_follows()=2,'a day later the held event goes out, once per person';
 assert (select payload from pg_temp.sent where payload->>'user_id'=a)=jsonb_build_object('type','follow','kind','place','user_id',a,
  'total',1,'place_count',1,'places',jsonb_build_array(jsonb_build_object('id',current_setting('test.p1'),'n',1)),'event_ids',jsonb_build_array(current_setting('test.n4'))),
  'only what nobody had said yet';
end $$;

-- Заблокований організатор зникає зі списку й головної; підписатись на нього не можна, і відповідь не каже, що це блок.
insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.a')::uuid,current_setting('test.host')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
do $$ begin
 assert (select count(*)=1 from jsonb_array_elements(public.my_follows()) x where x->>'kind'='place'),'the place stays';
 assert not exists(select 1 from jsonb_array_elements(public.my_follows()) x where x->>'kind'='organizer'),'the blocked organizer is hidden';
 assert not exists(select 1 from jsonb_array_elements(public.follow_events(10)) x where x->>'title' in ('Зустріч','Ще зустріч')),'and so are its events';
 begin perform public.follow('organizer',current_setting('test.host')::uuid); raise exception 'blocked organizer accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='FOLLOW_UNAVAILABLE'; end;
end $$;
-- Той, хто заблокував нас, не відрізняється від того, хто просто не організатор.
reset role;
insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.host')::uuid,current_setting('test.b')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
do $$ begin
 begin perform public.follow('organizer',current_setting('test.host')::uuid); raise exception 'accepted after being blocked';
 exception when sqlstate 'P0001' then assert sqlerrm='FOLLOW_UNAVAILABLE','a block by the organizer looks like any refusal'; end;
end $$;
reset role;

-- Обмежений акаунт не підписується.
update public.account_facts set status='limited' where user_id=current_setting('test.c')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.c'),true);
do $$ begin
 begin perform public.follow('place',current_setting('test.p1')::uuid); raise exception 'limited account followed';
 exception when sqlstate '42501' then assert sqlerrm='ACCOUNT_RESTRICTED'; end;
end $$;
reset role;

-- Стеля: двісті підписок; повтор наявної проходить, нова — ні.
insert into public.follows(user_id,target_kind,target_id)
select current_setting('test.e')::uuid,'place',gen_random_uuid() from generate_series(1,199);
insert into public.follows(user_id,target_kind,target_id) values (current_setting('test.e')::uuid,'place',current_setting('test.p1')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.e'),true);
select public.follow('place',current_setting('test.p1')::uuid);
do $$ begin
 begin perform public.follow('place',current_setting('test.p2')::uuid); raise exception 'the 201st follow accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='TOO_MANY_FOLLOWS'; end;
end $$;
reset role;

-- Відписка чіпає лише свої рядки; копія даних несе підписки.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
do $$ begin
 assert jsonb_array_length(public.export_my_data()->'follows')=2,'the export carries the follows';
 perform public.unfollow('place',current_setting('test.p1')::uuid);
 perform public.unfollow('place',current_setting('test.p1')::uuid);
 assert (select count(*)=1 from public.follows),'unfollow removes one row and repeats quietly';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.c'),true);
select public.unfollow('place',current_setting('test.p1')::uuid);
reset role;
do $$ begin
 assert (select count(*)=2 from public.follows where user_id=current_setting('test.b')::uuid),'nobody else lost a row';
end $$;

-- Видалення акаунта забирає його підписки й записи про пуш.
delete from auth.users where id=current_setting('test.b')::uuid;
do $$ begin
 assert not exists(select 1 from public.follows where user_id=current_setting('test.b')::uuid),'follows go with the account';
 assert not exists(select 1 from private.follow_pushes where user_id=current_setting('test.b')::uuid),'so does the push log';
 assert not exists(select 1 from private.follow_announced where user_id=current_setting('test.b')::uuid),'and the announced log';
end $$;

select 'PASS: follows: private rows, rules, organizer push, one place push per person per day, feed and list' as result;
rollback;

-- Запускати адміністратором бази. Усе відкочується. Артисти (20261002120000, 20261002130000): пошук лише з
-- майбутніми видимими подіями, картка знає артистів, «Стежити» через RPC, зведення пуша (що нове, прокат,
-- подія з двома артистами, ліміт на добу, пристрій) і спільний ліміт із закладами.
begin;

-- Ізоляція: у базі можуть бути справжні підписки, а зведення обробляє всіх. Усе відкотиться.
delete from public.follows;
delete from private.follow_pushes;
delete from private.follow_announced;

create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select 'https://example.invalid'::text, 'x'::text $$;

select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.d',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-artists-'||id||'@example.invalid',jsonb_build_object('display_name','F','birth_date','1990-01-01')
from unnest(array[current_setting('test.a'),current_setting('test.b'),current_setting('test.d')]) id;
-- a і b мають токен, d ні.
insert into public.push_tokens(token,user_id,platform) values
 ('artist-test-a-0123456789',current_setting('test.a')::uuid,'android'),('artist-test-b-0123456789',current_setting('test.b')::uuid,'ios');

insert into public.event_sources(slug,name,kind,base_url) values ('test_artists','Test','manual','https://example.invalid');
insert into public.artists(name,key,kind,source) values
 ('Артист Ікс','артист ікс','person','manual'),('Гурт Ігрек','гурт ігрек','group','auto'),('Без Подій','без подій',null,'auto');
select set_config('test.x',(select id::text from public.artists where key='артист ікс'),true),
 set_config('test.y',(select id::text from public.artists where key='гурт ігрек'),true),
 set_config('test.z',(select id::text from public.artists where key='без подій'),true);

create function pg_temp.imp(p_name text,p_title text,p_start interval,p_created interval,
 p_status text default 'live',p_quality numeric default 0.9) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
 insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
  origin,source_id,source_uid,import_status,quality,created_at)
 values (v_id,p_title,'','music','Ocean','Buoy',-41.1,-31.1,now()+p_start,now()+p_start+interval '2 hours','UTC',
  'import',(select id from public.event_sources where slug='test_artists'),p_name,p_status,p_quality,now()+p_created);
 perform set_config('test.'||p_name,v_id::text,true);
 return v_id;
end $$;
create function pg_temp.link(p_event text,p_artist text,p_role text default 'headliner',p_pos int default 0) returns void language sql as $$
 insert into public.event_artists(event_id,artist_id,role,position,how,confidence)
 values (current_setting('test.'||p_event)::uuid,current_setting('test.'||p_artist)::uuid,p_role,p_pos,'rules',0.9);
$$;
-- Нові (з'явились після підписки): два сеанси однієї назви (прокат), окрема подія гурту й спільна для обох.
select pg_temp.imp('n1','Концерт Ікса',interval '1 day',interval '-1 hour');
select pg_temp.imp('n2','Концерт Ікса',interval '2 days',interval '-1 hour');
select pg_temp.imp('n3','Джем Ігрека',interval '3 days',interval '-1 hour');
select pg_temp.imp('both','Спільний вечір',interval '4 days',interval '-1 hour');
-- Не нові й не видимі: з'явилась до підписки, зайва за статусом і за якістю, минула.
select pg_temp.imp('old1','Старий концерт',interval '5 days',interval '-3 hours');
select pg_temp.imp('stale1','Знятий',interval '5 days',interval '-1 hour','stale');
select pg_temp.imp('weak1','Слабкий',interval '5 days',interval '-1 hour','live',0.3);
select pg_temp.imp('past1','Минулий',interval '-5 hours',interval '-1 hour');
select pg_temp.link('n1','x'); select pg_temp.link('n2','x'); select pg_temp.link('n3','y');
select pg_temp.link('both','x'); select pg_temp.link('both','y','support',1);
select pg_temp.link('old1','x'); select pg_temp.link('stale1','x'); select pg_temp.link('weak1','x'); select pg_temp.link('past1','x');

-- Пошук: лише артисти з майбутніми видимими подіями; префікс слова; місто.
set local role anon;
do $$ declare r jsonb; begin
 r := public.search_artists('артист ікс');
 assert jsonb_array_length(r)=1 and r->0->>'name'='Артист Ікс','search finds the artist with events';
 -- Ікс: n1+n2 (одна вистава в двох сеансах), both, old1 = 3 вистави (stale, weak і минула не рахуються).
 -- Те саме число, що в «Підписках»: прокат один раз.
 assert (r->0->>'upcoming')::int=3,'search counts runs, not sessions: '||(r->0->>'upcoming');
 assert public.search_artists('без подій')='[]'::jsonb,'an artist without events is not offered';
 assert jsonb_array_length(public.search_artists('ікс','Ocean'))=1 and public.search_artists('ікс','Киів')='[]'::jsonb,'city filter';
 assert public.search_artists('  ')='[]'::jsonb,'blank text';
 begin perform public.search_artists(repeat('х',121)); raise exception 'long text accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_SEARCH_TEXT'; end;
 -- Події артиста: картками, найближчі першими, без знятих і слабких.
 r := public.artist_events(current_setting('test.x')::uuid);
 assert jsonb_array_length(r)=4,'artist events: '||jsonb_array_length(r);
 assert r->0->>'title'='Концерт Ікса','nearest first';
 -- Картка знає артистів: роль і порядок.
 assert (select count(*)=2 from jsonb_array_elements(
  (select c->'artists' from jsonb_array_elements(r) c where c->>'id'=current_setting('test.both')))),'card carries both artists';
 assert (select c->'artists'->1->>'role' from jsonb_array_elements(r) c where c->>'id'=current_setting('test.both'))='support','role in the card';
 assert not exists (select 1 from jsonb_array_elements(r) c where c->>'id'=current_setting('test.stale1')),'withdrawn event is not offered';
 assert public.artist_events(null)='[]'::jsonb,'null artist';
 -- Прямого доступу до зв'язку немає, а до імен є.
 begin perform count(*) from public.event_artists; raise exception 'links readable directly';
 exception when insufficient_privilege then null; end;
 assert (select count(*)>=3 from public.artists),'names are public';
end $$;
reset role;

-- «Стежити»: артист як ціль; повтор — тиша; чужий id відхиляється; прямий запис заборонений.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
select public.follow('artist',current_setting('test.x')::uuid);
select public.follow('artist',current_setting('test.x')::uuid);
select public.follow('artist',current_setting('test.y')::uuid);
do $$ declare r jsonb; begin
 assert (select count(*)=2 from public.follows where target_kind='artist'),'two artists, the repeat is a no-op';
 begin perform public.follow('artist',gen_random_uuid()); raise exception 'missing artist accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='FOLLOW_UNAVAILABLE'; end;
 r := public.my_follows();
 assert jsonb_array_length(r)=2 and (select bool_and(i->>'kind'='artist') from jsonb_array_elements(r) i),'list holds artists';
 -- Ікс: «Концерт Ікса» (прокат з двох сеансів = 1), «Спільний вечір»; «Старий» теж видима й підписка з нею збігається.
 assert (select (i->>'upcoming')::int from jsonb_array_elements(r) i where i->>'name'='Артист Ікс')=3,'upcoming counts runs, not sessions';
 -- Пошук і підписки дають одне число для одного артиста.
 assert (select (public.search_artists('артист ікс')->0->>'upcoming')::int)=(select (i->>'upcoming')::int from jsonb_array_elements(r) i where i->>'name'='Артист Ікс'),'search and follows agree';
 -- Головна: прокат одним рядком, подія з двома артистами один раз на артиста, але картка одна.
 assert (select count(*) from jsonb_array_elements(public.follow_events(20)) c where c->>'title'='Концерт Ікса')=1,'run is one card';
end $$;
reset role;
-- Підписку роблять заднім числом: події з'явились після неї, крім old1.
update public.follows set created_at = now() - interval '2 hours';
-- d підписаний, але без пристрою: нове лишається «новим».
insert into public.follows(user_id,target_kind,target_id,created_at)
 values (current_setting('test.d')::uuid,'artist',current_setting('test.x')::uuid,now()-interval '2 hours');

-- Зведення: одному a один пуш, прокат і спільна подія рахуються один раз; b і d (без пристрою) нічого.
do $$ declare v integer; p jsonb; begin
 v := private.notify_artist_follows();
 assert v=1,'one person with a device: '||v;
 p := (select payload from pg_temp.sent limit 1);
 assert p->>'type'='follow' and p->>'kind'='artist' and p->>'user_id'=current_setting('test.a'),'payload: '||p;
 assert (p->>'total')::int=3,'run + joint show + other = 3 shows: '||(p->>'total');
 assert (p->>'artist_count')::int=2,'two artists';
 assert p->'artists'->0->>'id'=current_setting('test.x'),'busiest artist first, ties by nearest';
 assert jsonb_array_length(p->'event_ids')=3 and p->'event_ids'->>0=current_setting('test.n1'),'nearest events, no old/stale/weak/past';
 assert not (p->'event_ids')::text like '%'||current_setting('test.old1')||'%','old event is not new';
 -- Повторний прогін мовчить: людині вже сказали, і ліміт на добу.
 assert private.notify_artist_follows()=0,'second run is silent';
 assert (select count(*)=1 from pg_temp.sent),'still one push';
 -- d без пристрою не витратила «нове»: з'явиться токен — отримає.
 assert not exists (select 1 from private.follow_announced where user_id=current_setting('test.d')::uuid),'no device keeps the news';
 insert into public.push_tokens(token,user_id,platform) values ('artist-test-d-0123456789',current_setting('test.d')::uuid,'ios');
 assert private.notify_artist_follows()=1,'the device arrived, the news is delivered';
 -- Спільний ліміт із закладами: хто отримав пуш про артиста, того зведення закладів тієї ж доби не чіпає.
 assert exists (select 1 from private.follow_pushes where user_id=current_setting('test.a')::uuid),'one daily limit for both digests';
end $$;

-- Двері: клієнти не запускають зведення і не читають журнали.
do $$ begin
 assert not has_function_privilege('authenticated','private.notify_artist_follows()','execute'),'clients cannot run the digest';
 assert not has_function_privilege('anon','public.follow(text,uuid)','execute'),'anon cannot follow';
 assert has_function_privilege('anon','public.search_artists(text,text,integer)','execute'),'anyone can search';
end $$;

rollback;
select 'artists: ok' as result;

-- Запускати адміністратором бази. Усе відкочується. Подія з кількома продавцями (docs/event-offers.md, фаза 1):
-- злиття переносить усі зв'язки без втрат, старий id відкриває живу подію, ідентичність липка, основний продавець
-- не перемикається, поки живий, ручне зняття й вимкнене джерело — на рівні пропозиції, від'єднання не повертається.
begin;

-- Пуші тригерів (учасник, повідомлення) нікуди не йдуть.
create or replace function private.notify_push(p_payload jsonb) returns void language plpgsql security definer
 set search_path='' as $$ begin end $$;

select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.run',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-offers-'||id||'@example.invalid',jsonb_build_object('display_name','O','birth_date','1990-01-01')
from unnest(array[current_setting('test.a'),current_setting('test.b')]) id;
insert into public.event_sources(slug,name,kind,base_url,weight,enabled) values
 ('test_offers_a','Продавець А','manual','https://example.invalid',0.8,true),
 ('test_offers_b','Продавець Б','manual','https://example.invalid',0.7,true),
 ('test_offers_c','Продавець В','manual','https://example.invalid',0.5,true);
insert into public.artists(name,key) values ('Тест Ікс','тест ікс'),('Тест Ігрек','тест ігрек');

-- Рядок дампу: переможець (members — копії групи) або копія (winner — ключ переможця).
create function pg_temp.w(p_slug text, p_uid text, p_title text, p_start timestamptz, p_members jsonb default null,
 p_id uuid default null, p_descr text default '') returns jsonb language sql as $$
 select jsonb_strip_nulls(jsonb_build_object('id',coalesce(p_id,gen_random_uuid()),'slug',p_slug,'uid',p_uid,
  'url','https://example.invalid/'||p_uid,'title',p_title,'description',p_descr,'category','music','city','Ocean',
  'address','Buoy, 1','lat',-40.5,'lon',-30.5,'starts',p_start,'ends',p_start+interval '2 hours','tz','Europe/Kyiv',
  'dedupe','x','quality',0.9,'price',300,'members',p_members)) $$;
create function pg_temp.c(p_slug text, p_uid text, p_title text, p_start timestamptz, p_wslug text, p_wuid text,
 p_linked text default 'rule') returns jsonb language sql as $$
 select jsonb_build_object('slug',p_slug,'uid',p_uid,'url','https://example.invalid/'||p_uid,'title',p_title,
  'starts',p_start,'price',250,'winner_slug',p_wslug,'winner_uid',p_wuid,'linked',p_linked) $$;
create function pg_temp.ev(p_slug text, p_uid text) returns uuid language sql as $$
 select o.event_id from public.event_offers o join public.event_sources s on s.id=o.source_id
 where s.slug=p_slug and o.source_uid=p_uid $$;
create function pg_temp.ingest(p_rows jsonb) returns integer language sql as $$
 select private.ingest_offers(current_setting('test.run')::uuid, p_rows) $$;
select set_config('test.t',(date_trunc('minute',now())+interval '10 days')::text,true);

-- ── 1. Злиття: копія, що жила окремою подією, переходить у подію переможця разом з усіма зв'язками.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_a','live-1','Гурт Тест',current_setting('test.t')::timestamptz)));
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_b','dup-1','Гурт Тест. Концерт',current_setting('test.t')::timestamptz,
 null,null,'Опис лише в копії')));
select set_config('test.live',pg_temp.ev('test_offers_a','live-1')::text,true),
 set_config('test.dup',pg_temp.ev('test_offers_b','dup-1')::text,true);
update public.event_offers set status='withdrawn' where source_uid='dup-1';      -- знята копія, як до фази 1
do $$ declare l uuid := current_setting('test.live')::uuid; d uuid := current_setting('test.dup')::uuid;
 a uuid := current_setting('test.a')::uuid; b uuid := current_setting('test.b')::uuid; begin
 assert l <> d, 'two events before the merge';
 assert (select import_status from public.events where id=d)='withdrawn', 'withdrawn copy';
 insert into public.saved_events(user_id,event_id) values (a,d),(b,d),(a,l);
 insert into public.event_members(event_id,user_id) values (d,a);
 insert into public.event_waitlist(event_id,user_id) values (d,b);
 insert into public.event_ratings(event_id,user_id,score) values (d,a,5),(d,b,4),(l,b,3);
 insert into public.event_messages(event_id,author_id,body) values (d,a,'Хто йде?');
 insert into public.chat_reads(user_id,event_id,read_at) values (a,d,now()),(a,l,now()-interval '1 day');
 insert into public.event_artists(event_id,artist_id,how) select d,id,'source' from public.artists where key in ('тест ікс','тест ігрек');
 insert into public.event_artists(event_id,artist_id,how) select l,id,'source' from public.artists where key='тест ікс';
 insert into private.follow_announced(user_id,event_id) values (a,d),(a,l);
 insert into private.follow_seen(user_id,event_id) values (b,d);
 insert into public.reports(reporter_id,subject_type,event_id,reason) values (b,'event',d,'scam');
 -- Супутники: збір a переходить; у b уже є збір на живій події, тож його другий лишається на надгробку.
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,companion_of) values
  (gen_random_uuid(),a,'Йдемо разом: А','Test description','music','Ocean','Buoy, 1',-40.5,-30.5,now()+interval '9 days',now()+interval '10 days','UTC',4,d),
  (gen_random_uuid(),b,'Йдемо разом: Б1','Test description','music','Ocean','Buoy, 1',-40.5,-30.5,now()+interval '9 days',now()+interval '10 days','UTC',4,d),
  (gen_random_uuid(),b,'Йдемо разом: Б2','Test description','music','Ocean','Buoy, 1',-40.5,-30.5,now()+interval '9 days',now()+interval '10 days','UTC',4,l);
end $$;
create temp table before_links on commit drop as
select (select count(*) from public.saved_events) saved, (select count(*) from public.event_ratings) ratings,
 (select count(*) from public.event_artists) artists, (select count(*) from private.follow_announced) announced,
 (select count(*) from public.chat_reads) reads;

-- Конвеєр сьогодні звів пару: копія з ключем переможця.
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_offers_b','dup-1','Гурт Тест. Концерт',current_setting('test.t')::timestamptz,
 'test_offers_a','live-1')));
do $$ declare l uuid := current_setting('test.live')::uuid; d uuid := current_setting('test.dup')::uuid;
 a uuid := current_setting('test.a')::uuid; b uuid := current_setting('test.b')::uuid; e public.events; m jsonb; begin
 select * into e from public.events where id=d;
 assert e.merged_into=l and e.import_status='withdrawn', 'copy is a tombstone of the live event';
 assert (select count(*) from public.event_offers where event_id=l)=2 and pg_temp.ev('test_offers_b','dup-1')=l, 'both offers on the live event';
 assert (select status from public.event_offers where source_uid='dup-1')='live', 'seen copy is a live offer again';
 -- Нічого не лишилось на надгробку, крім збору, якому заборонено переходити.
 assert not exists (select 1 from public.saved_events where event_id=d), 'no saves on the tombstone';
 assert not exists (select 1 from public.event_members where event_id=d) and not exists (select 1 from public.event_waitlist where event_id=d)
   and not exists (select 1 from public.event_ratings where event_id=d) and not exists (select 1 from public.event_messages where event_id=d)
   and not exists (select 1 from public.chat_reads where event_id=d) and not exists (select 1 from public.event_artists where event_id=d)
   and not exists (select 1 from private.follow_announced where event_id=d) and not exists (select 1 from private.follow_seen where event_id=d)
   and not exists (select 1 from public.reports where event_id=d),
   'every link moved off the tombstone';
 assert exists (select 1 from public.reports where event_id=l and reporter_id=b), 'report follows the event';
 -- Переїхало, дублі за ключем відкинуто, решта на місці.
 assert (select array_agg(user_id order by user_id) from public.saved_events where event_id=l)=(select array_agg(x order by x) from unnest(array[a,b]) x), 'both saves on the live event';
 assert (select count(*) from public.saved_events)=(select saved-1 from before_links), 'only the duplicate save dropped';
 assert exists (select 1 from public.event_members where event_id=l and user_id=a), 'member moved';
 assert exists (select 1 from public.event_waitlist where event_id=l and user_id=b), 'waitlist moved';
 assert (select score from public.event_ratings where event_id=l and user_id=a)=5 and (select score from public.event_ratings where event_id=l and user_id=b)=3,
   'rating moved; the live event keeps its own on conflict';
 assert (select count(*) from public.event_ratings)=(select ratings-1 from before_links), 'one duplicate rating dropped';
 assert (select body from public.event_messages where event_id=l)='Хто йде?', 'chat moved';
 assert (select read_at from public.chat_reads where event_id=l and user_id=a) > now()-interval '1 hour', 'later read mark kept';
 assert (select count(*) from public.event_artists where event_id=l)=2 and (select count(*) from public.event_artists)=(select artists-1 from before_links),
   'artists united';
 assert (select count(*) from private.follow_announced)=(select announced-1 from before_links)
   and exists (select 1 from private.follow_seen where event_id=l and user_id=b), 'follow marks moved';
 assert (select count(*) from public.events where companion_of=l)=2 and (select title from public.events where companion_of=d)='Йдемо разом: Б1',
   'companion follows the event; a second one of the same organizer stays';
 assert (select description from public.events where id=l)='Опис лише в копії', 'empty description filled from the tombstone';
 select moved into m from private.event_merges where from_id=d and into_id=l and reason='ingest:rule';
 assert (m->>'saved_events')::int=1 and (m->>'saved_events_dup')::int=1 and (m->>'companions')::int=1 and (m->>'companions_kept')::int=1
   and (m->>'offers')::int=1 and (m->>'reports')::int=1, 'merge journal';
 -- Основна — та, що була (А, жива): кнопка не перескакує.
 select * into e from public.events where id=l;
 assert e.import_status='live' and e.canonical_url='https://example.invalid/live-1' and e.source_uid='live-1', 'primary stays';
 assert e.price_min=250, 'lowest live price';
end $$;

-- Старий id (пуш, посилання, нагадування) віддає живу подію гостеві: і деталі, і картку.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 assert (select id from public.event_details(current_setting('test.dup')::uuid))=current_setting('test.live')::uuid, 'details by the old id';
 assert (select r.import_status from public.event_details(current_setting('test.dup')::uuid) r)='live', 'shown live';
 assert (public.event_cards_by_ids(array[current_setting('test.dup')::uuid])->0->>'id')=current_setting('test.live'), 'card by the old id';
end $$;
reset role;

-- Злиття лише імпорту.
do $$ begin
 begin perform private.merge_event((select id from public.events where companion_of=current_setting('test.live')::uuid limit 1),
  current_setting('test.live')::uuid); raise exception 'community merged';
 exception when sqlstate '22023' then null; end;
end $$;

-- ── 2. Липкість: група йде в подію, де вже є її пропозиція; основний не перемикається, поки живий.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_c','s-c','Сольник',current_setting('test.t')::timestamptz+interval '1 day')));
select set_config('test.s',pg_temp.ev('test_offers_c','s-c')::text,true);
-- Наступного дня важчий продавець виграє групу в пам'яті, а легший стає копією.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_a','s-a','Сольник Артиста',current_setting('test.t')::timestamptz+interval '1 day',
 '[{"slug":"test_offers_c","uid":"s-c"}]')));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_offers_c','s-c','Сольник',current_setting('test.t')::timestamptz+interval '1 day','test_offers_a','s-a')));
do $$ declare s uuid := current_setting('test.s')::uuid; e public.events; begin
 assert pg_temp.ev('test_offers_a','s-a')=s, 'heavier seller joins the existing event, no new one';
 select * into e from public.events where id=s;
 assert e.canonical_url='https://example.invalid/s-c', 'primary does not switch while alive';
 assert e.title='Сольник Артиста', 'content from the group that holds the primary';
 -- Основний зник з афіші — кнопка йде до живого з найбільшою вагою.
 update public.event_offers set status='withdrawn', ingest_run_id=current_setting('test.run')::uuid where source_uid='s-c';
 select * into e from public.events where id=s;
 assert e.canonical_url='https://example.invalid/s-a' and e.import_status='live', 'primary switches only when gone';
 update public.event_offers set status='withdrawn', ingest_run_id=current_setting('test.run')::uuid where source_uid='s-a';
 select * into e from public.events where id=s;
 assert e.import_status='withdrawn' and e.canonical_url='https://example.invalid/s-a', 'no live offer — withdrawn, last button kept';
end $$;
-- Продавець, що не є основним, переніс сеанс сам: подія не скаче (R4 вирішить), пропозиція — нова дата.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_a','s-a','Сольник Артиста',current_setting('test.t')::timestamptz+interval '1 day')));
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_c','s-c','Сольник',current_setting('test.t')::timestamptz+interval '1 day 1 hour')));
do $$ declare s uuid := current_setting('test.s')::uuid; begin
 assert (select import_status from public.events where id=s)='live', 'revived by the next dump';
 assert (select starts_at from public.events where id=s)=current_setting('test.t')::timestamptz+interval '1 day', 'event time from the primary';
 assert (select starts_at from public.event_offers where source_uid='s-c')=current_setting('test.t')::timestamptz+interval '1 day 1 hour', 'offer has its own time';
 assert pg_temp.ev('test_offers_c','s-c')=s, 'still one event';
end $$;
-- Порожній опис не стирає збережений.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_a','live-1','Гурт Тест',current_setting('test.t')::timestamptz)));
do $$ begin
 assert (select description from public.events where id=current_setting('test.live')::uuid)='Опис лише в копії', 'description kept';
end $$;

-- ── 3. Ручне зняття пропозиції дамп не скасовує; вимкнене джерело не пишеться; зайнятий id — новий.
update public.event_offers set status='withdrawn', ingest_run_id=null where source_uid='s-a';
update public.event_offers set status='withdrawn', ingest_run_id=current_setting('test.run')::uuid where source_uid='s-c';
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_a','s-a','Сольник Артиста',current_setting('test.t')::timestamptz+interval '1 day')));
do $$ begin
 assert (select status from public.event_offers where source_uid='s-a')='withdrawn', 'manual withdrawal survives';
 assert (select import_status from public.events where id=current_setting('test.s')::uuid)='withdrawn', 'event stays withdrawn';
end $$;
update public.event_sources set enabled=false where slug='test_offers_b';
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_b','off-1','Вимкнений',current_setting('test.t')::timestamptz)));
do $$ begin assert pg_temp.ev('test_offers_b','off-1') is null, 'disabled source writes nothing'; end $$;
update public.event_sources set enabled=true where slug='test_offers_b';
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_b','taken-1','Новий сеанс',current_setting('test.t')::timestamptz+interval '3 days',
 null,current_setting('test.live')::uuid)));
do $$ begin
 assert pg_temp.ev('test_offers_b','taken-1') not in (current_setting('test.live')::uuid), 'taken computed id gets a fresh one';
end $$;

-- ── 4. Від'єднання: пропозиція стає окремою подією, збереження лишаються, наступні прогони назад не приєднують.
do $$ declare l uuid := current_setting('test.live')::uuid; v uuid; begin
 v := private.detach_offer((select id from public.event_offers where source_uid='dup-1'));
 perform set_config('test.detached', v::text, true);
 assert pg_temp.ev('test_offers_b','dup-1')=v and v<>l, 'offer moved to a new event';
 assert (select linked from public.event_offers where source_uid='dup-1')='manual', 'manual link';
 assert (select count(*) from public.saved_events where event_id=l)=2 and not exists (select 1 from public.saved_events where event_id=v), 'saves stay';
 assert (select title from public.events where id=v)='Гурт Тест. Концерт' and (select import_status from public.events where id=v)='live', 'own event, live';
 assert (select canonical_url from public.events where id=l)='https://example.invalid/live-1', 'old event keeps its primary';
 begin perform private.detach_offer((select id from public.event_offers where source_uid='live-1')); raise exception 'last offer detached';
 exception when sqlstate '22023' then null; end;
end $$;
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_a','live-1','Гурт Тест',current_setting('test.t')::timestamptz,
 '[{"slug":"test_offers_b","uid":"dup-1"}]')));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_offers_b','dup-1','Гурт Тест. Концерт',current_setting('test.t')::timestamptz,'test_offers_a','live-1','agent')));
-- І навпаки: від'єднана перемогла в пам'яті, а стара пропозиція — копія.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_offers_b','dup-1','Гурт Тест. Концерт',current_setting('test.t')::timestamptz,
 '[{"slug":"test_offers_a","uid":"live-1"}]')));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_offers_a','live-1','Гурт Тест',current_setting('test.t')::timestamptz,'test_offers_b','dup-1')));
do $$ begin
 assert pg_temp.ev('test_offers_b','dup-1')=current_setting('test.detached')::uuid, 'detached offer not re-attached';
 assert pg_temp.ev('test_offers_a','live-1')=current_setting('test.live')::uuid, 'old offer not pulled into the frozen event';
 assert (select merged_into from public.events where id=current_setting('test.detached')::uuid) is null
   and (select merged_into from public.events where id=current_setting('test.live')::uuid) is null, 'nothing merged';
end $$;

-- ── 5. Агент: нова копія, яку звів агент, приєднується з linked='agent'.
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_offers_c','ag-1','Live Band',current_setting('test.t')::timestamptz,'test_offers_a','live-1','agent')));
do $$ begin
 assert pg_temp.ev('test_offers_c','ag-1')=current_setting('test.live')::uuid and (select linked from public.event_offers where source_uid='ag-1')='agent',
   'agent link stored';
end $$;

select 'PASS: links moved without loss, old id opens the live event, sticky identity, primary kept, manual/disabled, detach, agent' as result;
rollback;

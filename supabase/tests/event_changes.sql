-- Запускати адміністратором бази. Усе відкочується. Пуші про зміну афіші й супутник за подією (docs/event-offers.md,
-- фаза 3: R6–R7): рядок на кожен рядок таблиці текстів, перемикач (вимкнено — лише тінь, без ретро-пушів при
-- ввімкненні), «без сильного свідчення — тиша», повтор без дубля, виправлення лише тим, хто отримав помилкове, два
-- сильних поспіль після виправлення, вікно й «менше 12 год — одразу», R3 import_status за станом, R7 — супутник
-- зсувається, закривається й відновлюється, людина в супутнику отримує лише його пуш.
begin;

-- Пуші ловимо в таблицю замість pg_net.
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;

select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.c',gen_random_uuid()::text,true),set_config('test.d',gen_random_uuid()::text,true),
 set_config('test.e',gen_random_uuid()::text,true),set_config('test.run',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-changes-'||id||'@example.invalid',jsonb_build_object('display_name','Ch','birth_date','1990-01-01')
from unnest(array[current_setting('test.a'),current_setting('test.b'),current_setting('test.c'),current_setting('test.d'),
 current_setting('test.e')]) id;
insert into public.event_sources(slug,name,kind,base_url,weight,enabled) values
 ('test_chg_a','Concert.test','manual','https://example.invalid',0.8,true),
 ('test_chg_b','Karabas.test','manual','https://example.invalid',0.7,true);
-- Сеанс через 10 днів о 19:00 за Києвом.
select set_config('test.t',(((now() at time zone 'Europe/Kyiv')::date + 10 + time '19:00') at time zone 'Europe/Kyiv')::text,true);

create function pg_temp.t(p_shift interval default '0') returns timestamptz language sql as $$
 select current_setting('test.t')::timestamptz + p_shift $$;
create function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('test.'||p)::uuid $$;
create function pg_temp.w(p_slug text, p_uid text, p_title text, p_start timestamptz) returns jsonb language sql as $$
 select jsonb_build_object('id',gen_random_uuid(),'slug',p_slug,'uid',p_uid,'url','https://example.invalid/'||p_uid,
  'title',p_title,'description','','category','music','city','Ocean','address','Buoy, 1','lat',-40.5,'lon',-30.5,
  'starts',p_start,'ends',p_start+interval '2 hours','tz','Europe/Kyiv','dedupe','x','quality',0.9,'price',300) $$;
create function pg_temp.c(p_slug text, p_uid text, p_title text, p_start timestamptz, p_wuid text) returns jsonb language sql as $$
 select jsonb_build_object('slug',p_slug,'uid',p_uid,'url','https://example.invalid/'||p_uid,'title',p_title,
  'starts',p_start,'price',250,'winner_slug','test_chg_a','winner_uid',p_wuid) $$;
create function pg_temp.ingest(p_rows jsonb) returns integer language sql as $$
 select private.ingest_offers(current_setting('test.run')::uuid, p_rows) $$;
create function pg_temp.offer(p_uid text) returns public.event_offers language sql as $$
 select o.* from public.event_offers o join public.event_sources s on s.id=o.source_id
 where s.slug like 'test_chg_%' and o.source_uid=p_uid $$;
create function pg_temp.ev(p_uid text) returns uuid language sql as $$ select (pg_temp.offer(p_uid)).event_id $$;
create function pg_temp.chk(p_uid text, p_verdict text, p_detail jsonb default '{}', p_http integer default 200) returns integer
language sql as $$
 select private.record_offer_checks(jsonb_build_array(jsonb_build_object('offer_id',o.id,'why','vanished',
  'expected',o.starts_at,'url',o.canonical_url,'http',p_http,'verdict',p_verdict,'detail',p_detail)))
 from pg_temp.offer(p_uid) o $$;
create function pg_temp.st(p_uid text) returns private.event_state language sql as $$
 select * from private.event_state where event_id=pg_temp.ev(p_uid) $$;
create function pg_temp.save(p_user text, p_uid text) returns void language sql as $$
 insert into public.saved_events(user_id,event_id) values (pg_temp.u(p_user), pg_temp.ev(p_uid)) $$;
-- Черга пушів події: «людина: зміна · ціль · текст» у сталому порядку.
create function pg_temp.q(p_uid text, p_change text default null) returns text[] language sql as $$
 select coalesce(array_agg(x order by x), '{}') from (
  select case p.user_id when pg_temp.u('a') then 'a' when pg_temp.u('b') then 'b' when pg_temp.u('c') then 'c'
               when pg_temp.u('d') then 'd' when pg_temp.u('e') then 'e' end
   || ':' || p.change || case when p.target_id = p.event_id then '' else ' · супутник' end || ' · ' || p.body as x
  from private.event_change_pushes p
  where p.event_id = pg_temp.ev(p_uid) and p.skipped is null and (p_change is null or p.change = p_change)) s $$;
-- Усе з черги, що чекає вікна, — відправити зараз (вікно перевіряється окремо, у п. 7).
create function pg_temp.flush() returns integer language sql as $$
 update private.event_change_pushes set send_after = now() where sent_at is null and skipped is null;
 select private.flush_event_change_pushes() $$;
create function pg_temp.import_status(p_uid text) returns text language sql as $$
 select import_status from public.events where id = pg_temp.ev(p_uid) $$;

-- ── 1. Таблиця текстів R6–R7, рядок за рядком; дата як у функції push; тихі години в поясі події.
do $$ declare t timestamptz := '2026-11-07 17:00+00'; begin
 assert private.when_uk(t, 'Europe/Kyiv') = 'сб, 7 листопада о 19:00', 'date like Intl uk-UA';
 assert private.event_change_body('cancelled', 'x', 'Concert.ua')
   = 'Скасовано. Якщо купили квиток — повернення в Concert.ua', 'cancelled, one seller';
 assert private.event_change_body('cancelled', 'x', null)
   = 'Скасовано. Якщо купили квиток — повернення у продавця, де купували', 'cancelled, several sellers';
 assert private.event_change_body('postponed', 'x', 'Concert.ua') = 'Відкладено, нової дати ще нема', 'postponed';
 assert private.event_change_body('moved', private.when_uk(t, 'Europe/Kyiv'))
   = 'Перенесено на сб, 7 листопада о 19:00', 'moved';
 assert private.event_change_body('corrected', private.when_uk(t, 'Europe/Kyiv'))
   = 'Подія все ж відбудеться: сб, 7 листопада о 19:00', 'corrected';
 assert private.event_change_body('cancelled', 'x', 'Concert.ua', true) = 'Подію скасували, тож збір скасовано', 'R7 cancelled';
 assert private.event_change_body('postponed', 'x', null, true) = 'Подію відклали, тож збір скасовано', 'R7 postponed';
 assert private.event_change_body('moved', 'x', null, true, 'сб, 7 листопада о 18:30')
   = 'Подію перенесли — збір тепер сб, 7 листопада о 18:30', 'R7 moved';
 assert private.event_change_body('corrected', 'x', null, true, 'сб, 7 листопада о 18:30')
   = 'Подія все ж відбудеться — збір сб, 7 листопада о 18:30', 'R7 corrected';
 assert not private.quiet_hours('2026-10-20 06:30+00', 'Europe/Kyiv') and private.quiet_hours('2026-10-20 05:59+00', 'Europe/Kyiv')
   and not private.quiet_hours('2026-10-20 18:59+00', 'Europe/Kyiv') and private.quiet_hours('2026-10-20 19:00+00', 'Europe/Kyiv')
   and private.quiet_hours('2026-10-20 06:30+00', 'America/New_York'), '09:00–21:59 in the event zone';
 -- Вікно: вночі — на 09:00 (того ж ранку чи наступного), удень — одразу, менше 12 год до початку — одразу.
 assert private.change_send_after(t, 'Europe/Kyiv', '2026-10-20 20:30+00') = '2026-10-21 06:00+00', '23:30 → 09:00 next day';
 assert private.change_send_after(t, 'Europe/Kyiv', '2026-10-20 03:00+00') = '2026-10-20 06:00+00', '06:00 → 09:00 same day';
 assert private.change_send_after(t, 'Europe/Kyiv', '2026-10-20 10:00+00') = '2026-10-20 10:00+00', 'daytime: now';
 assert private.change_send_after('2026-10-21 02:00+00', 'Europe/Kyiv', '2026-10-20 20:30+00') = '2026-10-20 20:30+00',
   'under 12 hours: now even at night';
 assert private.change_send_after(t, 'America/New_York', '2026-10-20 10:00+00') = '2026-10-20 13:00+00', 'event zone, not Kyiv';
 assert private.quiet_hours('2026-10-20 19:30+00') and not private.quiet_hours('2026-10-20 10:00+00'), 'Kyiv version unchanged';
end $$;

-- ── 2. Перемикач вимкнено: лише тінь. Ввімкнення перераховує import_status, але пушів за минуле не шле.
select private.set_event_changes(false);
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_chg_a','off1','Тінь',pg_temp.t())));
select pg_temp.save('a','off1');
select pg_temp.chk('off1','cancelled','{"raw":"EventCancelled"}');
do $$ begin
 assert (pg_temp.st('off1')).state = 'cancelled' and exists (select 1 from private.would_send where event_id = pg_temp.ev('off1')),
   'shadow still writes would_send';
 assert pg_temp.q('off1') = '{}' and not exists (select 1 from pg_temp.sent), 'no push while off';
 assert pg_temp.import_status('off1') = 'live', 'client sees nothing while off';
end $$;
do $$ begin
 assert private.set_event_changes(true) >= 1, 'enabling recounts import_status';
 assert pg_temp.import_status('off1') = 'withdrawn', 'R3: cancelled state hides the event';
 assert pg_temp.q('off1') = '{}' and not exists (select 1 from pg_temp.sent), 'no pushes for changes before the switch';
end $$;

-- ── 3. Увімкнено: скасовано (один продавець, кілька), відкладено, перенесено. Повтор без дубля.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_chg_a','one','Один продавець',pg_temp.t()),
 pg_temp.w('test_chg_a','two','Два продавці',pg_temp.t()),
 pg_temp.w('test_chg_a','pp','Відкладена',pg_temp.t()),
 pg_temp.w('test_chg_a','mv','Перенесена',pg_temp.t())));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_chg_b','two_b','Два продавці',pg_temp.t(),'two')));
-- Другий продавець уже не продає: свіжий продаж проти «скасовано» — конфлікт (20261104130000_seller_report).
update public.event_offers set status = 'withdrawn', updated_at = now() where id = (pg_temp.offer('two_b')).id;
select pg_temp.save('a','one'), pg_temp.save('a','two'), pg_temp.save('a','pp'), pg_temp.save('a','mv');
select pg_temp.chk('one','cancelled','{"raw":"EventCancelled"}');
select pg_temp.chk('two','cancelled','{"raw":"EventCancelled"}');
select pg_temp.chk('pp','postponed','{"raw":"EventPostponed"}');
select pg_temp.chk('mv','rescheduled_away',jsonb_build_object('new_start',pg_temp.t('7 days')));
-- Повтор того самого свідчення й перерахунок — нічого нового.
select pg_temp.chk('one','cancelled','{"raw":"EventCancelled"}');
select private.refresh_event_state(pg_temp.ev('one'));
do $$ begin
 assert pg_temp.q('one') = array['a:cancelled · Скасовано. Якщо купили квиток — повернення в Concert.test'], 'one seller';
 assert pg_temp.q('two') = array['a:cancelled · Скасовано. Якщо купили квиток — повернення у продавця, де купували'], 'two sellers';
 assert pg_temp.q('pp') = array['a:postponed · Відкладено, нової дати ще нема'], 'postponed';
 assert pg_temp.q('mv') = array['a:moved · Перенесено на ' || private.when_uk(pg_temp.t('7 days'), 'Europe/Kyiv')], 'moved';
 assert (select count(*) from private.event_change_pushes where event_id = pg_temp.ev('one')) = 1, 'repeat: no second push';
 assert (select title from private.event_change_pushes where event_id = pg_temp.ev('one')) = 'Один продавець', 'title = event';
 -- R3 і час події за станом.
 assert pg_temp.import_status('one') = 'withdrawn' and pg_temp.import_status('two') = 'withdrawn'
   and pg_temp.import_status('pp') = 'withdrawn' and pg_temp.import_status('mv') = 'live', 'import_status follows the state';
 assert (select (starts_at, ends_at) from public.events where id = pg_temp.ev('mv')) = (pg_temp.t('7 days'), pg_temp.t('7 days 2 hours')),
   'moved event shows the new time';
end $$;
select pg_temp.flush();
do $$ begin
 assert (select count(*) from pg_temp.sent) = 4 and not exists (select 1 from private.event_change_pushes
   where event_id in (pg_temp.ev('one'), pg_temp.ev('two'), pg_temp.ev('pp'), pg_temp.ev('mv')) and sent_at is null), 'all sent';
 assert (select payload from pg_temp.sent where payload->>'event_id' = pg_temp.ev('pp')::text) = jsonb_build_object('type','change',
   'kind','cancelled','change','postponed','event_id',pg_temp.ev('pp'),'title','Відкладена','body','Відкладено, нової дати ще нема',
   'user_ids',jsonb_build_array(pg_temp.u('a'))), 'wire: known kind + exact change';
 assert (select payload->>'kind' from pg_temp.sent where payload->>'event_id' = pg_temp.ev('mv')::text) = 'moved', 'moved kind';
 assert pg_temp.flush() = 0, 'nothing twice';
end $$;

-- ── 4. Без сильного свідчення — тиша: зникла зі списку, 404 скрізь (unknown), розпродано, «в силі».
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_chg_a','quiet','Тиха',pg_temp.t()),
 pg_temp.w('test_chg_a','alive','Зникла, але жива',pg_temp.t())));
select pg_temp.save('a','quiet'), pg_temp.save('a','alive');
update public.event_offers set status = 'withdrawn', ingest_run_id = current_setting('test.run')::uuid, updated_at = now()
where id in ((pg_temp.offer('quiet')).id, (pg_temp.offer('alive')).id);
do $$ begin
 assert pg_temp.import_status('alive') = 'withdrawn', 'vanished, page not read yet: withdrawn as before';
end $$;
select pg_temp.chk('alive','scheduled','{"raw":"EventScheduled","sold_out":true}');
select pg_temp.chk('quiet','gone','{}',404);
do $$ declare l bigint; begin
 assert (pg_temp.st('quiet')).state = 'unknown' and pg_temp.import_status('quiet') = 'withdrawn', 'unknown hides the event';
 assert pg_temp.import_status('alive') = 'live', 'R3: the page says it is on, vanishing from the list is noise';
 assert pg_temp.q('quiet') = '{}' and pg_temp.q('alive') = '{}', 'no push without strong evidence';
 -- Запобіжник: зміна з would_push, але без сильного свідчення, пуша не дає.
 insert into private.event_state_log(event_id, from_state, to_state, from_starts_at, to_starts_at, change, evidence, would_push)
 values (pg_temp.ev('alive'), 'scheduled', 'cancelled', pg_temp.t(), pg_temp.t(), 'cancelled', '{"says":"listed"}', true)
 returning id into l;
 assert private.apply_event_change(l, true) = 0 and pg_temp.q('alive') = '{}', 'guard: strong evidence or silence';
end $$;

-- ── 5. Виправлення: лише тим, хто отримав помилкове. e зберегла вже після пуша; невідправлене — скасовується.
select pg_temp.save('e','one');
select pg_temp.chk('one','scheduled','{"raw":"EventScheduled"}');
do $$ begin
 assert (pg_temp.st('one')).state = 'scheduled' and pg_temp.import_status('one') = 'live', 'corrected, live again';
 assert pg_temp.q('one','corrected') = array['a:corrected · Подія все ж відбудеться: ' || private.when_uk(pg_temp.t(), 'Europe/Kyiv')],
   'correction only to the one who got the wrong push';
end $$;
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_chg_a','night','Нічна помилка',pg_temp.t())));
select pg_temp.save('a','night');
select pg_temp.chk('night','cancelled','{"raw":"EventCancelled"}');
update private.event_change_pushes set send_after = now() + interval '8 hours', sent_at = null
where event_id = pg_temp.ev('night');                                                                       -- чекає ранку
select pg_temp.chk('night','scheduled','{"raw":"EventScheduled"}');
do $$ begin
 assert (select skipped from private.event_change_pushes where event_id = pg_temp.ev('night') and change = 'cancelled') = 'corrected'
   and pg_temp.q('night') = '{}', 'wrong push not sent yet: dropped, and no correction either';
end $$;

-- ── 6. Після виправлення — два сильних свідчення поспіль.
select pg_temp.chk('one','cancelled','{"raw":"EventCancelled"}');
select private.refresh_event_state(pg_temp.ev('one'));                     -- те саме свідчення ще раз — не друге
do $$ begin
 assert (pg_temp.st('one')).state = 'scheduled' and (pg_temp.st('one')).unconfirmed->>'change' = 'cancelled', 'first one waits';
 assert pg_temp.q('one','cancelled') = array['a:cancelled · Скасовано. Якщо купили квиток — повернення в Concert.test']
   and (select count(*) from private.event_change_pushes where event_id = pg_temp.ev('one')) = 2, 'no new push yet';
 assert (select d.why from private.offer_checks_due(100000, now() + interval '2 hours') d where d.offer_id = (pg_temp.offer('one')).id)
   = 'conflict', 'rechecked hourly while waiting';
end $$;
-- Сторінка між ними каже «в силі» — очікування скидається; знову «скасовано» — знову перше.
select pg_temp.chk('one','scheduled','{"raw":"EventScheduled"}');
do $$ begin assert (pg_temp.st('one')).unconfirmed is null, 'alive in between resets'; end $$;
select pg_temp.chk('one','cancelled','{"raw":"EventCancelled"}');
do $$ begin assert (pg_temp.st('one')).state = 'scheduled', 'first again'; end $$;
select pg_temp.chk('one','cancelled','{"raw":"EventCancelled"}');
do $$ begin
 assert (pg_temp.st('one')).state = 'cancelled' and (pg_temp.st('one')).unconfirmed is null, 'second in a row applies';
 assert (select count(*) from private.event_change_pushes p where p.event_id = pg_temp.ev('one') and p.change = 'cancelled'
   and p.skipped is null) = 3, 'a again and e now';
end $$;

-- ── 7. Вікно: менше 12 год до початку — одразу; інакше 09:00–21:59 у поясі події, вночі — на 09:00.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_chg_a','soon','Скоро',now() + interval '6 hours'),
 pg_temp.w('test_chg_a','later','Пізніше',pg_temp.t())));
select pg_temp.save('a','soon'), pg_temp.save('a','later');
delete from pg_temp.sent;
select pg_temp.chk('soon','cancelled','{"raw":"EventCancelled"}');
select pg_temp.chk('later','cancelled','{"raw":"EventCancelled"}');
do $$ declare z text := 'Europe/Kyiv'; begin
 assert (select (send_after, sent_at) from private.event_change_pushes where event_id = pg_temp.ev('soon')) = (now(), now())
   and exists (select 1 from pg_temp.sent where payload->>'event_id' = pg_temp.ev('soon')::text), 'under 12 hours: right away';
 assert (select send_after from private.event_change_pushes where event_id = pg_temp.ev('later'))
   = private.change_send_after(pg_temp.t(), z), 'window in the event zone';
 assert (select sent_at is null from private.event_change_pushes where event_id = pg_temp.ev('later'))
   = private.quiet_hours(now(), z), 'night: waits for the hourly job';
end $$;
update private.event_change_pushes set send_after = now() + interval '1 hour', sent_at = null where event_id = pg_temp.ev('later');
do $$ begin
 assert private.flush_event_change_pushes() = 0, 'the hourly job sends nothing before its time';
end $$;

-- ── 8. R7: супутник іде за подією. b збирає, c — учасниця, що й зберегла подію, d — учасниця, заблокована з b.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_chg_a','pa','З компанією',pg_temp.t())));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_chg_b','pa_b','З компанією',pg_temp.t(),'pa')));
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,companion_of)
values (gen_random_uuid(),pg_temp.u('b'),'Йдемо разом: З компанією','Test description','music','Ocean','Buoy, 1',-40.5,-30.5,
 pg_temp.t('-30 minutes'),pg_temp.t('2 hours'),'Europe/Kyiv',4,pg_temp.ev('pa'));
select set_config('test.comp',(select id::text from public.events where companion_of = pg_temp.ev('pa')),true);
-- Блокування виселяє учасника (user_blocks_evict); блок до членства — запобіжник у черзі R6 однаково тримає.
insert into public.user_blocks(user_id,blocked_id) values (pg_temp.u('b'),pg_temp.u('d'));
insert into public.event_members(event_id,user_id,status) values (pg_temp.u('comp'),pg_temp.u('c'),'approved'),
 (pg_temp.u('comp'),pg_temp.u('d'),'approved');
select pg_temp.save('a','pa'), pg_temp.save('c','pa');
delete from pg_temp.sent;
-- Перенос — під JWT учасника (auth.uid() не null): службова зміна однаково проходить guard_companion.
select set_config('request.jwt.claim.sub', current_setting('test.c'), true);
select pg_temp.chk('pa','rescheduled_away',jsonb_build_object('new_start',pg_temp.t('1 day')));
select set_config('request.jwt.claim.sub', '', true);
do $$ declare meet text := private.when_uk(pg_temp.t('1 day -30 minutes'), 'Europe/Kyiv'); begin
 assert (select (starts_at, ends_at, status) from public.events where id = pg_temp.u('comp'))
   = (pg_temp.t('1 day -30 minutes'), pg_temp.t('1 day 2 hours'), 'published'::text), 'companion moved by the same delta';
 assert pg_temp.q('pa') = array[
   'a:moved · Перенесено на ' || private.when_uk(pg_temp.t('1 day'), 'Europe/Kyiv'),
   'b:moved · супутник · Подію перенесли — збір тепер ' || meet,
   'c:moved · супутник · Подію перенесли — збір тепер ' || meet], 'saver R6; organizer and member R7 once; blocked member nothing';
 assert (select title from private.event_change_pushes where event_id = pg_temp.ev('pa') and user_id = pg_temp.u('b'))
   = 'Йдемо разом: З компанією', 'companion title';
 assert not exists (select 1 from pg_temp.sent where payload->>'type' = 'event'), 'events_push stays silent';
end $$;
select pg_temp.flush();
-- Продавець відкликав перенос: той самий сеанс знову «в силі» на старий час — подія й збір повертаються.
select pg_temp.chk('pa','scheduled','{"raw":"EventScheduled"}');
do $$ declare meet text := private.when_uk(pg_temp.t('-30 minutes'), 'Europe/Kyiv'); begin
 assert (select starts_at from public.events where id = pg_temp.u('comp')) = pg_temp.t('-30 minutes')
   and (select starts_at from public.events where id = pg_temp.ev('pa')) = pg_temp.t(), 'both back';
 assert pg_temp.q('pa','corrected') = array[
   'a:corrected · Подія все ж відбудеться: ' || private.when_uk(pg_temp.t(), 'Europe/Kyiv'),
   'b:corrected · супутник · Подія все ж відбудеться — збір ' || meet,
   'c:corrected · супутник · Подія все ж відбудеться — збір ' || meet], 'correction with the meeting time';
end $$;
select pg_temp.flush();

-- Скасування закриває збір; виправлення (після двох поспіль — це вже друга зміна після виправлення) відкриває.
-- Другий продавець уже не продає: свіжий продаж проти «скасовано» — конфлікт (20261104130000_seller_report).
update public.event_offers set status = 'withdrawn', updated_at = now() where id = (pg_temp.offer('pa_b')).id;
select pg_temp.chk('pa','cancelled','{"raw":"EventCancelled"}');
select pg_temp.chk('pa','cancelled','{"raw":"EventCancelled"}');
do $$ begin
 assert (select status from public.events where id = pg_temp.u('comp')) = 'cancelled'
   and exists (select 1 from private.companion_closures where companion_id = pg_temp.u('comp')), 'companion closed with the event';
 assert pg_temp.q('pa','cancelled') = array[
   'a:cancelled · Скасовано. Якщо купили квиток — повернення у продавця, де купували',
   'b:cancelled · супутник · Подію скасували, тож збір скасовано',
   'c:cancelled · супутник · Подію скасували, тож збір скасовано'], 'R7 cancelled text';
 assert not exists (select 1 from pg_temp.sent where payload->>'type' = 'event'), 'still silent';
end $$;
select pg_temp.flush();
select pg_temp.chk('pa','scheduled','{"raw":"EventScheduled"}');
do $$ begin
 assert (select status from public.events where id = pg_temp.u('comp')) = 'published'
   and not exists (select 1 from private.companion_closures where companion_id = pg_temp.u('comp')), 'companion reopened';
 assert (select count(*) from private.event_change_pushes where event_id = pg_temp.ev('pa') and change = 'corrected') = 6,
   'second correction to the same three';
end $$;
-- Відкладення теж закриває (новий супутник іншої події).
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_chg_a','pb','Відкладена з компанією',pg_temp.t())));
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,companion_of)
values (gen_random_uuid(),pg_temp.u('b'),'Йдемо разом: Відкладена','Test description','music','Ocean','Buoy, 1',-40.5,-30.5,
 pg_temp.t('-30 minutes'),pg_temp.t('2 hours'),'Europe/Kyiv',4,pg_temp.ev('pb'));
select pg_temp.chk('pb','postponed','{"raw":"EventPostponed"}');
do $$ begin
 assert (select status from public.events where companion_of = pg_temp.ev('pb')) = 'cancelled', 'postponed closes too';
 assert pg_temp.q('pb') = array['b:postponed · супутник · Подію відклали, тож збір скасовано'], 'R7 postponed text';
end $$;

-- ── 9. Вимкнули — черга мовчить, import_status знову за списком.
update private.event_change_pushes set send_after = now() where sent_at is null and skipped is null;
do $$ begin
 assert private.set_event_changes(false) >= 1 and pg_temp.import_status('off1') = 'live', 'off: back to the listing';
 assert private.flush_event_change_pushes() = 0, 'off: nothing is sent';
end $$;

rollback;
select 'PASS: R6 texts row by row, switch (shadow only, no retro pushes), silence without strong evidence, repeat without duplicate, correction only to those who got it, two in a row after a correction, window, R3 import_status, R7 companion follows the event' as result;

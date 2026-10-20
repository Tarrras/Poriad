-- Запускати адміністратором бази. Усе відкочується. Стан події з усіх продавців і адресна перевірка у тіні
-- (docs/event-offers.md, фаза 2: R4–R5): правило на кожен рядок таблиці R4, липке «скасовано», захисти тихого
-- переносу, конфлікт agent-пропозиції, перенос з дампу, слоти R5 і ліміт раз на годину, «б надіслали» — і клієнт
-- нічого з цього не бачить.
begin;

create or replace function private.notify_push(p_payload jsonb) returns void language plpgsql security definer
 set search_path='' as $$ begin end $$;

select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.c',gen_random_uuid()::text,true),set_config('test.run',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-state-'||id||'@example.invalid',jsonb_build_object('display_name','S','birth_date','1990-01-01')
from unnest(array[current_setting('test.a'),current_setting('test.b'),current_setting('test.c')]) id;
insert into public.event_sources(slug,name,kind,base_url,weight,enabled) values
 ('test_state_a','Продавець А','manual','https://example.invalid',0.8,true),
 ('test_state_b','Продавець Б','manual','https://example.invalid',0.7,true);
-- Сеанс через 10 днів о 19:00 за Києвом.
select set_config('test.t',(((now() at time zone 'Europe/Kyiv')::date + 10 + time '19:00') at time zone 'Europe/Kyiv')::text,true);

create function pg_temp.t(p_shift interval default '0') returns timestamptz language sql as $$
 select current_setting('test.t')::timestamptz + p_shift $$;
create function pg_temp.w(p_slug text, p_uid text, p_title text, p_start timestamptz) returns jsonb language sql as $$
 select jsonb_build_object('id',gen_random_uuid(),'slug',p_slug,'uid',p_uid,'url','https://example.invalid/'||p_uid,
  'title',p_title,'description','','category','music','city','Ocean','address','Buoy, 1','lat',-40.5,'lon',-30.5,
  'starts',p_start,'ends',p_start+interval '2 hours','tz','Europe/Kyiv','dedupe','x','quality',0.9,'price',300) $$;
create function pg_temp.c(p_slug text, p_uid text, p_title text, p_start timestamptz, p_wuid text,
 p_linked text default 'rule') returns jsonb language sql as $$
 select jsonb_build_object('slug',p_slug,'uid',p_uid,'url','https://example.invalid/'||p_uid,'title',p_title,
  'starts',p_start,'price',250,'winner_slug','test_state_a','winner_uid',p_wuid,'linked',p_linked) $$;
create function pg_temp.ingest(p_rows jsonb) returns integer language sql as $$
 select private.ingest_offers(current_setting('test.run')::uuid, p_rows) $$;
create function pg_temp.offer(p_uid text) returns public.event_offers language sql as $$
 select o.* from public.event_offers o join public.event_sources s on s.id=o.source_id
 where s.slug like 'test_state_%' and o.source_uid=p_uid $$;
create function pg_temp.ev(p_uid text) returns uuid language sql as $$ select (pg_temp.offer(p_uid)).event_id $$;
-- Те, що віддає Edge Function offer-check: вердикт сторінки про поточний сеанс пропозиції.
create function pg_temp.chk(p_uid text, p_verdict text, p_detail jsonb default '{}', p_http integer default 200,
 p_redirected boolean default false) returns integer language sql as $$
 select private.record_offer_checks(jsonb_build_array(jsonb_build_object('offer_id',o.id,'why','vanished',
  'expected',o.starts_at,'url',o.canonical_url,'http',p_http,'redirected',p_redirected,'verdict',p_verdict,'detail',p_detail)))
 from pg_temp.offer(p_uid) o $$;
create function pg_temp.st(p_uid text) returns private.event_state language sql as $$
 select * from private.event_state where event_id=pg_temp.ev(p_uid) $$;
create function pg_temp.logs(p_uid text) returns bigint language sql as $$
 select count(*) from private.event_state_log where event_id=pg_temp.ev(p_uid) $$;
create function pg_temp.due(p_uid text, p_now timestamptz default now()) returns text language sql as $$
 select d.why from private.offer_checks_due(100000, p_now) d where d.offer_id=(pg_temp.offer(p_uid)).id $$;
-- Що бачить клієнт: деталі (як 1.3.0) — до й після мають збігатися.
create function pg_temp.seen(p_uid text) returns text language sql as $$
 select row(d.*)::text from public.event_details(pg_temp.ev(p_uid)) d $$;

-- ── 1. Таблиця R4 рядок за рядком: чиста функція правил.
create function pg_temp.o(p_says text, p_linked text default 'rule', p_new timestamptz default null,
 p_at timestamptz default now()) returns jsonb language sql as $$
 select jsonb_build_object('offer_id',gen_random_uuid(),'says',p_says,'linked',p_linked,'new_start',p_new,'at',p_at) $$;
do $$ declare t timestamptz := pg_temp.t(); r record; begin
 -- Сильне «скасовано», жодна інша пропозиція не каже сильно протилежне → cancelled, пуш.
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('cancelled'), pg_temp.o('alive')));
 assert (r.state, r.change, r.push) = ('cancelled', 'cancelled', true), 'R4.1 cancelled';
 -- Сильне «скасовано» лише від agent-пропозиції, інші продають → конфлікт: стан той самий, пуша нема.
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('cancelled','agent'), pg_temp.o('listed')));
 assert (r.state, r.change, r.push) = ('scheduled', 'conflict', false), 'R4.2 conflict';
 -- …і для переносу (тлумачення 20.10); але без живих продавців agent-«скасовано» діє.
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('moved','agent',t+interval '1 day'), pg_temp.o('alive')));
 assert r.change = 'conflict' and r.starts_at = t, 'R4.2 conflict on a move';
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('cancelled','agent'), pg_temp.o('gone')));
 assert r.change = 'cancelled', 'R4.2 agent alone';
 -- Сильне «відкладено», нової дати нема → postponed, пуш.
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('postponed')));
 assert (r.state, r.change, r.push) = ('postponed', 'postponed', true), 'R4.3 postponed';
 -- Сильне «перенесено» з новою датою → scheduled, нова дата, пуш «перенесено».
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('moved','rule',t+interval '7 days'), pg_temp.o('alive')));
 assert (r.state, r.starts_at, r.change, r.push) = ('scheduled', t+interval '7 days', 'moved', true), 'R4.4 rescheduled';
 -- Тихий перенос на годину того ж дня — теж перенос; перенос важить більше за «скасовано» іншого продавця.
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('moved','rule',t-interval '1 hour'), pg_temp.o('cancelled')));
 assert (r.starts_at, r.change, r.push) = (t-interval '1 hour', 'moved', true), 'R4.5 silent move beats cancel';
 -- Перенос, який стан уже має, — не зміна (повтор дампу не дає другого пуша).
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('moved','rule',t)));
 assert r.change is null, 'R4.5 applied move is no change';
 -- Продавці переносять на різний час / різні дати без сильного свідчення → без змін.
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('moved','rule',t+interval '1 day'), pg_temp.o('moved','rule',t+interval '2 days')));
 assert r.change is null and r.starts_at = t, 'R4.6 disagreeing moves';
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('listed'), pg_temp.o('alive')));
 assert r.change is null, 'R4.6 weak only';
 -- Зникла зі списку, сторінку ще не читали → не свідчення.
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('none'), pg_temp.o('gone')));
 assert r.change is null, 'R4.7 vanished is not evidence';
 -- EventScheduled / розпродано → пропозиція жива, змін нема.
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('alive')));
 assert r.change is null, 'R4.8 scheduled';
 -- 404 чи перенаправлення на список однієї пропозиції → без змін; усі gone → unknown без пуша.
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('gone'), pg_temp.o('listed')));
 assert r.change is null, 'R4.9 one gone';
 select * into r from private.event_state_rule('scheduled', t, jsonb_build_array(pg_temp.o('gone'), pg_temp.o('gone')));
 assert (r.state, r.change, r.push) = ('unknown', 'unknown', false), 'R4.10 all gone';
 select * into r from private.event_state_rule('unknown', t, jsonb_build_array(pg_temp.o('gone'), pg_temp.o('listed')));
 assert (r.state, r.change, r.push) = ('scheduled', 'restored', false), 'R4.10 back in the listing';
 -- Був cancelled/postponed, сторінка знову каже «в силі» → scheduled, пуш-виправлення; самого списку мало.
 select * into r from private.event_state_rule('cancelled', t, jsonb_build_array(pg_temp.o('alive'), pg_temp.o('gone')));
 assert (r.state, r.change, r.push) = ('scheduled', 'corrected', true), 'R4.11 correction';
 select * into r from private.event_state_rule('postponed', t, jsonb_build_array(pg_temp.o('listed')));
 assert r.change is null, 'R4.11 listing alone does not correct';
 select * into r from private.event_state_rule('cancelled', t, jsonb_build_array(pg_temp.o('cancelled'), pg_temp.o('alive')));
 assert r.change is null, 'R4.11 still cancelled by one seller';
end $$;

-- ── 2. Скасування від сторінки: липке, ідемпотентне, у «б надіслали» — тим, хто стежить; клієнт не бачить.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s1a','Концерт Один',pg_temp.t())));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_state_b','s1b','Концерт Один',pg_temp.t(),'s1a')));
insert into public.saved_events(user_id,event_id) values (current_setting('test.a')::uuid, pg_temp.ev('s1a'));
create temp table seen_before on commit drop as select pg_temp.seen('s1a') v;
select pg_temp.chk('s1a','cancelled','{"raw":"EventCancelled","sold_out":false}');
select pg_temp.chk('s1b','scheduled','{"raw":"EventScheduled","sold_out":true}');   -- інший продавець продає (слабке)
select pg_temp.chk('s1a','cancelled','{"raw":"EventCancelled","sold_out":false}');  -- повтор
select pg_temp.chk('s1a','gone','{}',404);                                           -- сторінку прибрали
do $$ declare s private.event_state := pg_temp.st('s1a'); w record; begin
 assert pg_temp.ev('s1a') = pg_temp.ev('s1b'), 'one event, two sellers';
 assert s.state = 'cancelled' and s.evidence->>'kind' = 'jsonld' and s.evidence->>'slug' = 'test_state_a', 'cancelled by the page';
 assert s.checked_at is not null, 'checked_at';
 assert pg_temp.logs('s1a') = 1, 'repeat and 404 add nothing: cancel is sticky';
 select * into w from private.would_send where event_id = pg_temp.ev('s1a');
 assert w.user_id = current_setting('test.a')::uuid and w.change = 'cancelled', 'would send to the one who saved';
 assert pg_temp.seen('s1a') = (select v from seen_before), 'client sees exactly the same';
 assert (select import_status from public.events where id = pg_temp.ev('s1a')) = 'live', 'import_status untouched';
end $$;
-- Продавець відкликав: та сама сторінка знову «в силі» → виправлення.
select pg_temp.chk('s1a','scheduled','{"raw":"EventScheduled","sold_out":false}');
do $$ begin
 assert (pg_temp.st('s1a')).state = 'scheduled', 'corrected';
 assert (select change from private.event_state_log where event_id = pg_temp.ev('s1a') order by id desc limit 1) = 'corrected'
   and (select count(*) from private.would_send where event_id = pg_temp.ev('s1a')) = 2, 'correction would go to the same person';
end $$;

-- ── 3. Конфлікт: «скасовано» лише від agent-пропозиції → перевірити всі ще раз → двічі поспіль → черга від'єднання.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s2a','Вистава Два',pg_temp.t())));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_state_b','s2b','Вистава Два',pg_temp.t(),'s2a','agent')));
select pg_temp.chk('s2b','cancelled');
do $$ begin
 assert (pg_temp.st('s2b')).state = 'scheduled' and (pg_temp.st('s2b')).conflicts = 1, 'conflict keeps the state';
 assert pg_temp.due('s2a', now() + interval '2 hours') = 'conflict' and pg_temp.due('s2b', now() + interval '2 hours') = 'conflict',
   'all offers rechecked';
 assert not exists (select 1 from private.would_send where event_id = pg_temp.ev('s2a')), 'no push on conflict';
end $$;
select pg_temp.chk('s2b','cancelled');
do $$ begin
 assert (pg_temp.st('s2b')).conflicts = 2 and exists (select 1 from private.offer_detach_queue where offer_id = (pg_temp.offer('s2b')).id),
   'queued for detaching after two checks';
 assert pg_temp.due('s2a', now() + interval '2 hours') is null, 'no endless rechecking';
end $$;

-- ── 4. Відкладено; перенесено з датою; тихий перенос і його захисти.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s3a','Відкладений',pg_temp.t()),
 pg_temp.w('test_state_a','s3b','Відкладений без дати',pg_temp.t()+interval '1 day'),
 pg_temp.w('test_state_a','s4a','Перенесений',pg_temp.t()),
 pg_temp.w('test_state_a','s5a','Іво Бобул',pg_temp.t()),
 pg_temp.w('test_state_a','s5b','Чужий концерт',pg_temp.t()),
 pg_temp.w('test_state_a','s5c','Далекий',pg_temp.t())));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_state_b','s5bb','Чужий концерт',pg_temp.t(),'s5b'),
 pg_temp.c('test_state_b','s5cb','Далекий',pg_temp.t(),'s5c')));
create temp table moved_before on commit drop as select pg_temp.seen('s4a') v;
select pg_temp.chk('s3a','postponed','{"raw":"EventPostponed","sold_out":false}');
select pg_temp.chk('s3b','rescheduled_away','{"new_start":null}');
select pg_temp.chk('s4a','rescheduled_away',jsonb_build_object('new_start',pg_temp.t('7 days')));
select pg_temp.chk('s5a','moved_silent',jsonb_build_object('new_start',pg_temp.t('-1 hour'),'name','ІВО БОБУЛ!','statuses',array['EventScheduled']));
select pg_temp.chk('s5b','moved_silent',jsonb_build_object('new_start',pg_temp.t('-1 hour'),'name','Зовсім інша подія'));
select pg_temp.chk('s5c','moved_silent',jsonb_build_object('new_start',pg_temp.t('100 days'),'name','Далекий'));
do $$ begin
 assert (pg_temp.st('s3a')).state = 'postponed' and (pg_temp.st('s3b')).state = 'postponed', 'postponed, with and without EventRescheduled';
 assert ((pg_temp.st('s4a')).state, (pg_temp.st('s4a')).starts_at, (pg_temp.st('s4a')).previous_starts_at)
   = ('scheduled', pg_temp.t('7 days'), pg_temp.t()), 'rescheduled with the new date';
 assert (pg_temp.st('s5a')).starts_at = pg_temp.t('-1 hour') and (pg_temp.st('s5a')).evidence->>'verdict' = 'moved_silent',
   'silent move an hour earlier, the title written differently';
 -- Інша назва — адресу віддали іншій події; понад 90 днів — теж не перенос. Інший продавець продає → без змін.
 assert (pg_temp.st('s5b')).state = 'scheduled' and (pg_temp.st('s5b')).starts_at = pg_temp.t() and pg_temp.logs('s5b') = 0, 'other title';
 assert (pg_temp.st('s5c')).starts_at = pg_temp.t() and pg_temp.logs('s5c') = 0, 'beyond 90 days';
 assert pg_temp.seen('s4a') = (select v from moved_before) and (select starts_at from public.events where id = pg_temp.ev('s4a')) = pg_temp.t(),
   'client still sees the old time';
end $$;

-- Дамп переніс сеанс пропозиції (усиновлення фази 1): тригер пише свідчення listing — подію переносить і без сторінки.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s5d','Тихий у списку',pg_temp.t())));
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s5d','Тихий у списку',pg_temp.t('30 minutes'))));
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s5d','Тихий у списку',pg_temp.t('30 minutes'))));
do $$ begin
 assert (pg_temp.st('s5d')).starts_at = pg_temp.t('30 minutes') and (pg_temp.st('s5d')).evidence->>'kind' = 'listing',
   'move seen by the dump';
 assert pg_temp.logs('s5d') = 1, 'second identical dump: no second change';
end $$;

-- ── 5. Різні дати без сильного свідчення: без змін, у звіті.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s6a','Розбіжність дат',pg_temp.t())));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_state_b','s6b','Розбіжність дат',pg_temp.t('30 minutes'),'s6a')));
select pg_temp.chk('s6b','scheduled');
do $$ begin
 assert (pg_temp.st('s6a')).starts_at = pg_temp.t() and pg_temp.logs('s6a') = 0, 'no change on weak disagreement';
 assert exists (select 1 from private.shadow_report(7) r where r.section = 'розбіжність дат' and r.label = 'Розбіжність дат'),
   'disagreement is in the report';
end $$;

-- ── 6. Зникла зі списку → сторінку прочитати; EventScheduled чи розпродано — шум; збій не рахується (до трьох спроб).
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s7a','Зникла',pg_temp.t()),
 pg_temp.w('test_state_a','s8a','Розпродана',pg_temp.t())));
update public.event_offers set status = 'withdrawn', ingest_run_id = current_setting('test.run')::uuid, updated_at = now()
where id in ((pg_temp.offer('s7a')).id, (pg_temp.offer('s8a')).id);
do $$ begin
 assert pg_temp.due('s7a') = 'vanished', 'vanished offer is due';
 assert (select import_status from public.events where id = pg_temp.ev('s7a')) = 'withdrawn', 'phase 1 still shows withdrawn';
end $$;
select pg_temp.chk('s8a','scheduled','{"raw":"EventScheduled","sold_out":true}');
select pg_temp.chk('s7a','error','{"error":"HTTP 503"}',503);
select pg_temp.chk('s7a','error','{}',403);
do $$ begin
 assert (pg_temp.st('s8a')).state = 'scheduled' and pg_temp.logs('s8a') = 0, 'sold out is not a state';
 assert pg_temp.due('s8a', now() + interval '2 hours') is null, 'read once after vanishing';
 assert pg_temp.due('s7a') is null, 'not more often than once an hour per page';
 assert pg_temp.due('s7a', now() + interval '2 hours') = 'vanished' and (pg_temp.st('s7a')).event_id is not null
   and (pg_temp.st('s7a')).state = 'scheduled' and pg_temp.logs('s7a') = 0, 'failure changes nothing, retried';
end $$;
select pg_temp.chk('s7a','error','{}',0);
do $$ begin assert pg_temp.due('s7a', now() + interval '2 hours') is null, 'three failures: give up'; end $$;

-- ── 7. 404 і перенаправлення: одна gone — без змін; усі — unknown без пуша; знову в списку — назад.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s9a','Зникла всюди',pg_temp.t())));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_state_b','s9b','Зникла всюди',pg_temp.t(),'s9a')));
select pg_temp.chk('s9a','gone','{}',410);
do $$ begin assert pg_temp.logs('s9a') = 0, 'one seller gone'; end $$;
select pg_temp.chk('s9b','redirect_away','{}',200,true);
do $$ begin
 assert (pg_temp.st('s9a')).state = 'unknown' and not exists (select 1 from private.would_send where event_id = pg_temp.ev('s9a')),
   'unknown, silently';
end $$;
update public.event_offers set seen_at = clock_timestamp() where id = (pg_temp.offer('s9b')).id;
select private.refresh_event_state(pg_temp.ev('s9a'));
do $$ begin assert (pg_temp.st('s9a')).state = 'scheduled', 'back in the listing'; end $$;

-- ── 8. Хто стежить: зберегли, організатор і підтверджені учасники супутника.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_state_a','s10a','З компанією',pg_temp.t())));
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,companion_of)
values (gen_random_uuid(),current_setting('test.b')::uuid,'Йдемо разом','Test description','music','Ocean','Buoy, 1',-40.5,-30.5,
 pg_temp.t('-1 hour'),pg_temp.t('3 hours'),'Europe/Kyiv',4,pg_temp.ev('s10a'));
insert into public.event_members(event_id,user_id,status)
select id, current_setting('test.c')::uuid, 'approved' from public.events where companion_of = pg_temp.ev('s10a');
insert into public.saved_events(user_id,event_id) values (current_setting('test.a')::uuid, pg_temp.ev('s10a'));
do $$ begin
 assert private.event_watchers(pg_temp.ev('s10a')) @> array[current_setting('test.a'),current_setting('test.b'),current_setting('test.c')]::uuid[]
   and cardinality(private.event_watchers(pg_temp.ev('s10a'))) = 3, 'watchers';
end $$;

-- ── 9. Слоти R5 для тих, за ким стежать: за добу, о 09:00 у день події, за 3 години; зроблене не повторюється.
do $$ declare t timestamptz := pg_temp.t(); morning timestamptz := ((t at time zone 'Europe/Kyiv')::date + time '09:00') at time zone 'Europe/Kyiv';
 o uuid := (pg_temp.offer('s10a')).id; begin
 assert pg_temp.due('s10a', t - interval '25 hours') is null, 'too early';
 assert pg_temp.due('s10a', t - interval '23 hours') = 'day_before', 'a day before';
 assert pg_temp.due('s10a', morning + interval '30 minutes') = 'morning', '09:00 on the day';
 assert pg_temp.due('s10a', t - interval '2 hours') = 'three_hours', '3 hours before';
 assert pg_temp.due('s10a', t + interval '1 hour') is null, 'started';
 insert into private.offer_checks(offer_id, checked_at, why, expected, url, http, verdict)
 values (o, morning + interval '31 minutes', 'morning', (pg_temp.offer('s10a')).starts_at, (pg_temp.offer('s10a')).canonical_url, 200, 'scheduled');
 assert pg_temp.due('s10a', morning + interval '40 minutes') is null, 'once an hour per page';
 assert pg_temp.due('s10a', morning + interval '3 hours') is null, 'morning slot done';
 assert pg_temp.due('s10a', t - interval '2 hours') = 'three_hours', 'next slot still due';
end $$;

-- ── 10. Звіт тіні збирається; без сильного свідчення пуша б не було.
do $$ begin
 assert (select count(*) from private.shadow_report(7) where section = 'точність') = 1, 'accuracy row';
 assert exists (select 1 from private.shadow_report(7) where section = 'аудит' and note like 'https://example.invalid/%'), 'audit sample';
 assert not exists (select 1 from private.event_state_log where would_push and event_id in (select event_id from public.event_offers o
   join public.event_sources s on s.id = o.source_id where s.slug like 'test_state_%')
   and coalesce(evidence->>'says', '') not in ('cancelled','postponed','moved','alive')), 'push only on strong evidence';
end $$;

rollback;
select 'PASS: R4 table row by row, sticky cancel, correction, agent conflict, silent move guards, dump moves, R5 slots and hourly limit, would-send, clients see nothing' as result;

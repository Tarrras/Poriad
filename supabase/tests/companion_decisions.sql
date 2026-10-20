-- Запускати адміністратором бази. Усе відкочується. R7а і R7б (docs/event-offers.md): після переносу афіші збір
-- організатора, що може відповісти (токен 1.4 з `companion_decision`), не зсувається, а чекає рішення; решта — як у
-- фазі 3; тексти; повторний перенос накопичує, повернення знімає питання; строк і тихі години; move_companion з
-- межами create_companion; guard_companion і далі тримає збір; скасування події знімає питання; клієнт бачить питання.
begin;

create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
update private.flags set enabled = true where name = 'event_changes';

select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.c',gen_random_uuid()::text,true),set_config('test.e',gen_random_uuid()::text,true),
 set_config('test.run',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-decide-'||id||'@example.invalid',jsonb_build_object('display_name','D','birth_date','1990-01-01')
from unnest(array[current_setting('test.a'),current_setting('test.b'),current_setting('test.c'),current_setting('test.e')]) id;
insert into public.event_sources(slug,name,kind,base_url,weight,enabled) values
 ('test_dec_a','Concert.test','manual','https://example.invalid',0.8,true);
-- Сеанс через 10 днів о 19:00 за Києвом.
select set_config('test.t',(((now() at time zone 'Europe/Kyiv')::date + 10 + time '19:00') at time zone 'Europe/Kyiv')::text,true);

create function pg_temp.t(p_shift interval default '0') returns timestamptz language sql as $$
 select current_setting('test.t')::timestamptz + p_shift $$;
create function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('test.'||p)::uuid $$;
create function pg_temp.as_user(p text) returns void language sql as $$
 select set_config('request.jwt.claim.sub', coalesce(current_setting('test.'||p, true), ''), true) $$;
create function pg_temp.w(p_uid text, p_title text, p_start timestamptz) returns jsonb language sql as $$
 select jsonb_build_object('id',gen_random_uuid(),'slug','test_dec_a','uid',p_uid,'url','https://example.invalid/'||p_uid,
  'title',p_title,'description','','category','music','city','Ocean','address','Buoy, 1','lat',-40.5,'lon',-30.5,
  'starts',p_start,'ends',p_start+interval '2 hours','tz','Europe/Kyiv','dedupe','x','quality',0.9,'price',300) $$;
create function pg_temp.offer(p_uid text) returns public.event_offers language sql as $$
 select o.* from public.event_offers o join public.event_sources s on s.id=o.source_id
 where s.slug = 'test_dec_a' and o.source_uid=p_uid $$;
create function pg_temp.ev(p_uid text) returns uuid language sql as $$ select (pg_temp.offer(p_uid)).event_id $$;
create function pg_temp.chk(p_uid text, p_verdict text, p_detail jsonb default '{}') returns integer language sql as $$
 select private.record_offer_checks(jsonb_build_array(jsonb_build_object('offer_id',o.id,'why','vanished',
  'expected',o.starts_at,'url',o.canonical_url,'http',200,'verdict',p_verdict,'detail',p_detail)))
 from pg_temp.offer(p_uid) o $$;
create function pg_temp.moved_to(p_uid text, p_start timestamptz) returns integer language sql as $$
 select pg_temp.chk(p_uid,'rescheduled_away',jsonb_build_object('new_start',p_start)) $$;
-- Збір на подію [p_uid]: організатор [p_who], зустріч [p_meet].
create function pg_temp.companion(p_uid text, p_who text, p_meet timestamptz) returns uuid language sql as $$
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,companion_of)
 select gen_random_uuid(),pg_temp.u(p_who),'Йдемо разом: '||e.title,'Test description','music','Ocean','Buoy, 1',-40.5,-30.5,
  p_meet,e.ends_at,'Europe/Kyiv',4,e.id from public.events e where e.id = pg_temp.ev(p_uid) returning id $$;
create function pg_temp.meet(p_id uuid) returns timestamptz language sql as $$ select starts_at from public.events where id = p_id $$;
create function pg_temp.decision(p_id uuid) returns private.companion_decisions language sql as $$
 select * from private.companion_decisions where companion_id = p_id $$;
-- Черга R6 події після останнього done(): «людина · текст» у сталому порядку. Удень черга йде одразу, тож не за sent_at.
create function pg_temp.q(p_uid text) returns text[] language sql as $$
 select coalesce(array_agg(x order by x), '{}') from (
  select case p.user_id when pg_temp.u('a') then 'a' when pg_temp.u('b') then 'b' when pg_temp.u('c') then 'c'
               when pg_temp.u('e') then 'e' end || ' · ' || p.body as x
  from private.event_change_pushes p where p.event_id = pg_temp.ev(p_uid) and p.skipped is null
   and p.id > coalesce(nullif(current_setting('test.mark', true), ''), '0')::bigint) s $$;
create function pg_temp.done(p_uid text) returns void language sql as $$
 select set_config('test.mark', (select coalesce(max(id), 0) from private.event_change_pushes)::text, true);
 update private.event_change_pushes set sent_at = now() where event_id = pg_temp.ev(p_uid) and sent_at is null $$;
create function pg_temp.w_uk(p_at timestamptz) returns text language sql as $$ select private.when_uk(p_at, 'Europe/Kyiv') $$;

-- ── 1. Тексти й формат часу.
do $$ declare t timestamptz := '2026-11-07 17:00+00'; begin
 assert private.meet_uk(t + interval '2 hours', t, 'Europe/Kyiv') = '21:00', 'same day: hour only';
 assert private.meet_uk(t + interval '1 day', t, 'Europe/Kyiv') = 'нд, 8 листопада о 19:00', 'other day: full date';
 assert private.companion_decision_body('ask', 'сб, 7 листопада о 21:00', 'о 19:30', '21:30')
   = 'Подію перенесли на сб, 7 листопада о 21:00. Ваш збір о 19:30 — перенести на 21:30?';
 assert private.companion_decision_body('wait', 'сб, 7 листопада о 21:00')
   = 'Подію перенесли на сб, 7 листопада о 21:00. Організатор вирішує, о котрій тепер збір';
 assert private.companion_decision_body('auto', null, null, '21:30') = 'Ми пересунули збір на 21:30. Змінити можна тут';
 assert private.companion_decision_body('moved', null, null, 'сб, 7 листопада о 21:30') = 'Збір перенесли на сб, 7 листопада о 21:30';
end $$;

-- ── 2. Хто може відповісти: токен 1.4 з позначкою; 1.3 реєструє тим самим викликом з двома параметрами.
select pg_temp.as_user('b');
select public.register_push_token('token-b-1.4-0000000000', 'ios', array['companion_decision']);
select pg_temp.as_user('e');
select public.register_push_token('token-e-1.3-0000000000', 'android');
select pg_temp.as_user('x');
do $$ begin
 assert private.can_decide(pg_temp.u('b')) and not private.can_decide(pg_temp.u('e')), 'only the 1.4 token decides';
 update public.push_tokens set updated_at = now() - interval '31 days' where user_id = pg_temp.u('b');
 assert not private.can_decide(pg_temp.u('b')), 'stale token does not count';
 update public.push_tokens set updated_at = now() where user_id = pg_temp.u('b');
end $$;

-- ── 3. Перенос +2 год: збір b (1.4) чекає рішення, збір e (1.3) зсувається одразу. c — учасниця збору b, a зберіг подію.
select private.ingest_offers(current_setting('test.run')::uuid, jsonb_build_array(pg_temp.w('pa','З компанією',pg_temp.t())));
select set_config('test.cb', pg_temp.companion('pa','b',pg_temp.t('-30 minutes'))::text, true),
       set_config('test.ce', pg_temp.companion('pa','e',pg_temp.t('-1 hour'))::text, true);
insert into public.event_members(event_id,user_id,status) values (pg_temp.u('cb'),pg_temp.u('c'),'approved');
insert into public.saved_events(user_id,event_id) values (pg_temp.u('a'), pg_temp.ev('pa'));
select pg_temp.moved_to('pa', pg_temp.t('2 hours'));
do $$ declare d private.companion_decisions := pg_temp.decision(pg_temp.u('cb')); begin
 assert pg_temp.meet(pg_temp.u('cb')) = pg_temp.t('-30 minutes'), 'deciding companion stays';
 assert d.proposed_at = pg_temp.t('90 minutes'), 'proposal: same difference';
 assert d.decide_by <= d.proposed_at - interval '3 hours' and d.decide_by > now(), 'deadline: 12 h but 3 h before';
 assert pg_temp.meet(pg_temp.u('ce')) = pg_temp.t('1 hour') and pg_temp.decision(pg_temp.u('ce')) is null, '1.3: shifted at once';
 assert pg_temp.q('pa') = array[
   'a · Перенесено на ' || pg_temp.w_uk(pg_temp.t('2 hours')),
   'b · Подію перенесли на ' || pg_temp.w_uk(pg_temp.t('2 hours')) || '. Ваш збір о 18:30 — перенести на 20:30?',
   'c · Подію перенесли на ' || pg_temp.w_uk(pg_temp.t('2 hours')) || '. Організатор вирішує, о котрій тепер збір',
   'e · Подію перенесли — збір тепер ' || pg_temp.w_uk(pg_temp.t('1 hour'))], 'R7а texts; 1.3 organizer keeps R7';
end $$;
select pg_temp.done('pa');

-- ── 4. Клієнт бачить питання — і учасниця, і організатор; час афіші поруч.
select pg_temp.as_user('c');
do $$ declare r public.event_result; begin
 select * into r from public.event_details(pg_temp.u('cb'));
 assert r.meet_proposed = pg_temp.t('90 minutes') and r.meet_decide_by is not null
   and r.companion_of_starts_at = pg_temp.t('2 hours'), 'pending decision visible';
end $$;
select pg_temp.as_user('x');

-- ── 5. Другий перенос (+1 год) накопичує: пропозиція 21:30. Новий пуш — новий текст.
select pg_temp.moved_to('pa', pg_temp.t('3 hours'));
do $$ begin
 assert (pg_temp.decision(pg_temp.u('cb'))).proposed_at = pg_temp.t('150 minutes'), 'accumulated';
 assert pg_temp.meet(pg_temp.u('cb')) = pg_temp.t('-30 minutes'), 'still waits';
end $$;
select pg_temp.done('pa');

-- ── 6. R7б: межі move_companion і guard_companion.
select pg_temp.as_user('c');
do $$ begin
 perform public.move_companion(pg_temp.u('cb'), pg_temp.t('150 minutes')); raise exception 'member moved';
exception when others then assert sqlerrm = 'NOT_ORGANIZER', sqlerrm; end $$;
select pg_temp.as_user('b');
do $$ declare bad timestamptz; begin
 foreach bad in array array[pg_temp.t('3 hours 15 minutes'), pg_temp.t('-15 minutes'), pg_temp.t('140 minutes')] loop
  begin perform public.move_companion(pg_temp.u('cb'), bad); raise exception 'moved to %', bad;
  exception when others then assert sqlerrm = 'INVALID_MEET_TIME', sqlerrm; end;
 end loop;
 begin update public.events set starts_at = pg_temp.t('2 hours') where id = pg_temp.u('cb'); raise exception 'direct edit';
 exception when others then assert sqlerrm = 'COMPANION_LOCKED', sqlerrm; end;
end $$;
delete from pg_temp.sent;
select public.move_companion(pg_temp.u('cb'), pg_temp.t('165 minutes'));
select pg_temp.as_user('x');
do $$ declare p jsonb := (select payload from pg_temp.sent); begin
 assert pg_temp.meet(pg_temp.u('cb')) = pg_temp.t('165 minutes') and pg_temp.decision(pg_temp.u('cb')) is null, 'moved, answered';
 assert (select count(*) from pg_temp.sent) = 1 and p->>'type' = 'change' and p->>'kind' = 'moved'
   and p->>'event_id' = current_setting('test.cb') and p->'user_ids' = jsonb_build_array(pg_temp.u('c'))
   and p->>'body' = 'Збір перенесли на ' || pg_temp.w_uk(pg_temp.t('165 minutes')), 'members only, own text';
end $$;

-- ── 7. Строк минув — зсув сам; уночі, коли до зустрічі ще 12 год і більше, чекаємо ранку.
select pg_temp.moved_to('pa', pg_temp.t('4 hours'));
select pg_temp.done('pa');
delete from pg_temp.sent;
do $$ declare night timestamptz := ((now() at time zone 'Europe/Kyiv')::date + time '23:30') at time zone 'Europe/Kyiv';
 day timestamptz := ((now() at time zone 'Europe/Kyiv')::date + 1 + time '10:00') at time zone 'Europe/Kyiv'; begin
 assert (pg_temp.decision(pg_temp.u('cb'))).proposed_at = pg_temp.t('225 minutes'), 'new question after the answer';
 update private.companion_decisions set decide_by = night - interval '1 minute' where companion_id = pg_temp.u('cb');
 assert private.resolve_companion_decisions(night) = 0 and pg_temp.decision(pg_temp.u('cb')) is not null, 'night: wait';
 assert private.resolve_companion_decisions(day) = 1, 'morning: shift';
 assert pg_temp.meet(pg_temp.u('cb')) = pg_temp.t('225 minutes') and pg_temp.decision(pg_temp.u('cb')) is null, 'shifted';
 assert (select array_agg(payload->>'body' order by payload->>'body') from pg_temp.sent) = array[
   'Збір перенесли на ' || pg_temp.w_uk(pg_temp.t('225 minutes')),
   'Ми пересунули збір на 22:45. Змінити можна тут'], 'organizer: we moved it; members: moved';
end $$;

-- ── 8. Повернення на час збору знімає питання; скасування події — теж, збір закрито.
select pg_temp.moved_to('pa', pg_temp.t('5 hours'));
do $$ begin assert (pg_temp.decision(pg_temp.u('cb'))).proposed_at = pg_temp.t('285 minutes'); end $$;
select pg_temp.moved_to('pa', pg_temp.t('4 hours'));   -- продавець повернув на 4 год
do $$ begin
 assert (select starts_at from public.events where id = pg_temp.ev('pa')) = pg_temp.t('4 hours'), 'event back';
 assert pg_temp.decision(pg_temp.u('cb')) is null and pg_temp.meet(pg_temp.u('cb')) = pg_temp.t('225 minutes'), 'nothing to ask, and no shift back';
end $$;
select pg_temp.done('pa');
select pg_temp.moved_to('pa', pg_temp.t('5 hours'));
select pg_temp.moved_to('pa', pg_temp.t('5 hours'));
select pg_temp.chk('pa','cancelled','{"raw":"EventCancelled"}');
select pg_temp.chk('pa','cancelled','{"raw":"EventCancelled"}');
do $$ begin
 assert pg_temp.decision(pg_temp.u('cb')) is null, 'cancel clears the question';
 assert (select status from public.events where id = pg_temp.u('cb')) = 'cancelled', 'companion closed (R7)';
end $$;

-- ── 9. Строк минув би одразу (до нової зустрічі менше 3 год) — зсув без питання.
select private.ingest_offers(current_setting('test.run')::uuid,
 jsonb_build_array(pg_temp.w('soon','Скоро',date_trunc('minute', now()) + interval '2 hours')));
select set_config('test.cs', pg_temp.companion('soon','b',date_trunc('minute', now()) + interval '105 minutes')::text, true);
select pg_temp.moved_to('soon', date_trunc('minute', now()) + interval '150 minutes');
do $$ begin
 assert pg_temp.decision(pg_temp.u('cs')) is null and pg_temp.meet(pg_temp.u('cs')) = date_trunc('minute', now()) + interval '135 minutes',
   'too late to ask: shifted';
end $$;

select 'PASS: R7а/R7б — question only for 1.4 organizers, texts, accumulate and clear, deadline and night, move_companion limits, guard, cancel, client fields' as result;
rollback;

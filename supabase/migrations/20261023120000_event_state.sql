-- Стан події з усіх продавців і адресна перевірка (docs/event-offers.md, фаза 2: R4–R5) — У ТІНІ.
--
-- Тінь: стан рахується й журналюється в приватних таблицях. Клієнти його не бачать, import_status, видача й RPC не
-- змінюються, пушів нема. Що б ми надіслали — private.would_send; точність для воріт фази 2 — private.shadow_report.
--
-- - private.offer_checks — що сказала сторінка пропозиції (Edge Function offer-check) або що дамп переніс сеанс.
-- - private.event_state_rule — правила R4 в одній чистій функції; private.refresh_event_state пише стан і журнал.
-- - Розклад R5: pg_cron кожні 15 хв → private.kick_offer_check() → pg_net → offer-check, яка бере пакет з
--   private.offer_checks_due і віддає вердикти в private.record_offer_checks.

-- ───────────────────────────────────────────── таблиці

create table private.offer_checks (
 id bigint generated always as identity primary key,
 offer_id uuid not null references public.event_offers(id) on delete cascade,
 checked_at timestamptz not null default clock_timestamp(),   -- не now(): порядок перевірок в одній транзакції
 -- vanished — зникла зі списку; day_before / morning / three_hours — слоти подій, за якими стежать; conflict —
 -- перечитування після конфлікту; listing — не сторінка, а дамп переніс сеанс пропозиції (тригер нижче).
 why text not null check (why in ('vanished','day_before','morning','three_hours','conflict','listing')),
 expected timestamptz not null,       -- сеанс, про який питали сторінку: starts_at пропозиції
 url text,
 http integer,                        -- -1 robots.txt забороняє, 0 мережа
 final_url text,
 redirected boolean not null default false,
 -- Словник tools/ingest/shadow_checks.verdict (TS-двійник — supabase/functions/offer-check/verdict.ts).
 verdict text not null,
 detail jsonb not null default '{}'
);
create index offer_checks_offer_idx on private.offer_checks (offer_id, checked_at desc);
create index offer_checks_url_idx on private.offer_checks (url, checked_at desc);

-- Стан події за R4. Окрема таблиця, а не колонки events: у тіні клієнт не бачить його навіть через select *.
create table private.event_state (
 event_id uuid primary key references public.events(id) on delete cascade,
 state text not null default 'scheduled' check (state in ('scheduled','cancelled','postponed','unknown')),
 starts_at timestamptz not null,      -- час події за свідченнями; events.starts_at у тіні не чіпаємо
 previous_starts_at timestamptz,
 evidence jsonb,
 state_changed_at timestamptz,
 checked_at timestamptz,              -- остання прочитана сторінка продавця
 conflicts integer not null default 0 -- скільки перевірок поспіль сильне свідчення лише від agent-пропозиції
);

create table private.event_state_log (
 id bigint generated always as identity primary key,
 event_id uuid not null references public.events(id) on delete cascade,
 at timestamptz not null default now(),
 from_state text not null,
 to_state text not null,
 from_starts_at timestamptz not null,
 to_starts_at timestamptz not null,
 change text not null check (change in ('cancelled','postponed','moved','corrected','unknown','restored','conflict')),
 evidence jsonb not null,
 would_push boolean not null,
 recipients uuid[] not null default '{}'   -- хто стежив у момент зміни (лише для would_push)
);
create index event_state_log_event_idx on private.event_state_log (event_id, at);
create index event_state_log_at_idx on private.event_state_log (at desc);

-- Журнал «що б ми надіслали»: подія, людина, зміна, свідчення (фаза 3 надсилатиме саме це).
create view private.would_send as
select l.id as log_id, l.at, l.event_id, u.user_id, l.change, l.evidence
from private.event_state_log l cross join unnest(l.recipients) as u(user_id)
where l.would_push;

-- Сильне свідчення лише від agent-пропозиції двічі поспіль, а інші продавці продають далі: агент, мабуть, зв'язав
-- різні сеанси. Розбирає людина (private.detach_offer).
create table private.offer_detach_queue (
 offer_id uuid primary key references public.event_offers(id) on delete cascade,
 event_id uuid not null,
 evidence jsonb not null,
 queued_at timestamptz not null default now()
);

revoke all on private.offer_checks, private.event_state, private.event_state_log, private.would_send,
 private.offer_detach_queue from public, anon, authenticated;

-- ───────────────────────────────────────────── свідчення пропозицій

-- Що каже пропозиція: інформативні перевірки її поточного сеансу, витлумачені для R4. Тихий перенос — лише
-- з тією ж назвою, до 90 днів і зі старою датою ще попереду (як усиновлення у фазі 1): інакше продавець віддав
-- адресу іншій події, і це «зникла».
create or replace function private.offer_says(p_offer uuid)
returns table (check_id bigint, checked_at timestamptz, says text, verdict text, new_start timestamptz, kind text,
 url text)
language sql stable set search_path='' as $$
 select c.id, c.checked_at, s.says, c.verdict, n.new_start,
  -- Перенаправлення — свідчення лише там, де воно й дає відповідь: сторінка зникла чи сеанс переїхав на іншу адресу.
  case when c.why = 'listing' then 'listing' when c.verdict = 'gone' then 'http_404'
       when c.verdict = 'redirect_away' or (c.verdict = 'moved_silent' and c.redirected) then 'redirect' else 'jsonld' end,
  coalesce(c.final_url, c.url)
 from public.event_offers o
 join private.offer_checks c on c.offer_id = o.id
 cross join lateral (select (c.detail->>'new_start')::timestamptz as new_start) n
 cross join lateral (select case
  when c.verdict = 'cancelled' then 'cancelled'
  when c.verdict = 'postponed' or (c.verdict = 'rescheduled_away' and n.new_start is null) then 'postponed'
  when c.verdict = 'rescheduled_away' then case when n.new_start > c.checked_at then 'moved' else 'gone' end
  when c.verdict = 'moved_silent' then
   case when n.new_start > c.checked_at and c.expected > c.checked_at
         and abs(extract(epoch from n.new_start - c.expected)) <= 90 * 86400
         and (coalesce(c.detail->>'name', '') = ''
              or left(private.title_key(c.detail->>'name'), 20) = left(private.title_key(o.title), 20))
        then 'moved' else 'gone' end
  when c.verdict = 'scheduled' then 'alive'
  when c.verdict in ('gone','redirect_away','date_missing') then 'gone'
  end as says) s
 where o.id = p_offer and s.says is not null
  -- Лише про поточний сеанс: перевірка старого часу після переносу вже нічого не каже.
  and (c.expected = o.starts_at or n.new_start = o.starts_at);
$$;

-- Свідчення всіх пропозицій події, по одному на пропозицію (вхід private.event_state_rule). says:
-- cancelled / postponed / moved (сильні), alive (сторінка каже, що сеанс у силі), listed (дамп бачить у списку, сторінку
-- не читали), gone, none (знята, сторінку ще не прочитали). Ручне зняття — рішення людини, не свідчення.
create or replace function private.offer_evidence(p_event uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o record; l record; st record; v_says text; v_on timestamptz; v jsonb := '[]';
begin
 for o in select x.id, x.linked, x.status, x.seen_at, s.slug from public.event_offers x
  join public.event_sources s on s.id = x.source_id
  where x.event_id = p_event and not (x.status = 'withdrawn' and x.ingest_run_id is null)
  order by x.created_at, x.id
 loop
  select x.* into l from private.offer_says(o.id) x order by x.checked_at desc, x.check_id desc limit 1;
  if not found then
   v := v || jsonb_build_object('offer_id', o.id, 'slug', o.slug, 'linked', o.linked,
    'says', case when o.status = 'live' then 'listed' else 'none' end);
   continue;
  end if;
  v_says := l.says;
  if l.says = 'gone' then
   -- «Скасовано» липке: сторінку часто прибирають після скасування, а 404 не каже, що подія відбудеться.
   select max(x.checked_at) into v_on from private.offer_says(o.id) x where x.says in ('alive','moved');
   select x.* into st from private.offer_says(o.id) x
   where x.says in ('cancelled','postponed') and x.checked_at > coalesce(v_on, '-infinity')
   order by x.checked_at desc, x.check_id desc limit 1;
   if found then l := st; v_says := st.says;
   elsif o.status = 'live' and o.seen_at > l.checked_at then v_says := 'listed';    -- дамп знову бачить у списку
   end if;
  end if;
  v := v || jsonb_build_object('offer_id', o.id, 'slug', o.slug, 'linked', o.linked, 'says', v_says,
   'at', l.checked_at, 'new_start', l.new_start, 'kind', l.kind, 'verdict', l.verdict, 'url', l.url);
 end loop;
 return v;
end $$;

-- ───────────────────────────────────────────── правила R4

-- Таблиця R4 з docs/event-offers.md, рядок за рядком (тест на кожен — supabase/tests/event_state.sql). Чиста функція:
-- поточний стан і свідчення пропозицій → новий стан, зміна, свідчення, чи був би пуш. change null — без змін.
-- Тлумачення, погоджені 20.10: «скасовано» липке (offer_evidence); виправлення — лише коли сторінка сама знову каже
-- «в силі»; конфлікт агента — і для переносу; перенос важить більше за скасування (старий сеанс часто позначають
-- скасованим, коли продають новий).
create or replace function private.event_state_rule(p_state text, p_starts timestamptz, p_offers jsonb,
 out state text, out starts_at timestamptz, out change text, out evidence jsonb, out push boolean)
language plpgsql stable set search_path='' as $$
declare v_strong jsonb; v_moves jsonb; v_times integer;
begin
 state := p_state; starts_at := p_starts; push := false;
 -- Перенос на час, який стан уже має, — не зміна.
 select coalesce(jsonb_agg(x order by (x->>'at')::timestamptz desc), '[]') into v_strong
 from jsonb_array_elements(p_offers) x
 where x->>'says' in ('cancelled','postponed')
    or (x->>'says' = 'moved' and abs(extract(epoch from (x->>'new_start')::timestamptz - p_starts)) >= 60);

 if jsonb_array_length(v_strong) > 0 then
  -- Сильне — лише від пропозицій, приєднаних агентом, а інші продавці продають далі: стан не міняємо.
  if not exists (select 1 from jsonb_array_elements(v_strong) x where x->>'linked' <> 'agent')
     and exists (select 1 from jsonb_array_elements(p_offers) x where x->>'says' in ('alive','listed')) then
   change := 'conflict'; evidence := v_strong; return;
  end if;
  select jsonb_agg(x), count(distinct date_trunc('minute', (x->>'new_start')::timestamptz)) into v_moves, v_times
  from jsonb_array_elements(v_strong) x where x->>'says' = 'moved';
  if v_times > 1 then return; end if;          -- продавці переносять на різний час: без змін, у звіт
  if v_times = 1 then
   state := 'scheduled'; starts_at := (v_moves->0->>'new_start')::timestamptz; change := 'moved';
   evidence := v_moves->0; push := true; return;
  end if;
  evidence := v_strong->0;                      -- найсвіжіше з «скасовано» й «відкладено»
  if evidence->>'says' <> p_state then state := evidence->>'says'; change := state; push := true; end if;
  return;
 end if;

 -- Сильних свідчень нема.
 if p_state in ('cancelled','postponed') then
  -- Сторінка, що казала «скасовано», знову каже «в силі» (липкість знімає лише вона): виправлення.
  select x into evidence from jsonb_array_elements(p_offers) x where x->>'says' = 'alive'
  order by (x->>'at')::timestamptz desc limit 1;
  if evidence is not null then state := 'scheduled'; change := 'corrected'; push := true; end if;
  return;
 end if;
 if p_state <> 'unknown' and jsonb_array_length(p_offers) > 0
    and not exists (select 1 from jsonb_array_elements(p_offers) x where x->>'says' <> 'gone') then
  state := 'unknown'; change := 'unknown'; evidence := p_offers;    -- пуша нема: відкрите питання 1
  return;
 end if;
 if p_state = 'unknown' then
  select x into evidence from jsonb_array_elements(p_offers) x where x->>'says' in ('alive','listed') limit 1;
  if evidence is not null then state := 'scheduled'; change := 'restored'; end if;
 end if;
end $$;

-- Хто стежить за подією (R5): зберегли, організатор і підтверджені учасники опублікованих супутників.
create or replace function private.event_watchers(p_event uuid) returns uuid[]
language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(distinct u order by u), '{}') from (
  select s.user_id from public.saved_events s where s.event_id = p_event
  union all
  select c.organizer_id from public.events c where c.companion_of = p_event and c.status = 'published'
  union all
  select m.user_id from public.event_members m join public.events c on c.id = m.event_id
  where c.companion_of = p_event and c.status = 'published' and m.status = 'approved') x(u);
$$;

-- Перерахунок стану події з усіх свідчень і запис у журнал. Ідемпотентний: те саме свідчення вдруге змін не дає.
create or replace function private.refresh_event_state(p_event uuid) returns text
language plpgsql security definer set search_path='' as $$
declare v_event public.events; v_state private.event_state; r record; v_conflicts integer;
begin
 select * into v_event from public.events where id = p_event;
 if not found or v_event.origin <> 'import' or v_event.merged_into is not null then return null; end if;
 insert into private.event_state (event_id, starts_at) values (p_event, v_event.starts_at) on conflict do nothing;
 select * into v_state from private.event_state where event_id = p_event for update;
 select * into r from private.event_state_rule(v_state.state, v_state.starts_at, private.offer_evidence(p_event));

 update private.event_state s set conflicts = case when r.change = 'conflict' then s.conflicts + 1 else 0 end,
  checked_at = (select max(c.checked_at) from private.offer_checks c join public.event_offers o on o.id = c.offer_id
                where o.event_id = p_event and c.why <> 'listing' and c.verdict <> 'error')
 where s.event_id = p_event returning s.conflicts into v_conflicts;
 if r.change = 'conflict' and v_conflicts >= 2 then
  insert into private.offer_detach_queue (offer_id, event_id, evidence)
  select (x->>'offer_id')::uuid, p_event, x from jsonb_array_elements(r.evidence) x on conflict do nothing;
 end if;
 if r.change is null then return null; end if;

 insert into private.event_state_log (event_id, from_state, to_state, from_starts_at, to_starts_at, change, evidence,
  would_push, recipients)
 values (p_event, v_state.state, r.state, v_state.starts_at, r.starts_at, r.change, r.evidence, r.push,
  case when r.push then private.event_watchers(p_event) else '{}' end);
 if r.change <> 'conflict' then
  update private.event_state set state = r.state, starts_at = r.starts_at, evidence = r.evidence,
   previous_starts_at = case when r.change = 'moved' then v_state.starts_at else previous_starts_at end,
   state_changed_at = now()
  where event_id = p_event;
 end if;
 return r.change;
end $$;

-- Дамп переніс сеанс пропозиції (фаза 1 переймає тихий перенос і явний перенос Karabas): та сама сторінка, інший
-- час. Для R4 це сильне свідчення переносу з kind = listing.
create or replace function private.on_offer_moved() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into private.offer_checks (offer_id, why, expected, url, verdict, detail)
 values (new.id, 'listing', old.starts_at, new.canonical_url, 'moved_silent',
  jsonb_build_object('new_start', new.starts_at, 'name', new.title));
 perform private.refresh_event_state(new.event_id);
 return null;
exception when others then
 raise warning 'event_state: перенос пропозиції % не записано: %', new.id, sqlerrm;    -- тінь не ламає дамп
 return null;
end $$;

create trigger event_offers_moved after update of starts_at on public.event_offers
for each row when (old.starts_at is distinct from new.starts_at and new.status = 'live' and new.ingest_run_id is not null)
execute function private.on_offer_moved();

-- ───────────────────────────────────────────── адресна перевірка (R5)

-- Що перевірити зараз (Edge Function offer-check бере пакет). Пріоритет — події, за якими стежать:
-- - зникла зі списку: знята дампом, сторінку після зняття ще не прочитали — на всій афіші, бо точність «б надіслали»
--   міряємо на ній (людей поки мало);
-- - за подією стежать: найсвіжіший слот, що настав, — за добу, о 09:00 у поясі події в день події, за 3 години;
-- - конфлікт agent-пропозиції: усі пропозиції події ще раз.
-- Не частіше разу на годину на сторінку. Збій чи бан (verdict error) перевірку не зараховує: до трьох спроб.
create or replace function private.offer_checks_due(p_limit integer default 60, p_now timestamptz default now())
returns table (offer_id uuid, url text, expected timestamptz, why text, tz_policy text, time_zone text,
 crawl_delay integer)
language sql stable security definer set search_path='' as $$
 with o as (
  select x.id, x.canonical_url, x.starts_at, x.status, x.updated_at, x.event_id, s.tz_policy, s.crawl_delay_seconds,
   coalesce(st.starts_at, e.starts_at) as e_starts, coalesce(e.time_zone, s.default_time_zone) as tz,
   coalesce(st.conflicts, 0) as conflicts
  from public.event_offers x
  join public.events e on e.id = x.event_id and e.merged_into is null and e.origin = 'import'
  join public.event_sources s on s.id = x.source_id and s.enabled
  left join private.event_state st on st.event_id = x.event_id
  where x.canonical_url is not null and not (x.status = 'withdrawn' and x.ingest_run_id is null)
   and coalesce(st.starts_at, e.starts_at) > p_now
   and not exists (select 1 from private.offer_checks c where c.url = x.canonical_url and c.why <> 'listing'
                   and c.checked_at > p_now - interval '1 hour')),
 watched as (
  select v.event_id from public.saved_events v
  union select c.companion_of from public.events c where c.companion_of is not null and c.status = 'published'),
 due as (
  select o.*, 'vanished' as why, o.updated_at as since, 1 as prio from o where o.status = 'withdrawn' and o.starts_at > p_now
  union all
  select o.*, t.why, t.at, 0 from o join watched w on w.event_id = o.event_id
  cross join lateral (select v.why, v.at from (values
    ('day_before', o.e_starts - interval '24 hours'),
    ('morning', ((o.e_starts at time zone o.tz)::date + time '09:00') at time zone o.tz),
    ('three_hours', o.e_starts - interval '3 hours')) v(why, at)
   where v.at <= p_now order by v.at desc limit 1) t
  union all
  select o.*, 'conflict', p_now - interval '1 hour', 0 from o where o.conflicts = 1),
 pending as (
  select distinct on (d.id) d.* from due d
  where not exists (select 1 from private.offer_checks c where c.offer_id = d.id and c.why <> 'listing'
                    and c.checked_at >= d.since and c.verdict <> 'error')
   and (select count(*) from private.offer_checks c where c.offer_id = d.id and c.checked_at >= d.since
        and c.verdict = 'error') < 3
  order by d.id, d.prio)
 select d.id, d.canonical_url, d.starts_at, d.why, d.tz_policy, d.tz, d.crawl_delay_seconds
 from pending d order by d.prio, d.e_starts, d.id limit greatest(p_limit, 0);
$$;

-- Вердикти від offer-check: запис і перерахунок стану кожної зачепленої події. Повертає, скільки подій змінились.
create or replace function private.record_offer_checks(p_rows jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare v_event uuid; n integer := 0;
begin
 insert into private.offer_checks (offer_id, why, expected, url, http, final_url, redirected, verdict, detail)
 select x.offer_id, x.why, x.expected, x.url, x.http, x.final_url, coalesce(x.redirected, false), x.verdict,
  coalesce(x.detail, '{}')
 from jsonb_to_recordset(p_rows) as x(offer_id uuid, why text, expected timestamptz, url text, http integer,
  final_url text, redirected boolean, verdict text, detail jsonb)
 where exists (select 1 from public.event_offers o where o.id = x.offer_id);
 for v_event in select distinct o.event_id from jsonb_to_recordset(p_rows) as x(offer_id uuid)
  join public.event_offers o on o.id = x.offer_id
 loop
  if private.refresh_event_state(v_event) is not null then n := n + 1; end if;
 end loop;
 return n;
end $$;

-- Годинник R5: якщо є що перевіряти, будить offer-check. Адреса й секрет — ті самі, що в push (Vault):
-- поки їх нема (як і пушів), перевірка мовчить.
create or replace function private.kick_offer_check() returns boolean
language plpgsql security definer set search_path='' as $$
declare v_url text; v_secret text;
begin
 if not exists (select 1 from private.offer_checks_due(1)) then return false; end if;
 select regexp_replace(e.url, '/push$', '/offer-check'), e.secret into v_url, v_secret from private.push_endpoint() e;
 if v_url is null or v_secret is null then return false; end if;
 perform net.http_post(url := v_url, body := '{}'::jsonb,
  headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
  timeout_milliseconds := 150000);
 return true;
end $$;

-- ───────────────────────────────────────────── звіт тіні

-- Ворота фази 2: точність «б надіслали» ≥ 99% за тиждень. Точність — частка змін з would_push, яких за 72 год не
-- відкликали (виправлення або перенос назад). Решта — для ручного аудиту й здоров'я перевірки.
create or replace function private.shadow_report(p_days integer default 7)
returns table (section text, label text, n bigint, note text)
language sql stable security definer set search_path='' as $$
 with w as (
  select l.*, l.at < now() - interval '72 hours' as ripe,
   exists (select 1 from private.event_state_log m where m.event_id = l.event_id and m.id > l.id
           and m.at <= l.at + interval '72 hours'
           and (m.change = 'corrected' or (m.change = 'moved' and m.to_starts_at = l.from_starts_at))) as undone
  from private.event_state_log l where l.would_push and l.at > now() - make_interval(days => p_days)),
 c as (select c.*, split_part(split_part(coalesce(c.url, ''), '://', 2), '/', 1) as host
       from private.offer_checks c where c.why <> 'listing' and c.checked_at > now() - make_interval(days => p_days))
 select 'точність', 'дозрілих (старших 72 год) б надіслали / відкликано', count(*) filter (where ripe),
  coalesce(round(100.0 * count(*) filter (where ripe and not undone) / nullif(count(*) filter (where ripe), 0), 1)::text || '%', '—')
  || ', відкликано ' || count(*) filter (where ripe and undone)
 from w
 union all
 select 'б надіслали', w.change || ' · ' || coalesce(w.evidence->>'kind', '?') || ' · ' || coalesce(w.evidence->>'slug', '?'),
  count(*), 'людей: ' || coalesce(sum(cardinality(w.recipients)), 0)
 from w group by 2
 union all
 select 'зміни стану', l.change, count(*), null
 from private.event_state_log l where l.at > now() - make_interval(days => p_days) group by 2
 union all
 select 'перевірки', c.host || ' · ' || c.verdict, count(*), null from c group by 2
 union all
 -- Збій і бан продавця стан не міняють — окремий лічильник.
 select 'збої', c.host || ' · http ' || coalesce(c.http::text, '?'), count(*), max(c.checked_at)::text
 from c where c.verdict = 'error' group by 2
 union all
 select 'стежать', 'майбутніх подій / з них unknown', count(*),
  count(*) filter (where s.state = 'unknown') || ' unknown'
 from (select distinct x.event_id from (select v.event_id from public.saved_events v
       union select c.companion_of from public.events c where c.companion_of is not null and c.status = 'published') x) f
 join public.events e on e.id = f.event_id and e.starts_at > now()
 left join private.event_state s on s.event_id = f.event_id
 union all
 -- Пропозиції з різними датами без сильного свідчення: стан не міняємо, але показуємо.
 select 'розбіжність дат', e.title, count(*), string_agg(distinct o.starts_at::text, ' / ')
 from public.events e join public.event_offers o on o.event_id = e.id and o.status = 'live'
 where e.origin = 'import' and e.merged_into is null and e.starts_at > now()
 group by e.id, e.title having max(o.starts_at) - min(o.starts_at) >= interval '1 minute'
 union all
 select 'черга від''єднання', q.event_id::text, 1, q.evidence->>'url' from private.offer_detach_queue q
 union all
 -- Вибірка для ручного аудиту: відкрити посилання й звірити.
 select * from (select 'аудит', w.change || ' ' || e.title || ' ' || to_char(w.from_starts_at, 'DD.MM HH24:MI')
  || case when w.change = 'moved' then ' → ' || to_char(w.to_starts_at, 'DD.MM HH24:MI') else '' end, 1::bigint, w.evidence->>'url'
  from w join public.events e on e.id = w.event_id order by w.at desc limit 30) a;
$$;

revoke all on function private.offer_says(uuid), private.offer_evidence(uuid),
 private.event_state_rule(text, timestamptz, jsonb), private.event_watchers(uuid), private.refresh_event_state(uuid),
 private.on_offer_moved(), private.offer_checks_due(integer, timestamptz), private.record_offer_checks(jsonb),
 private.kick_offer_check(), private.shadow_report(integer) from public, anon, authenticated;

-- Кожні 15 хвилин, де є pg_cron (prod; dev — увімкнено 2026-10-20). Без pg_cron — ручний select private.kick_offer_check().
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('offer-check', '*/15 * * * *', 'select private.kick_offer_check()')$cron$;
 end if;
end $$;

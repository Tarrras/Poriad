-- Пуші про зміну афіші й супутник за подією (docs/event-offers.md, фаза 3: R6–R7) — ЗА ПЕРЕМИКАЧЕМ.
--
-- Перемикач `private.flags.event_changes` вимкнено: усе як у фазі 2 — стан і журнал «б надіслали», клієнт нічого не
-- бачить. Увімкнення — одна команда `select private.set_event_changes(true);`. Тоді зміна стану події (R4):
-- - R7: супутники зсуваються разом з подією, при скасуванні чи відкладенні закриваються, після виправлення
--   відновлюються (службово: guard_companion і events_push це пропускають);
-- - час імпортованої події й import_status ідуть за станом (R3);
-- - R6: пуш кожному, хто стежить, — один на людину на зміну, журнал і черга private.event_change_pushes.
--
-- В обох режимах (тінь міряє те, що слатимемо): після виправлення наступна пушева зміна застосовується лише з другим
-- сильним свідченням поспіль.

-- ───────────────────────────────────────────── перемикач

create table private.flags (
 name text primary key,
 enabled boolean not null default false,
 changed_at timestamptz not null default now()
);
insert into private.flags (name) values ('event_changes');
revoke all on private.flags from public, anon, authenticated;

create function private.flag(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select f.enabled from private.flags f where f.name = p_name), false);
$$;

-- ───────────────────────────────────────────── таблиці

-- R6: журнал і черга. Рядок — пуш однієї людині про одну зміну (state_version — рядок event_state_log). target_id —
-- що відкриває тап: сама подія або супутник людини (R7). skipped: superseded — новіша зміна прийшла до відправлення,
-- corrected — помилкове виправили до відправлення.
create table private.event_change_pushes (
 id bigint generated always as identity primary key,
 event_id uuid not null references public.events(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 change text not null check (change in ('cancelled','postponed','moved','corrected')),
 state_version bigint not null references private.event_state_log(id) on delete cascade,
 target_id uuid not null,
 title text not null,
 body text not null,
 send_after timestamptz not null,
 sent_at timestamptz,
 skipped text check (skipped in ('superseded','corrected')),
 created_at timestamptz not null default now(),
 unique (event_id, user_id, change, state_version)
);
create index event_change_pushes_due_idx on private.event_change_pushes (send_after) where sent_at is null and skipped is null;
create index event_change_pushes_event_idx on private.event_change_pushes (event_id, user_id);

-- R7: супутники, які закрили ми (скасування чи відкладення події), — щоб виправлення їх повернуло.
create table private.companion_closures (
 companion_id uuid primary key references public.events(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 closed_at timestamptz not null default now()
);

-- Перша пушева зміна після виправлення: чекає другого сильного свідчення поспіль.
alter table private.event_state add column unconfirmed jsonb;

revoke all on private.event_change_pushes, private.companion_closures from public, anon, authenticated;

-- ───────────────────────────────────────────── вікно й тексти

-- Тихі години в поясі події. Наявна однопараметрова версія (Київ) лишається для «Стежити».
create function private.quiet_hours(p_at timestamptz, p_zone text) returns boolean
language sql stable set search_path='' as $$
 select extract(hour from p_at at time zone coalesce(p_zone, 'Europe/Kyiv')) not between 9 and 21;
$$;
create or replace function private.quiet_hours(p_at timestamptz default now()) returns boolean
language sql stable set search_path='' as $$
 select private.quiet_hours(p_at, 'Europe/Kyiv');
$$;

-- Коли слати (R6): до початку менше 12 год — одразу; інакше в межах 09:00–21:59 у поясі події, вночі — о 09:00.
create function private.change_send_after(p_start timestamptz, p_zone text, p_now timestamptz default now())
returns timestamptz language sql stable set search_path='' as $$
 select case when p_start - p_now < interval '12 hours' or not private.quiet_hours(p_now, z) then p_now
  else ((p_now at time zone z)::date + (extract(hour from p_now at time zone z) >= 22)::int + time '09:00') at time zone z end
 from (select coalesce(p_zone, 'Europe/Kyiv') as z) x;
$$;

-- «пт, 7 листопада о 19:00» — як `when` у функції push (Intl uk-UA), без залежності від локалі бази.
create function private.when_uk(p_at timestamptz, p_zone text) returns text
language sql stable set search_path='' as $$
 select (array['нд','пн','вт','ср','чт','пт','сб'])[extract(dow from l)::int + 1] || ', ' || extract(day from l)::int || ' '
  || (array['січня','лютого','березня','квітня','травня','червня','липня','серпня','вересня','жовтня','листопада',
            'грудня'])[extract(month from l)::int] || ' о ' || to_char(l, 'HH24:MI')
 from (select p_at at time zone coalesce(p_zone, 'Europe/Kyiv') as l) x;
$$;

-- Таблиця текстів R6 (хто зберіг) і R7 (організатор і учасники супутника). p_seller — єдиний продавець події, null —
-- їх кілька. Тест на кожен рядок — supabase/tests/event_changes.sql.
create function private.event_change_body(p_change text, p_when text, p_seller text default null,
 p_companion boolean default false, p_meet text default null) returns text
language sql immutable set search_path='' as $$
 select case when p_companion then case p_change
   when 'cancelled' then 'Подію скасували, тож збір скасовано'
   when 'postponed' then 'Подію відклали, тож збір скасовано'
   when 'moved' then 'Подію перенесли — збір тепер ' || p_meet
   when 'corrected' then 'Подія все ж відбудеться — збір ' || p_meet end
  else case p_change
   when 'cancelled' then 'Скасовано. Якщо купили квиток — повернення ' || coalesce('в ' || p_seller, 'у продавця, де купували')
   when 'postponed' then 'Відкладено, нової дати ще нема'
   when 'moved' then 'Перенесено на ' || p_when
   when 'corrected' then 'Подія все ж відбудеться: ' || p_when end end;
$$;

-- ───────────────────────────────────────────── службові зміни супутника (R7)

-- Свідомо скасовує правило з docs/companions.md: час і статус супутника міняє подія. Локальний прапорець
-- poruch.follow_parent: guard_companion пропускає, events_push мовчить — пуш іде з черги R6 з текстом R7.
create or replace function private.guard_companion() returns trigger language plpgsql set search_path='' as $$
begin
 if auth.uid() is null or current_setting('poruch.follow_parent', true) = 'on' then return new; end if;
 if old.companion_of is null and new.companion_of is not null then raise exception 'COMPANION_LOCKED' using errcode='P0001'; end if;
 if old.companion_of is not null and (new.title,new.description,new.category,new.city,new.address,new.latitude,new.longitude,
   new.starts_at,new.ends_at,new.time_zone,new.capacity,new.min_age,new.max_age,new.approval_required,new.companion_of,new.meet_note)
   is distinct from (old.title,old.description,old.category,old.city,old.address,old.latitude,old.longitude,
   old.starts_at,old.ends_at,old.time_zone,old.capacity,old.min_age,old.max_age,old.approval_required,old.companion_of,old.meet_note) then
  raise exception 'COMPANION_LOCKED' using errcode='P0001';
 end if;
 return new;
end $$;

create or replace function private.on_event_changed() returns trigger language plpgsql security definer set search_path='' as $$
declare v_kind text;
begin
 if current_setting('poruch.follow_parent', true) = 'on' then return new; end if;     -- R7: пуш шле черга R6
 -- Про те, що вже скінчилось, не сповіщаємо: модерація й видалення акаунта скасовують і минулі події.
 if old.status = 'published' and new.status = 'cancelled' and new.ends_at > now() then
  v_kind := 'cancelled';
 elsif old.starts_at <> new.starts_at and new.status = 'published' and old.starts_at > now() then
  v_kind := 'moved';
 end if;
 if v_kind is not null then
  perform private.notify_push(jsonb_build_object('type','event','kind',v_kind,'event_id',new.id));
 end if;
 return new;
end $$;

-- ───────────────────────────────────────────── R3: import_status за станом

-- Тіло — з 20261021120000_event_offers; додано стан події, коли перемикач увімкнено: скасована, відкладена чи
-- невідома — знята, навіть якщо продавець ще продає; зникла зі списку, але сторінка каже «в силі», — жива.
create or replace function private.sync_event(p_event uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_event public.events; v_primary public.event_offers; v_live integer; v_price numeric; v_free boolean; v_status text;
 v_state text;
begin
 select * into v_event from public.events where id = p_event;
 if not found or v_event.merged_into is not null then return; end if;
 select o.* into v_primary from public.event_offers o join public.event_sources s on s.id = o.source_id
 where o.event_id = p_event
 order by o.status = 'live' desc, (o.source_id = v_event.source_id and o.source_uid = v_event.source_uid) desc,
          s.weight desc, o.created_at, o.id
 limit 1;
 if not found then return; end if;           -- подія без пропозицій (спільнотна чи тестова) — не наша справа
 select count(*), min(o.price_min), bool_or(o.is_free) into v_live, v_price, v_free
 from public.event_offers o where o.event_id = p_event and o.status = 'live';
 v_status := case when v_live = 0 then 'withdrawn'
                  when v_event.import_status = 'stale' and v_event.ends_at < now() then 'stale' else 'live' end;
 if private.flag('event_changes') then
  select s.state into v_state from private.event_state s where s.event_id = p_event;
  if v_state in ('cancelled','postponed','unknown') then
   v_status := 'withdrawn';
  elsif v_live = 0 and exists (select 1 from jsonb_array_elements(private.offer_evidence(p_event)) x where x->>'says' = 'alive') then
   v_status := case when v_event.import_status = 'stale' and v_event.ends_at < now() then 'stale' else 'live' end;
  end if;
 end if;
 if v_live = 0 then v_price := v_event.price_min; v_free := v_event.is_free; end if;
 update public.events e set source_id = v_primary.source_id, source_uid = v_primary.source_uid,
  canonical_url = v_primary.canonical_url, price_min = v_price, is_free = v_free, import_status = v_status,
  ingest_run_id = v_primary.ingest_run_id, updated_at = now()
 where e.id = p_event and (e.source_id, e.source_uid, e.canonical_url, e.price_min, e.is_free, e.import_status, e.ingest_run_id)
  is distinct from (v_primary.source_id, v_primary.source_uid, v_primary.canonical_url, v_price, v_free, v_status,
                    v_primary.ingest_run_id);
end $$;

-- ───────────────────────────────────────────── R6–R7: наслідки зміни стану

-- Розсилка черги: що настало й ще не пішло. Групує однаковий текст на одну ціль в один виклик функції push.
create function private.flush_event_change_pushes() returns integer
language plpgsql security definer set search_path='' as $$
declare g record; n integer := 0;
begin
 if not private.flag('event_changes') then return 0; end if;
 for g in
  with due as (select p.* from private.event_change_pushes p
               where p.sent_at is null and p.skipped is null and p.send_after <= now() for update skip locked)
  select d.target_id, d.change, d.title, d.body, array_agg(d.id) as ids, jsonb_agg(d.user_id) as users
  from due d group by 1, 2, 3, 4
 loop
  -- На дроті наявні kind (випущені клієнти інших не знають), точна зміна — окремим полем.
  perform private.notify_push(jsonb_build_object('type', 'change',
   'kind', case when g.change in ('cancelled','postponed') then 'cancelled' else 'moved' end, 'change', g.change,
   'event_id', g.target_id, 'title', g.title, 'body', g.body, 'user_ids', g.users));
  update private.event_change_pushes set sent_at = now() where id = any(g.ids);
  n := n + cardinality(g.ids);
 end loop;
 return n;
end $$;

-- Зміна стану з журналу, перемикач увімкнено: час події й супутників, а з p_push — черга пушів.
create function private.apply_event_change(p_log bigint, p_push boolean) returns integer
language plpgsql security definer set search_path='' as $$
declare l private.event_state_log; e public.events; v_delta interval; v_seller text; v_send timestamptz;
 v_since bigint; v_zone text; n integer := 0;
begin
 select * into l from private.event_state_log where id = p_log;
 select * into e from public.events where id = l.event_id;
 if l.id is null or e.id is null or l.change not in ('cancelled','postponed','moved','corrected') then return 0; end if;
 v_delta := l.to_starts_at - l.from_starts_at;
 v_zone := coalesce(e.time_zone, 'Europe/Kyiv');
 perform set_config('poruch.follow_parent', 'on', true);

 -- Час події за станом: клієнт показує те, що й пуш. Супутники — на ту саму різницю, якщо зустріч ще попереду.
 if v_delta <> interval '0' then
  update public.events set starts_at = l.to_starts_at, ends_at = ends_at + (l.to_starts_at - starts_at), updated_at = now()
  where id = l.event_id and starts_at <> l.to_starts_at;
  update public.events c set starts_at = c.starts_at + v_delta, ends_at = c.ends_at + v_delta, updated_at = now()
  where c.companion_of = l.event_id and c.status = 'published' and c.starts_at > now();
 end if;
 -- Виправлення скасування: закриті нами супутники знову відкриті, якщо зустріч попереду й організатор не зібрав новий.
 if l.change = 'corrected' and l.from_state in ('cancelled','postponed') then
  update public.events c set status = 'published', updated_at = now()
  from private.companion_closures z
  where z.event_id = l.event_id and c.id = z.companion_id and c.status = 'cancelled' and c.starts_at > now()
   and not exists (select 1 from public.events o where o.companion_of = c.companion_of and o.organizer_id = c.organizer_id
                   and o.status = 'published');
  delete from private.companion_closures where event_id = l.event_id;
 end if;

 if p_push then
  -- Невідправлене про цю подію застаріло: новіша зміна його заміняє, виправлення — скасовує.
  update private.event_change_pushes set skipped = case when l.change = 'corrected' then 'corrected' else 'superseded' end
  where event_id = l.event_id and sent_at is null and skipped is null;
  -- Пуш лише з сильним свідченням (R4); виправлення спирається на сторінку чи список на попередньому часі.
  if l.change = 'corrected' or l.evidence->>'says' in ('cancelled','postponed','moved') then
   select case when count(distinct o.source_id) = 1 then min(s.name) end into v_seller
   from public.event_offers o join public.event_sources s on s.id = o.source_id
   where o.event_id = l.event_id and not (o.status = 'withdrawn' and o.ingest_run_id is null);
   -- До початку рахуємо від раніших з двох часів: людина могла планувати на старий.
   v_send := private.change_send_after(least(l.from_starts_at, l.to_starts_at), v_zone);
   v_since := coalesce((select max(x.id) from private.event_state_log x where x.event_id = l.event_id
                        and x.change = 'corrected' and x.id < l.id), 0);
   insert into private.event_change_pushes (event_id, user_id, change, state_version, target_id, title, body, send_after)
   with roles as (
    -- Супутник людини: власний збір важить більше за чужий. Учасник, заблокований з організатором, — не тут.
    select distinct on (x.user_id) x.* from (
     select c.organizer_id as user_id, c.id as companion_id, c.title, c.starts_at as meet, 0 as prio
     from public.events c where c.companion_of = l.event_id and c.status = 'published'
     union all
     select m.user_id, c.id, c.title, c.starts_at, 1 from public.events c
     join public.event_members m on m.event_id = c.id and m.status = 'approved'
     where c.companion_of = l.event_id and c.status = 'published' and not private.blocked_between(m.user_id, c.organizer_id)) x
    order by x.user_id, x.prio),
   people as (
    -- Хто стежить; виправлення — лише тим, кому про цю подію вже пішов пуш після попереднього виправлення.
    select r.user_id from roles r where l.change <> 'corrected'
    union select s.user_id from public.saved_events s where s.event_id = l.event_id and l.change <> 'corrected'
    union select p.user_id from private.event_change_pushes p
     where l.change = 'corrected' and p.event_id = l.event_id and p.sent_at is not null and p.state_version > v_since)
   select l.event_id, u.user_id, l.change, l.id, coalesce(r.companion_id, l.event_id), coalesce(r.title, e.title),
    private.event_change_body(l.change, private.when_uk(l.to_starts_at, v_zone), v_seller, r.companion_id is not null,
     private.when_uk(r.meet, v_zone)),
    v_send
   from people u left join roles r on r.user_id = u.user_id
   on conflict do nothing;
   get diagnostics n = row_count;
  end if;
 end if;

 -- Скасування чи відкладення закриває супутники — після того, як їхніх людей записали в чергу.
 if l.change in ('cancelled','postponed') then
  with closed as (update public.events c set status = 'cancelled', updated_at = now()
                  where c.companion_of = l.event_id and c.status = 'published' and c.ends_at > now() returning c.id)
  insert into private.companion_closures (companion_id, event_id) select id, l.event_id from closed on conflict do nothing;
 end if;
 perform set_config('poruch.follow_parent', '', true);
 if n > 0 and v_send <= now() then perform private.flush_event_change_pushes(); end if;
 return n;
end $$;

-- ───────────────────────────────────────────── стан: друге свідчення після виправлення, наслідки

-- Тіло — з 20261024120000_event_state_guards; додано «два сильних поспіль після виправлення» і наслідки (перемикач).
create or replace function private.refresh_event_state(p_event uuid, p_reason text default null) returns text
language plpgsql security definer set search_path='' as $$
declare v_event public.events; v_state private.event_state; v_offers jsonb; r record; v_conflicts integer;
 v_push boolean; v_wait jsonb; v_log bigint;
begin
 select * into v_event from public.events where id = p_event;
 if not found or v_event.origin <> 'import' or v_event.merged_into is not null then return null; end if;
 insert into private.event_state (event_id, starts_at) values (p_event, v_event.starts_at) on conflict do nothing;
 select * into v_state from private.event_state where event_id = p_event for update;
 v_offers := private.offer_evidence(p_event);
 select * into r from private.event_state_rule(v_state.state, v_state.starts_at, v_offers, v_state.previous_starts_at,
  p_reason is not null);

 -- Після виправлення наступна пушева зміна — лише з другим сильним свідченням поспіль (R6). Перше чекає в
 -- unconfirmed; ту саму зміну зі свіжішим свідченням застосовуємо; інший результат скидає очікування.
 if r.push and p_reason is null and r.change in ('cancelled','postponed','moved')
    and (select l.change from private.event_state_log l where l.event_id = p_event
         and l.change in ('cancelled','postponed','moved','corrected') order by l.id desc limit 1) = 'corrected' then
  v_wait := jsonb_build_object('change', r.change, 'state', r.state, 'starts_at', r.starts_at, 'at', r.evidence->'at');
  if v_state.unconfirmed - 'at' = v_wait - 'at' then
   if (v_wait->>'at')::timestamptz > (v_state.unconfirmed->>'at')::timestamptz then v_wait := null;
   else v_wait := v_state.unconfirmed; end if;
  end if;
 end if;
 update private.event_state set unconfirmed = v_wait where event_id = p_event and unconfirmed is distinct from v_wait;
 if v_wait is not null then r.change := null; end if;

 -- Чужа сторінка (дата в адресі, зайнята ціль) — пропозицію хибно прив'язано: розбирає людина.
 insert into private.offer_detach_queue (offer_id, event_id, evidence)
 select (x->>'offer_id')::uuid, p_event, x from jsonb_array_elements(v_offers) x where x->>'detach' is not null
 on conflict do nothing;
 update private.event_state s set conflicts = case when r.change = 'conflict' then s.conflicts + 1 else 0 end,
  checked_at = (select max(c.checked_at) from private.offer_checks c join public.event_offers o on o.id = c.offer_id
                where o.event_id = p_event and c.why <> 'listing' and c.verdict <> 'error')
 where s.event_id = p_event returning s.conflicts into v_conflicts;
 if r.change = 'conflict' and v_conflicts >= 2 then
  insert into private.offer_detach_queue (offer_id, event_id, evidence)
  select (x->>'offer_id')::uuid, p_event, x from jsonb_array_elements(r.evidence) x on conflict do nothing;
 end if;

 if r.change is not null then
  v_push := r.push and p_reason is null;
  insert into private.event_state_log (event_id, from_state, to_state, from_starts_at, to_starts_at, change, evidence,
   would_push, recipients)
  values (p_event, v_state.state, r.state, v_state.starts_at, r.starts_at, r.change,
   case when p_reason is null then r.evidence else jsonb_build_object('reason', p_reason, 'evidence', r.evidence) end,
   v_push, case when v_push then private.event_watchers(p_event) else '{}' end)
  returning id into v_log;
  if r.change <> 'conflict' then
   update private.event_state set state = r.state, starts_at = r.starts_at, evidence = r.evidence,
    previous_starts_at = case when r.change = 'moved' then v_state.starts_at
                              when r.starts_at <> v_state.starts_at then null       -- перенос відкликано
                              else previous_starts_at end,
    state_changed_at = now()
   where event_id = p_event;
  end if;
 end if;

 -- Фаза 3: наслідки бачать люди (час, супутники, пуші), import_status — за станом і свіжими сторінками. Збій тут не
 -- має зупинити адресну перевірку (record_offer_checks пише пакет однією транзакцією): стан записано, наслідки — ні.
 if private.flag('event_changes') then
  begin
   if v_log is not null and r.change <> 'conflict' then perform private.apply_event_change(v_log, v_push); end if;
   perform private.sync_event(p_event);
  exception when others then
   raise warning 'event_changes: наслідки зміни події % не застосовано: %', p_event, sqlerrm;
  end;
 end if;
 return r.change;
end $$;

-- Тіло — з 20261023120000_event_state; додано перечитування подій, що чекають другого свідчення (як після конфлікту).
create or replace function private.offer_checks_due(p_limit integer default 60, p_now timestamptz default now())
returns table (offer_id uuid, url text, expected timestamptz, why text, tz_policy text, time_zone text,
 crawl_delay integer)
language sql stable security definer set search_path='' as $$
 with o as (
  select x.id, x.canonical_url, x.starts_at, x.status, x.updated_at, x.event_id, s.tz_policy, s.crawl_delay_seconds,
   coalesce(st.starts_at, e.starts_at) as e_starts, coalesce(e.time_zone, s.default_time_zone) as tz,
   coalesce(st.conflicts, 0) as conflicts, st.unconfirmed is not null as unconfirmed
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
  select o.*, 'conflict', p_now - interval '1 hour', 0 from o where o.conflicts = 1 or o.unconfirmed),
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

-- ───────────────────────────────────────────── увімкнення

-- Одна команда для prod: select private.set_event_changes(true). Ставить прапорець і перераховує import_status
-- майбутніх імпортованих подій за станом. Пушів за минулі зміни не шле: лише за ті, що стануться після.
-- Повертає, скільки подій змінили import_status.
create function private.set_event_changes(p_on boolean) returns integer
language plpgsql security definer set search_path='' as $$
declare v_event uuid; v_before text; n integer := 0;
begin
 update private.flags set enabled = p_on, changed_at = now() where name = 'event_changes';
 for v_event, v_before in select e.id, e.import_status from public.events e
  where e.origin = 'import' and e.merged_into is null and e.ends_at > now()
 loop
  perform private.sync_event(v_event);
  if (select import_status from public.events where id = v_event) is distinct from v_before then n := n + 1; end if;
 end loop;
 return n;
end $$;

revoke all on function private.flag(text), private.quiet_hours(timestamptz, text), private.when_uk(timestamptz, text),
 private.change_send_after(timestamptz, text, timestamptz),
 private.event_change_body(text, text, text, boolean, text), private.flush_event_change_pushes(),
 private.apply_event_change(bigint, boolean), private.set_event_changes(boolean),
 private.refresh_event_state(uuid, text), private.offer_checks_due(integer, timestamptz), private.sync_event(uuid)
 from public, anon, authenticated;

-- Черга вікна: щогодини, де є pg_cron (prod; dev — з 2026-10-20). Вимкнений перемикач — нічого не шле.
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('event-change-pushes', '5 * * * *', 'select private.flush_event_change_pushes()')$cron$;
 end if;
end $$;

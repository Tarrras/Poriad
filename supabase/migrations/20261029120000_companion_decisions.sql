-- R7а і R7б (docs/event-offers.md, рішення 20.10): збір «Шукаю компанію» після переносу афіші — спершу питаємо
-- організатора, і організатор сам змінює час збору. Потребує 20261027120000_event_changes (apply_event_change, тексти,
-- перемикач) і діє лише з ним: без перемикача apply_event_change не кличуть.
--
-- - Питаємо лише організатора, який може відповісти: застосунок 1.4 позначає пуш-токен `companion_decision`, а
--   питання без пуша до нього не дійде. Решті — як у фазі 3: збір одразу на ту саму різницю (1.3 нового екрана не має).
-- - Питання — рядок private.companion_decisions: пропозиція (стара зустріч + та сама різниця, повторні переноси
--   накопичуються) і строк: 12 год після пуша, але не пізніше ніж за 3 год до нової зустрічі. Строк минув — зсув сам
--   (задача pg_cron кожні 15 хв), не скасування. Перенос назад на час збору знімає питання.
-- - R7б: public.move_companion — організатор змінює лише час збору в межах create_companion (не пізніше початку,
--   не раніше ніж за 3 год, крок 15 хв від початку). guard_companion пропускає лише службову зміну; учасникам —
--   «Збір перенесли на …». Ця ж RPC відповідає на питання («Перенести на 21:30» / «Інший час»); «Скасувати збір» —
--   наявний cancel_event.

-- ───────────────────────────────────────────── хто може відповісти

alter table public.push_tokens add column features text[] not null default '{}';

-- Стара сигнатура (1.3) — та сама виклик з двома параметрами: PostgREST бере default третього.
drop function public.register_push_token(text, text);
drop function private.register_push_token(text, text);

create function private.register_push_token(p_token text, p_platform text, p_features text[] default '{}')
returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_features text[] := coalesce(p_features, '{}');
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_token is null or length(p_token) < 16 or length(p_token) > 4096 then raise exception 'INVALID_TOKEN' using errcode='22023'; end if;
 if p_platform not in ('android','ios') then raise exception 'INVALID_PLATFORM' using errcode='22023'; end if;
 if cardinality(v_features) > 16 or exists (select 1 from unnest(v_features) f where f is null or length(f) > 40) then
  raise exception 'INVALID_FEATURES' using errcode='22023'; end if;
 insert into public.push_tokens(token,user_id,platform,features) values (p_token,v_user,p_platform,v_features)
 on conflict (token) do update set user_id=excluded.user_id,platform=excluded.platform,features=excluded.features,updated_at=now();
 delete from public.push_tokens t where t.user_id=v_user and t.token not in
  (select token from public.push_tokens where user_id=v_user order by updated_at desc limit 10);
end $$;

create function public.register_push_token(p_token text, p_platform text, p_features text[] default '{}')
returns void language sql set search_path='' as $$ select private.register_push_token(p_token,p_platform,p_features); $$;

-- Організатор збору відповість: свіжий (30 днів) токен застосунку, що вміє показати питання.
create function private.can_decide(p_user uuid) returns boolean language sql stable set search_path='' as $$
 select exists (select 1 from public.push_tokens t where t.user_id = p_user and 'companion_decision' = any(t.features)
  and t.updated_at > now() - interval '30 days');
$$;

-- ───────────────────────────────────────────── питання

create table private.companion_decisions (
 companion_id uuid primary key references public.events(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 proposed_at timestamptz not null,
 decide_by timestamptz not null,
 created_at timestamptz not null default now()
);
create index companion_decisions_due_idx on private.companion_decisions (decide_by);
revoke all on private.companion_decisions from public, anon, authenticated;

-- «21:30», коли день той самий, що в [p_ref], інакше «пт, 7 листопада о 21:30».
create function private.meet_uk(p_at timestamptz, p_ref timestamptz, p_zone text) returns text
language sql stable set search_path='' as $$
 select case when (p_at at time zone z)::date = (p_ref at time zone z)::date then to_char(p_at at time zone z, 'HH24:MI')
  else private.when_uk(p_at, z) end
 from (select coalesce(p_zone, 'Europe/Kyiv') as z) x;
$$;

-- Тексти R7а. Тест на кожен — supabase/tests/companion_decisions.sql.
create function private.companion_decision_body(p_role text, p_when text, p_meet text default null,
 p_proposed text default null) returns text language sql immutable set search_path='' as $$
 select case p_role
  when 'ask' then 'Подію перенесли на ' || p_when || '. Ваш збір ' || p_meet || ' — перенести на ' || p_proposed || '?'
  when 'wait' then 'Подію перенесли на ' || p_when || '. Організатор вирішує, о котрій тепер збір'
  when 'auto' then 'Ми пересунули збір на ' || p_proposed || '. Змінити можна тут'
  when 'moved' then 'Збір перенесли на ' || p_proposed end;
$$;

-- Пуш людям збору поза чергою R6: [p_who] — `organizer` чи `members` (підтверджені, не заблоковані з організатором).
create function private.notify_companion(p_companion uuid, p_who text, p_body text) returns void
language plpgsql security definer set search_path='' as $$
declare c public.events; v_users jsonb;
begin
 select * into c from public.events where id = p_companion;
 if c.id is null then return; end if;
 if p_who = 'organizer' then v_users := jsonb_build_array(c.organizer_id);
 else select jsonb_agg(m.user_id) into v_users from public.event_members m
  where m.event_id = c.id and m.status = 'approved' and m.user_id <> c.organizer_id
   and not private.blocked_between(m.user_id, c.organizer_id);
 end if;
 if v_users is null or jsonb_array_length(v_users) = 0 then return; end if;
 perform private.notify_push(jsonb_build_object('type', 'change', 'kind', 'moved', 'change', 'moved',
  'event_id', c.id, 'title', c.title, 'body', p_body, 'user_ids', v_users));
end $$;

-- ───────────────────────────────────────────── R6–R7 з питанням (замінює версію 20261027120000)

create or replace function private.apply_event_change(p_log bigint, p_push boolean) returns integer
language plpgsql security definer set search_path='' as $$
declare l private.event_state_log; e public.events; v_delta interval; v_seller text; v_send timestamptz;
 v_since bigint; v_zone text; v_strong boolean; n integer := 0;
begin
 select * into l from private.event_state_log where id = p_log;
 select * into e from public.events where id = l.event_id;
 if l.id is null or e.id is null or l.change not in ('cancelled','postponed','moved','corrected') then return 0; end if;
 v_delta := l.to_starts_at - l.from_starts_at;
 v_zone := coalesce(e.time_zone, 'Europe/Kyiv');
 -- Пуш лише з сильним свідченням (R4); виправлення спирається на сторінку чи список на попередньому часі.
 v_strong := p_push and (l.change = 'corrected' or l.evidence->>'says' in ('cancelled','postponed','moved'));
 -- До початку рахуємо від раніших з двох часів: людина могла планувати на старий.
 v_send := private.change_send_after(least(l.from_starts_at, l.to_starts_at), v_zone);
 perform set_config('poruch.follow_parent', 'on', true);

 -- Час події за станом: клієнт показує те, що й пуш.
 if v_delta <> interval '0' then
  update public.events set starts_at = l.to_starts_at, ends_at = ends_at + (l.to_starts_at - starts_at), updated_at = now()
  where id = l.event_id and starts_at <> l.to_starts_at;
  -- R7а: відкрите питання накопичує різницю; нове — лише коли організатор відповість і пуш до нього піде, а строк ще
  -- не минув. Решта зборів — на ту саму різницю одразу, як у фазі 3.
  update private.companion_decisions d set proposed_at = d.proposed_at + v_delta,
   decide_by = least(v_send + interval '12 hours', d.proposed_at + v_delta - interval '3 hours')
  where d.event_id = l.event_id;
  insert into private.companion_decisions (companion_id, event_id, proposed_at, decide_by)
  select c.id, l.event_id, c.starts_at + v_delta, least(v_send + interval '12 hours', c.starts_at + v_delta - interval '3 hours')
  from public.events c
  where c.companion_of = l.event_id and c.status = 'published' and c.starts_at > now() and v_strong
   and private.can_decide(c.organizer_id)
   and least(v_send + interval '12 hours', c.starts_at + v_delta - interval '3 hours') > now()
  on conflict (companion_id) do nothing;
  update public.events c set starts_at = c.starts_at + v_delta, ends_at = c.ends_at + v_delta, updated_at = now()
  where c.companion_of = l.event_id and c.status = 'published' and c.starts_at > now()
   and not exists (select 1 from private.companion_decisions d where d.companion_id = c.id);
  -- Перенос назад на час збору: питати нема про що. Після зсуву — інакше цей збір зсунувся б назад.
  delete from private.companion_decisions d using public.events c
  where d.event_id = l.event_id and c.id = d.companion_id and d.proposed_at = c.starts_at;
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
  if v_strong then
   select case when count(distinct o.source_id) = 1 then min(s.name) end into v_seller
   from public.event_offers o join public.event_sources s on s.id = o.source_id
   where o.event_id = l.event_id and not (o.status = 'withdrawn' and o.ingest_run_id is null);
   v_since := coalesce((select max(x.id) from private.event_state_log x where x.event_id = l.event_id
                        and x.change = 'corrected' and x.id < l.id), 0);
   insert into private.event_change_pushes (event_id, user_id, change, state_version, target_id, title, body, send_after)
   with roles as (
    -- Супутник людини: власний збір важить більше за чужий. Учасник, заблокований з організатором, — не тут.
    select distinct on (x.user_id) x.* from (
     select c.organizer_id as user_id, c.id as companion_id, c.title, c.starts_at as meet, 0 as prio, d.proposed_at
     from public.events c left join private.companion_decisions d on d.companion_id = c.id
     where c.companion_of = l.event_id and c.status = 'published'
     union all
     select m.user_id, c.id, c.title, c.starts_at, 1, d.proposed_at from public.events c
     join public.event_members m on m.event_id = c.id and m.status = 'approved'
     left join private.companion_decisions d on d.companion_id = c.id
     where c.companion_of = l.event_id and c.status = 'published' and not private.blocked_between(m.user_id, c.organizer_id)) x
    order by x.user_id, x.prio),
   people as (
    -- Хто стежить; виправлення — лише тим, кому про цю подію вже пішов пуш після попереднього виправлення.
    select r.user_id from roles r where l.change <> 'corrected'
    union select s.user_id from public.saved_events s where s.event_id = l.event_id and l.change <> 'corrected'
    union select p.user_id from private.event_change_pushes p
     where l.change = 'corrected' and p.event_id = l.event_id and p.sent_at is not null and p.state_version > v_since)
   select l.event_id, u.user_id, l.change, l.id, coalesce(r.companion_id, l.event_id), coalesce(r.title, e.title),
    case when r.proposed_at is not null then private.companion_decision_body(case r.prio when 0 then 'ask' else 'wait' end,
      private.when_uk(l.to_starts_at, v_zone), 'о ' || to_char(r.meet at time zone v_zone, 'HH24:MI'),
      private.meet_uk(r.proposed_at, r.meet, v_zone))
     else private.event_change_body(l.change, private.when_uk(l.to_starts_at, v_zone), v_seller, r.companion_id is not null,
      private.when_uk(r.meet, v_zone)) end,
    v_send
   from people u left join roles r on r.user_id = u.user_id
   on conflict do nothing;
   get diagnostics n = row_count;
  end if;
 end if;

 -- Скасування чи відкладення закриває супутники — після того, як їхніх людей записали в чергу. Питати вже нема про що.
 if l.change in ('cancelled','postponed') then
  delete from private.companion_decisions where event_id = l.event_id;
  with closed as (update public.events c set status = 'cancelled', updated_at = now()
                  where c.companion_of = l.event_id and c.status = 'published' and c.ends_at > now() returning c.id)
  insert into private.companion_closures (companion_id, event_id) select id, l.event_id from closed on conflict do nothing;
 end if;
 perform set_config('poruch.follow_parent', '', true);
 if n > 0 and v_send <= now() then perform private.flush_event_change_pushes(); end if;
 return n;
end $$;

-- ───────────────────────────────────────────── строк минув: зсув сам

-- Кожні 15 хв. Уночі (у поясі події) чекаємо ранку, якщо до нової зустрічі ще 12 год і більше; строк і так не пізніше
-- ніж за 3 год до неї. Збір, якого вже нема чи який почався, питання знімає.
create function private.resolve_companion_decisions(p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path='' as $$
declare d record; n integer := 0;
begin
 for d in select x.*, c.status, c.starts_at as meet, c.time_zone from private.companion_decisions x
  join public.events c on c.id = x.companion_id where x.decide_by <= p_now for update of x skip locked
 loop
  if d.status <> 'published' or d.meet <= p_now or d.proposed_at <= p_now then
   delete from private.companion_decisions where companion_id = d.companion_id; continue;
  end if;
  if private.quiet_hours(p_now, d.time_zone) and d.proposed_at - p_now >= interval '12 hours' then continue; end if;
  perform set_config('poruch.follow_parent', 'on', true);
  update public.events set starts_at = d.proposed_at, ends_at = ends_at + (d.proposed_at - starts_at), updated_at = now()
  where id = d.companion_id;
  perform set_config('poruch.follow_parent', '', true);
  delete from private.companion_decisions where companion_id = d.companion_id;
  perform private.notify_companion(d.companion_id, 'organizer',
   private.companion_decision_body('auto', null, null, private.meet_uk(d.proposed_at, d.meet, d.time_zone)));
  perform private.notify_companion(d.companion_id, 'members',
   private.companion_decision_body('moved', null, null, private.when_uk(d.proposed_at, d.time_zone)));
  n := n + 1;
 end loop;
 return n;
end $$;

-- ───────────────────────────────────────────── R7б: організатор змінює час збору

create function private.move_companion(p_companion uuid, p_meet_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); c public.events; p public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into c from public.events where id = p_companion for update;
 if not found or c.companion_of is null then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if c.organizer_id <> v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
 if c.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if c.starts_at <= now() then raise exception 'EVENT_STARTED' using errcode='P0001'; end if;
 select * into p from public.events where id = c.companion_of;
 if p.status <> 'published' or p.starts_at <= now() then raise exception 'COMPANION_UNAVAILABLE' using errcode='P0001'; end if;
 -- Ті самі межі, що в create_companion, і сітка 15 хв від початку, як у CompanionRules.meetTimes.
 if p_meet_at is null or p_meet_at <= now() or p_meet_at > p.starts_at or p_meet_at < p.starts_at - interval '3 hours'
    or mod(extract(epoch from p.starts_at - p_meet_at)::bigint, 900) <> 0 then
  raise exception 'INVALID_MEET_TIME' using errcode='22023'; end if;
 delete from private.companion_decisions where companion_id = c.id;
 if p_meet_at = c.starts_at then return; end if;
 -- Службова зміна: guard_companion пропускає, events_push мовчить — учасникам свій текст.
 perform set_config('poruch.follow_parent', 'on', true);
 update public.events set starts_at = p_meet_at, ends_at = greatest(p.ends_at, p_meet_at + interval '1 minute'), updated_at = now()
 where id = c.id;
 perform set_config('poruch.follow_parent', '', true);
 perform private.notify_companion(c.id, 'members',
  private.companion_decision_body('moved', null, null, private.when_uk(p_meet_at, c.time_zone)));
end $$;

create function public.move_companion(p_companion uuid, p_meet_at timestamptz) returns void
language sql set search_path='' as $$ select private.move_companion(p_companion, p_meet_at); $$;

-- ───────────────────────────────────────────── клієнтам: питання й час афіші

alter type public.event_result
 add attribute meet_proposed timestamptz,
 add attribute meet_decide_by timestamptz,
 add attribute companion_of_starts_at timestamptz;

create or replace function private.event_rows(p_ids uuid[])
returns setof public.event_result language sql stable security definer set search_path='' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,
 coalesce(p.display_name, s.name),
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
 e.origin,s.name,e.canonical_url,e.import_status,e.price_min,e.is_free,
 -- Чат — лише своїм: організатору й підтвердженим. Запит і черга ще не всередині.
 case when e.organizer_id=auth.uid()
       or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved')
      then e.contact_url end,
 e.companion_of,
 pe.title,
 cs.state, cs.previous_starts_at, cs.checked_at,
 case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end,
 -- R7а: питання до організатора збору бачать усі, кому видно збір (учасникам — «Організатор вирішує»).
 case when e.status = 'published' then d.proposed_at end,
 case when e.status = 'published' then d.decide_by end,
 pe.starts_at
 from public.events e
 left join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 left join public.events pe on pe.id=e.companion_of
 left join private.companion_decisions d on d.companion_id=e.id
 cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
 where e.id=any(p_ids) and private.has_event_access(e.id)
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$$;

revoke all on function private.register_push_token(text, text, text[]), public.register_push_token(text, text, text[]),
 private.move_companion(uuid, timestamptz), public.move_companion(uuid, timestamptz) from public, anon, authenticated;
grant execute on function private.register_push_token(text, text, text[]), public.register_push_token(text, text, text[]),
 private.move_companion(uuid, timestamptz), public.move_companion(uuid, timestamptz) to authenticated;
revoke all on function private.can_decide(uuid), private.meet_uk(timestamptz, timestamptz, text),
 private.companion_decision_body(text, text, text, text), private.notify_companion(uuid, text, text),
 private.apply_event_change(bigint, boolean), private.resolve_companion_decisions(timestamptz)
 from public, anon, authenticated;

do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('companion-decisions', '*/15 * * * *', 'select private.resolve_companion_decisions()')$cron$;
 end if;
end $$;

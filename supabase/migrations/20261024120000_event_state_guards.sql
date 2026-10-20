-- Захисти тихого переносу в R4 (docs/event-offers.md, фаза 2, тінь). Перший prod-прогін 20.10 дав хибний перенос:
-- «Конотопська відьма», Київ, 21.10 (подія c2b5b8cf). Пропозицію badseller ще до фази 1 хибно прив'язали до 21.10, хоча
-- її адреса — сторінка сеансу 04.11 (…/konotopska-vidma-2026-11-04). Сторінка показала один сеанс 04.11, і R4 «переніс»
-- подію на 4 листопада. Насправді 21.10 живе на Concert.ua, а 04.11 — окрема жива подія з трьома продавцями.
--
-- Тихий перенос (вердикт moved_silent) тепер не рахується:
-- 1. якщо дата в slug адреси пропозиції не збігається з датою її сеансу — сторінка чужа (misattached);
-- 2. якщо на новий час у тому ж місті вже є жива подія з тією ж назвою, що існувала до зникнення пропозиції — сторінка
--    показує сусідній сеанс (taken);
-- 3. якщо інший продавець цієї події свіжо (за 36 год) бачить її на старий час — це конфлікт, не перенос.
-- У 1 і 2 пропозиція йде в чергу від'єднання. Явний перенос (EventRescheduled з previousStartDate) захисти 2 і 3 не
-- чіпають: продавець сказав прямо.
--
-- Плюс відкликання: стан, перенесений на час, на який більше ніщо не вказує, повертається на попередній, якщо там
-- подію бачать (пуш-виправлення у фазі 3). Перерахунок наприкінці робить це для вже записаних станів — тихо, без
-- «б надіслали»: пушів у тіні не було, а точність у звіті рахує це відкликання.

-- Що каже пропозиція: інформативні перевірки її поточного сеансу, витлумачені для R4. Тихий перенос — лише з тією ж
-- назвою, до 90 днів і зі старою датою ще попереду (як усиновлення у фазі 1): інакше продавець віддав адресу іншій
-- події, і це «зникла». misattached і taken — чужа сторінка: свідченням не є, пропозицію треба від'єднати.
create or replace function private.offer_says(p_offer uuid)
returns table (check_id bigint, checked_at timestamptz, says text, verdict text, new_start timestamptz, kind text,
 url text)
language sql stable set search_path='' as $$
 select c.id, c.checked_at,
  case
   -- Свідчить лише те, що сторінка каже про наш сеанс прямо (і явний перенос з previousStartDate); інші дати на
   -- чужій сторінці — не про нас.
   when g.misattached and c.verdict in ('moved_silent','date_missing','gone','redirect_away') then 'misattached'
   when s.says = 'moved' and c.verdict = 'moved_silent' and exists (
    select 1 from public.events t
    where t.id <> o.event_id and t.merged_into is null and t.origin = 'import' and t.status = 'published'
     and t.import_status = 'live' and t.city = e.city
     and t.starts_at between n.new_start - interval '1 minute' and n.new_start + interval '1 minute'
     and left(private.title_key(t.title), 20) = left(private.title_key(o.title), 20)
     -- Існувала до того, як пропозиція зникла: справжній перенос з новою адресою дамп заводить тим самим прогоном.
     and t.created_at < case when o.status = 'withdrawn' then least(o.updated_at, c.checked_at) else c.checked_at end
                        - interval '3 hours') then 'taken'
   else s.says end,
  c.verdict, n.new_start,
  -- Перенаправлення — свідчення лише там, де воно й дає відповідь: сторінка зникла чи сеанс переїхав на іншу адресу.
  case when c.why = 'listing' then 'listing' when c.verdict = 'gone' then 'http_404'
       when c.verdict = 'redirect_away' or (c.verdict = 'moved_silent' and c.redirected) then 'redirect' else 'jsonld' end,
  coalesce(c.final_url, c.url)
 from public.event_offers o
 join public.events e on e.id = o.event_id
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
 -- Дата в slug (badseller …-2026-11-04, другий сеанс дня — …-2026-11-04-1800) — дата сеансу цієї сторінки.
 cross join lateral (select substring(o.canonical_url from '-(\d{4}-\d{2}-\d{2})(?:-\d{4}(?:-\d+)?)?/?$')
   <> to_char(o.starts_at at time zone coalesce(e.time_zone, 'Europe/Kyiv'), 'YYYY-MM-DD') as misattached) g
 where o.id = p_offer and s.says is not null
  -- Лише про поточний сеанс: перевірка старого часу після переносу вже нічого не каже.
  and (c.expected = o.starts_at or n.new_start = o.starts_at);
$$;

-- Свідчення всіх пропозицій події, по одному на пропозицію (вхід private.event_state_rule). says:
-- cancelled / postponed / moved (сильні), alive (сторінка каже, що сеанс у силі), listed (дамп бачить у списку, сторінку
-- не читали), gone, none (знята, сторінку ще не прочитали). Ручне зняття — рішення людини, не свідчення.
-- fresh — подію бачили на її часі за останні 36 год (дамп чи сторінка); detach — чужа сторінка, у чергу від'єднання.
create or replace function private.offer_evidence(p_event uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o record; l record; st record; v_says text; v_on timestamptz; v_detach text; v jsonb := '[]';
begin
 for o in select x.id, x.linked, x.status, x.seen_at, x.starts_at, s.slug from public.event_offers x
  join public.event_sources s on s.id = x.source_id
  where x.event_id = p_event and not (x.status = 'withdrawn' and x.ingest_run_id is null)
  order by x.created_at, x.id
 loop
  select x.says into v_detach from private.offer_says(o.id) x order by x.checked_at desc, x.check_id desc limit 1;
  if v_detach is distinct from 'misattached' and v_detach is distinct from 'taken' then v_detach := null; end if;
  select x.* into l from private.offer_says(o.id) x where x.says not in ('misattached','taken')
  order by x.checked_at desc, x.check_id desc limit 1;
  if not found then
   v := v || jsonb_build_object('offer_id', o.id, 'slug', o.slug, 'linked', o.linked, 'starts_at', o.starts_at,
    'says', case when o.status = 'live' then 'listed' else 'none' end,
    'fresh', o.status = 'live' and o.seen_at > now() - interval '36 hours', 'detach', v_detach);
   continue;
  end if;
  v_says := l.says;
  if l.says = 'gone' then
   -- Сильне свідчення липке: сторінку скасованої чи перенесеної події часто прибирають, а 404 не каже, що подія в силі.
   select max(x.checked_at) into v_on from private.offer_says(o.id) x where x.says = 'alive';
   select x.* into st from private.offer_says(o.id) x
   where x.says in ('cancelled','postponed','moved') and x.checked_at > coalesce(v_on, '-infinity')
   order by x.checked_at desc, x.check_id desc limit 1;
   if found then l := st; v_says := st.says;
   elsif o.status = 'live' and o.seen_at > l.checked_at then v_says := 'listed';    -- дамп знову бачить у списку
   end if;
  end if;
  v := v || jsonb_build_object('offer_id', o.id, 'slug', o.slug, 'linked', o.linked, 'starts_at', o.starts_at,
   'says', v_says, 'at', l.checked_at, 'new_start', l.new_start, 'kind', l.kind, 'verdict', l.verdict, 'url', l.url,
   'fresh', case v_says when 'listed' then o.seen_at > now() - interval '36 hours'
                        when 'alive' then l.checked_at > now() - interval '36 hours' else false end,
   'detach', v_detach);
 end loop;
 return v;
end $$;

-- Таблиця R4 з docs/event-offers.md, рядок за рядком (тест на кожен — supabase/tests/event_state.sql). Чиста функція:
-- поточний стан, його попередній час і свідчення пропозицій → новий стан, зміна, свідчення, чи був би пуш. change null —
-- без змін. p_recheck — перерахунок через зміну правил: перенос, на який правила більше не вказують, відкликається й без
-- свідчення на старому часі (так, ніби його й не було). Тлумачення, погоджені 20.10: «скасовано» липке (offer_evidence); виправлення — лише коли сторінка сама знову
-- каже «в силі»; конфлікт агента — і для переносу; перенос важить більше за скасування. 20.10, після prod: тихий перенос від одного
-- продавця, коли інший свіжо бачить подію на старий час, — конфлікт; перенос, на який більше ніщо не вказує, — відкликати.
drop function private.event_state_rule(text, timestamptz, jsonb);
create function private.event_state_rule(p_state text, p_starts timestamptz, p_offers jsonb,
 p_previous timestamptz default null, p_recheck boolean default false,
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
  -- Лише тихі переноси, а інший продавець свіжо бачить подію на старий час: конфлікт, перечитати всіх.
  if v_times > 0
     and not exists (select 1 from jsonb_array_elements(v_moves) m where m->>'verdict' is distinct from 'moved_silent')
     and exists (select 1 from jsonb_array_elements(p_offers) x
                 where x->>'says' in ('alive','listed') and coalesce((x->>'fresh')::boolean, false)
                  and abs(extract(epoch from (x->>'starts_at')::timestamptz - p_starts)) < 60
                  and x->>'slug' not in (select m->>'slug' from jsonb_array_elements(v_moves) m)) then
   change := 'conflict'; evidence := v_moves; return;
  end if;
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
 -- Перенос, на який більше ніщо не вказує, а на попередньому часі подію бачать: відкликати.
 if p_state = 'scheduled' and p_previous is not null and not exists (
    select 1 from jsonb_array_elements(p_offers) x
    where (x->>'says' in ('alive','listed') and abs(extract(epoch from (x->>'starts_at')::timestamptz - p_starts)) < 60)
       or (x->>'says' = 'moved' and abs(extract(epoch from (x->>'new_start')::timestamptz - p_starts)) < 60)) then
  select x into evidence from jsonb_array_elements(p_offers) x
  where x->>'says' in ('alive','listed') and abs(extract(epoch from (x->>'starts_at')::timestamptz - p_previous)) < 60
  order by x->>'says' = 'alive' desc limit 1;
  if evidence is not null or p_recheck then
   starts_at := p_previous; change := 'corrected'; push := true; evidence := coalesce(evidence, p_offers); return;
  end if;
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

-- Перерахунок стану події з усіх свідчень і запис у журнал. Ідемпотентний: те саме свідчення вдруге змін не дає.
-- p_reason — перерахунок через зміну правил, а не нове свідчення: зміна пишеться без «б надіслали».
drop function if exists private.refresh_event_state(uuid);
create or replace function private.refresh_event_state(p_event uuid, p_reason text default null) returns text
language plpgsql security definer set search_path='' as $$
declare v_event public.events; v_state private.event_state; v_offers jsonb; r record; v_conflicts integer;
 v_push boolean;
begin
 select * into v_event from public.events where id = p_event;
 if not found or v_event.origin <> 'import' or v_event.merged_into is not null then return null; end if;
 insert into private.event_state (event_id, starts_at) values (p_event, v_event.starts_at) on conflict do nothing;
 select * into v_state from private.event_state where event_id = p_event for update;
 v_offers := private.offer_evidence(p_event);
 select * into r from private.event_state_rule(v_state.state, v_state.starts_at, v_offers, v_state.previous_starts_at,
  p_reason is not null);

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
 if r.change is null then return null; end if;

 v_push := r.push and p_reason is null;
 insert into private.event_state_log (event_id, from_state, to_state, from_starts_at, to_starts_at, change, evidence,
  would_push, recipients)
 values (p_event, v_state.state, r.state, v_state.starts_at, r.starts_at, r.change,
  case when p_reason is null then r.evidence else jsonb_build_object('reason', p_reason, 'evidence', r.evidence) end,
  v_push, case when v_push then private.event_watchers(p_event) else '{}' end);
 if r.change <> 'conflict' then
  update private.event_state set state = r.state, starts_at = r.starts_at, evidence = r.evidence,
   previous_starts_at = case when r.change = 'moved' then v_state.starts_at
                             when r.starts_at <> v_state.starts_at then null       -- перенос відкликано
                             else previous_starts_at end,
   state_changed_at = now()
  where event_id = p_event;
 end if;
 return r.change;
end $$;

revoke all on function private.offer_says(uuid), private.offer_evidence(uuid),
 private.event_state_rule(text, timestamptz, jsonb, timestamptz, boolean), private.refresh_event_state(uuid, text)
 from public, anon, authenticated;

-- Уже записані стани — за новими правилами, тихо.
do $$ declare v_event uuid; n integer := 0; begin
 for v_event in select event_id from private.event_state loop
  if private.refresh_event_state(v_event, 'правила R4 20.10: тихий перенос — чужа сторінка, зайнята ціль, свіжий інший продавець') is not null
  then n := n + 1; end if;
 end loop;
 raise notice 'event_state: перераховано за новими правилами, змінилось %', n;
end $$;

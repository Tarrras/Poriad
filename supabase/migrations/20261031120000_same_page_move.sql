-- «Зайнята ціль» блокувала справжній перенос (docs/event-offers.md, «Борги фаз 1–2», перенос на тій самій сторінці).
-- Погоджено з користувачем 20.10.
--
-- Захист 20261024120000 не рахує тихого переносу, коли на новий час уже є жива подія, що існувала до зникнення
-- пропозиції: це сусідній сеанс. Але продавці переносять сеанс і на тій самій сторінці. Karabas і concert.ua лишають
-- адресу, badseller перенаправляє стару на нову. Ключ пропозиції — адреса + час, тож дамп заводить нову пропозицію, і
-- вона лягає в подію, яку інші продавці продають на новий час давно. Приклад prod: FOREX UKRAINE, Львів. Karabas на
-- тій самій сторінці мав 23.10, тим самим прогоном 15.10 — 20.11. Стара badseller-адреса перенаправляє на сторінку
-- 20.11, а пропозиція badseller на неї з'явилась у цілі 20.10, коли 23.10 давно зник.
--
-- 1. Ціль не «зайнята», якщо в ній є пропозиція того самого продавця з тією самою сторінкою (canonical_url, кінцева
--    адреса перевірки), що з'явилась уже після зникнення нашої (не раніше ніж за 3 год). Сусідній сеанс на тій самій
--    сторінці жив поруч і раніше — він лишається під захистом. R4 вирішує перенос, як завжди (конфлікт зі свіжим
--    іншим продавцем, друге свідчення після виправлення), з «б надіслали» тим, хто стежить за старою подією.
-- 2. Прийнятий перенос на таку ціль зливає стару подію в ціль (private.merge_event, причина same_page_move). Інакше
--    з перемикачем людина отримала б «Перенесено», а подія показувала б «Не знайшли в продажу». Злиття — видимий
--    наслідок, тож лише з перемикачем event_changes, разом з пушами: без нього той, хто зберіг, мовчки опинився б на
--    іншій даті.
-- 3. Черга від'єднання: рядок, чия причина більше не в силі, — cleared; злитий — merged.

alter table private.offer_detach_queue drop constraint offer_detach_queue_resolution_check;
alter table private.offer_detach_queue add constraint offer_detach_queue_resolution_check
 check (resolution in ('detached','kept','cleared','merged'));

-- Тіло — з 20261024120000_event_state_guards; у «зайнятій цілі» — виняток для тієї самої сторінки продавця.
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
     and t.created_at < v.vanished - interval '3 hours'
     -- Та сама сторінка того самого продавця з'явилась у цілі вже після зникнення — продавець переніс сеанс.
     and not exists (select 1 from public.event_offers x where x.event_id = t.id and x.source_id = o.source_id
          and rtrim(x.canonical_url, '/') in (rtrim(o.canonical_url, '/'), rtrim(coalesce(c.final_url, c.url), '/'))
          and x.created_at >= v.vanished - interval '3 hours')) then 'taken'
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
 cross join lateral (select case when o.status = 'withdrawn' then least(o.updated_at, c.checked_at)
                                 else c.checked_at end as vanished) v
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

-- Прийнятий R4 перенос на сторінку того самого продавця: стара подія зливається в ціль. Ціль — одна жива подія з
-- живою пропозицією того самого продавця на новий час, чия сторінка — сторінка знятої пропозиції старої (canonical_url
-- чи кінцева адреса перевірки). Сусідній сеанс сюди не дійде: його перенос R4 не прийняв. Лише з перемикачем.
create or replace function private.merge_page_moves() returns integer
language plpgsql security definer set search_path='' as $$
declare r record; v_offers uuid[]; n integer := 0;
begin
 if not private.flag('event_changes') then return 0; end if;
 for r in
  select st.event_id as from_id, min(x.event_id::text)::uuid as into_id
  from private.event_state st
  join public.events e on e.id = st.event_id and e.merged_into is null and e.origin = 'import' and e.status = 'published'
  join public.event_offers o on o.event_id = e.id and o.status = 'withdrawn' and o.canonical_url is not null
  join public.event_offers x on x.source_id = o.source_id and x.status = 'live' and x.event_id <> e.id
   and abs(extract(epoch from x.starts_at - st.starts_at)) < 60
   and rtrim(x.canonical_url, '/') in (rtrim(o.canonical_url, '/'),
    (select rtrim(c.final_url, '/') from private.offer_checks c where c.offer_id = o.id and c.why <> 'listing'
       and c.verdict not in ('gone','redirect_away','no_jsonld','error') order by c.checked_at desc, c.id desc limit 1))
  join public.events f on f.id = x.event_id and f.merged_into is null and f.origin = 'import' and f.status = 'published'
   and f.import_status = 'live'
  where st.state = 'scheduled' and st.previous_starts_at is not null and st.starts_at > now()
   and not private.event_frozen(e.id) and not private.event_frozen(f.id)
  group by st.event_id having count(distinct x.event_id) = 1
 loop
  begin
   v_offers := array(select id from public.event_offers where event_id = r.from_id);
   perform private.merge_event(r.from_id, r.into_id, 'same_page_move');
   update private.offer_detach_queue set resolution = 'merged', resolved_at = now()
   where offer_id = any(v_offers) and (resolution is null or resolution = 'cleared');
   n := n + 1;
  exception when others then raise warning 'merge_page_moves % -> %: %', r.from_id, r.into_id, sqlerrm;
  end;
 end loop;
 return n;
end $$;

-- Тіло — з 20261030120000_offer_cleanup; додано cleared: чужа сторінка чи зайнята ціль, яких свіже свідчення вже не
-- показує (сторінка знову показала наш сеанс, ціль виявилась тією самою сторінкою, дамп сам переніс пропозицію).
-- ponytail: cleared не відкривається знову, якщо причина повернеться; відкривати, якщо таке трапиться.
create or replace function private.process_offer_detach_queue(p_since timestamptz default now()) returns integer
language plpgsql security definer set search_path='' as $$
declare v_offer uuid; n integer := 0;
begin
 update private.offer_detach_queue q set resolution = 'detached', resolved_at = now()
 from public.event_offers o where o.id = q.offer_id and q.resolution is null and o.linked = 'manual';
 update private.offer_detach_queue q set resolution = 'cleared', resolved_at = now()
 from public.event_offers o join public.events e on e.id = o.event_id and e.merged_into is null
 where o.id = q.offer_id and q.resolution is null and q.evidence->>'detach' is not null and e.ends_at > p_since
  and not exists (select 1 from jsonb_array_elements(private.offer_evidence(o.event_id)) x
                  where x->>'offer_id' = o.id::text and x->>'detach' is not null);
 for v_offer in
  select q.offer_id from private.offer_detach_queue q
  join public.event_offers o on o.id = q.offer_id
  join public.events e on e.id = o.event_id and e.merged_into is null and e.ends_at > p_since
  where q.resolution is null and o.status = 'withdrawn'
   and exists (select 1 from public.event_offers x where x.event_id = o.event_id and x.id <> o.id and x.status = 'live')
 loop
  begin
   perform private.detach_offer(v_offer);
   update private.offer_detach_queue set resolution = 'detached', resolved_at = now() where offer_id = v_offer;
   n := n + 1;
  exception when others then raise warning 'offer_detach_queue %: %', v_offer, sqlerrm;
  end;
 end loop;
 return n;
end $$;

-- Тіло — з 20261030120000_offer_cleanup; після перерахунку стану — злиття прийнятих переносів на ту саму сторінку.
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
 perform private.merge_url_twins();
 for v_event in select distinct o.event_id from jsonb_to_recordset(p_rows) as x(offer_id uuid)
  join public.event_offers o on o.id = x.offer_id
 loop
  if private.refresh_event_state(v_event) is not null then n := n + 1; end if;
 end loop;
 perform private.merge_page_moves();
 perform private.process_offer_detach_queue();
 return n;
end $$;

revoke all on function private.offer_says(uuid), private.merge_page_moves(),
 private.process_offer_detach_queue(timestamptz), private.record_offer_checks(jsonb) from public, anon, authenticated;

-- Наявні: подіям з нерозібраною «зайнятою ціллю» — перерахунок за новим правилом. Це свідчення сторінки, а не зміна
-- правил тлумачення, тож «б надіслали» пишеться, як за нової перевірки. Після виправлення перенос чекає другого
-- свідчення (offer_checks_due перечитає щогодини). Потім черга; злиття — з перемикачем.
do $$ declare v_event uuid; v_moved integer := 0; v_waiting integer := 0; begin
 for v_event in select distinct o.event_id from private.offer_detach_queue q
  join public.event_offers o on o.id = q.offer_id join public.events e on e.id = o.event_id and e.ends_at > now()
  where q.resolution is null and q.evidence->>'detach' = 'taken'
 loop
  if private.refresh_event_state(v_event) = 'moved' then v_moved := v_moved + 1;
  elsif (select unconfirmed is not null from private.event_state where event_id = v_event) then v_waiting := v_waiting + 1;
  end if;
 end loop;
 perform private.process_offer_detach_queue();
 raise notice 'same_page_move: перенесено %, чекають другого свідчення %, cleared %, злито %, у черзі чекає %',
  v_moved, v_waiting, (select count(*) from private.offer_detach_queue where resolution = 'cleared'),
  private.merge_page_moves(), (select count(*) from private.offer_detach_queue where resolution is null);
end $$;

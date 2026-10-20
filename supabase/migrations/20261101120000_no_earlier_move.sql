-- Тихий перенос на раніше — не перенос (docs/event-offers.md, «Борги фаз 1–2», перенос на раніше). Погоджено з
-- користувачем 20.10, до воріт ~27.10.
--
-- R4 прийняв у тіні 6 тихих переносів на дату, раніше за сеанс більш ніж на добу (prod 20.10), і всі вони — інший показ,
-- а не перенос. badseller перенаправляє сторінку зниклого показу репертуару на найближчий інший («Лісова пісня»
-- 07.11 → 22.10, «Бояриня», «Дзеркало сумної коханки», «Світ у горіховій шкаралупі»). internet_bilet має одну сторінку
-- на театр чи шоу («Театр Чорний квадрат», «Alice»): вона показує наступний показ під тією самою назвою. Переносять
-- на пізніше; на раніше в межах доби (інша година того ж дня, Іво Бобул 19:00 → 18:00) лишається переносом.
--
-- Тепер сторінка, що показує один сеанс раніше за наш більш ніж на добу (вердикт moved_silent, з перенаправленням чи
-- без), каже про наш сеанс «зник» (gone). Явний перенос (EventRescheduled з previousStartDate) не чіпаємо: продавець
-- сказав прямо. Класифікатор сторінки (verdict.ts, shadow_checks.verdict) той самий — змінюється тлумачення в R4. Дамп
-- не усиновлює такий перенос (tools/ingest/emit.py, той самий поріг), інакше пропозиція переїхала б, а R4 її не визнав.
--
-- Уже прийняті переноси на раніше перераховуються тихо (без «б надіслали»), як захисти 20261024120000: спершу
-- відкликання на старий час, потім, якщо інших живих продавців нема, — unknown («не знайшли в продажу», пуша нема).
-- Крім тих, що дамп уже усиновив (пропозиція жива на новому часі, «Театр Чорний квадрат»): старого сеансу нема ніде.
-- Не в чергу від'єднання: пропозиція прив'язана до свого сеансу правильно, від'єднувати нема від чого.

-- Тіло — з 20261031120000_same_page_move; у тихому переносі — поріг «не раніше ніж на добу».
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
         -- Раніше більш ніж на добу — не перенос: сторінка показує інший показ (див. шапку).
         and n.new_start >= c.expected - interval '1 day'
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

revoke all on function private.offer_says(uuid) from public, anon, authenticated;

do $$ declare v_event uuid; n integer := 0; v_change text; v_reason text :=
  'правила R4 20.10: тихий перенос на раніше більш ніж на добу — інший показ, не перенос'; begin
 for v_event in select s.event_id from private.event_state s
  where s.state = 'scheduled' and s.previous_starts_at is not null
   and s.starts_at < s.previous_starts_at - interval '1 day'
   and exists (select 1 from private.event_state_log l where l.event_id = s.event_id and l.change = 'moved'
               and l.to_starts_at = s.starts_at and l.evidence->>'verdict' = 'moved_silent')
   -- Дамп уже сам переніс пропозицію на новий час і бачить її там живою: старого сеансу нема ніде, лишаємо.
   and not exists (select 1 from public.event_offers o where o.event_id = s.event_id and o.status = 'live'
                   and abs(extract(epoch from o.starts_at - s.starts_at)) < 60)
 loop
  -- Перший перерахунок відкликає перенос, другий бачить, що сторінки більше нічого не кажуть про сеанс.
  v_change := private.refresh_event_state(v_event, v_reason);
  if v_change = 'corrected' then n := n + 1; perform private.refresh_event_state(v_event, v_reason); end if;
 end loop;
 raise notice 'no_earlier_move: відкликано %, з них unknown %', n,
  (select count(*) from private.event_state_log l where l.change = 'unknown' and l.evidence->>'reason' = v_reason);
end $$;

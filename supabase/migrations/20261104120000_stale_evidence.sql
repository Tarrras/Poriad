-- Два нові типи хибних змін з воріт фази 2 (docs/gate-2026-10-24.md, «Що виправити спершу», пункти 1–2).
--
-- 1. Несвіже «скасовано/відкладено» проти свіжого живого продавця. «Віталій Лобач», Київ, 30.10 (61274d14): Karabas зняв
--    подію 25.09, а його сторінку вперше прочитали 20.10, у першому проході по нагромадженому, — EventPostponed. Concert.ua
--    той самий сеанс продає (EventScheduled, InStock), але R4 відклав подію: при ввімкненні перемикача вона зникла б з
--    афіші. Тепер свідчення, яке вперше прочитали через 48+ год після зникнення пропозиції, не перебиває продавця, що
--    свіжо (за 36 год) продає той самий сеанс: це конфлікт (перечитати всіх, двічі поспіль → черга від'єднання), а вже
--    застосований стан відкликається. Свіже скасування, прочитане одразу після зникнення, не чіпаємо: воно липке, як і
--    було.
-- 2. Годинний зсув поясу — не перенос. TRANSMISSION 2.0 (bdc29a3c), Ганна Кочегура (b6191423), Hotel 57 (15a1ab45):
--    сторінки з 18.10 показують той самий місцевий час, а стара пропозиція лежала на годину раніше — зимовий сеанс,
--    записаний з літнім зсувом +03. Тихий перенос рівно на годину пізніше зимового сеансу тепер «зник» (gone).
--
-- Обидва — лише тлумачення свідчень у R4; класифікатор сторінки (verdict.ts, shadow_checks.verdict) той самий. Уже
-- записані стани перераховуються тихо (без «б надіслали»), як у 20261101120000_no_earlier_move: Лобач → corrected
-- (scheduled на 30.10); TRANSMISSION → corrected на 13:00 і далі unknown (окрема жива подія на 14:00 лишається);
-- Кочегура й Hotel 57 не змінюються — живі пропозиції вже стоять на правильному часі.

-- Тіло — з 20261101120000_no_earlier_move; у тихому переносі — виняток для годинного зсуву поясу.
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
         -- Рівно на годину пізніше зимового сеансу — наш літній зсув (+03 замість +02) у старій пропозиції, а не
         -- перенос (TRANSMISSION 2.0, Ганна Кочегура, Hotel 57: сторінки з 18.10 показують той самий час).
         -- ponytail: справжній перенос на годину пізніше взимку теж стане «зник» без пуша; час однаково підтягне дамп.
         and not (n.new_start - c.expected = interval '1 hour'
                  and (c.expected at time zone coalesce(e.time_zone, 'Europe/Kyiv'))
                      - (c.expected at time zone 'UTC') = interval '2 hours')
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


-- Тіло — з 20261024120000_event_state_guards; додано позначку stale.
create or replace function private.offer_evidence(p_event uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o record; l record; st record; v_says text; v_on timestamptz; v_detach text; v_stale boolean; v jsonb := '[]';
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
  -- Несвіже: сторінку вперше прочитали через 48+ год після того, як пропозиція зникла зі списку (перший прохід 20.10
  -- по нагромадженому). Таке «скасовано/відкладено» могло давно застаріти — event_state_rule не дає йому перебити
  -- свіжого живого продавця.
  v_stale := o.status = 'withdrawn' and v_says in ('cancelled','postponed')
   and (select min(c.checked_at) from private.offer_checks c where c.offer_id = o.id and c.why <> 'listing'
        and c.checked_at > o.seen_at) > o.seen_at + interval '48 hours';
  v := v || jsonb_build_object('offer_id', o.id, 'slug', o.slug, 'linked', o.linked, 'starts_at', o.starts_at,
   'says', v_says, 'stale', v_stale, 'at', l.checked_at, 'new_start', l.new_start, 'kind', l.kind, 'verdict', l.verdict, 'url', l.url,
   'fresh', case v_says when 'listed' then o.seen_at > now() - interval '36 hours'
                        when 'alive' then l.checked_at > now() - interval '36 hours' else false end,
   'detach', v_detach);
 end loop;
 return v;
end $$;

-- Тіло — з 20261024120000_event_state_guards; додано несвіже сильне свідчення проти свіжого продавця.
create or replace function private.event_state_rule(p_state text, p_starts timestamptz, p_offers jsonb,
 p_previous timestamptz default null, p_recheck boolean default false,
 out state text, out starts_at timestamptz, out change text, out evidence jsonb, out push boolean)
language plpgsql stable set search_path='' as $$
declare v_strong jsonb; v_moves jsonb; v_times integer; v_stale jsonb;
begin
 state := p_state; starts_at := p_starts; push := false;
 -- Перенос на час, який стан уже має, — не зміна.
 select coalesce(jsonb_agg(x order by (x->>'at')::timestamptz desc), '[]') into v_strong
 from jsonb_array_elements(p_offers) x
 where x->>'says' in ('cancelled','postponed')
    or (x->>'says' = 'moved' and abs(extract(epoch from (x->>'new_start')::timestamptz - p_starts)) >= 60);

 -- Несвіже «скасовано/відкладено», а інший продавець свіжо продає той самий сеанс (Віталій Лобач, prod 20.10: Karabas
 -- зняв подію 25.09 і пише EventPostponed, Concert.ua продає): не сильне свідчення, а конфлікт — перечитати всіх,
 -- двічі поспіль → черга від'єднання. Уже застосований такий стан відкликається.
 select jsonb_agg(x) into v_stale from jsonb_array_elements(v_strong) x
 where coalesce((x->>'stale')::boolean, false) and exists (select 1 from jsonb_array_elements(p_offers) y
  where y->>'says' in ('alive','listed') and coalesce((y->>'fresh')::boolean, false)
   and abs(extract(epoch from (y->>'starts_at')::timestamptz - p_starts)) < 60 and y->>'slug' <> x->>'slug');
 if v_stale is not null then
  select coalesce(jsonb_agg(x order by (x->>'at')::timestamptz desc), '[]') into v_strong
  from jsonb_array_elements(v_strong) x
  where not exists (select 1 from jsonb_array_elements(v_stale) s where s->>'offer_id' = x->>'offer_id');
  if jsonb_array_length(v_strong) = 0 then
   if p_state in ('cancelled','postponed') then
    select y into evidence from jsonb_array_elements(p_offers) y
    where y->>'says' in ('alive','listed') and coalesce((y->>'fresh')::boolean, false)
     and abs(extract(epoch from (y->>'starts_at')::timestamptz - p_starts)) < 60
    order by y->>'says' = 'alive' desc limit 1;
    state := 'scheduled'; change := 'corrected'; push := true; return;
   end if;
   change := 'conflict'; evidence := v_stale; return;
  end if;
 end if;

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


revoke all on function private.offer_says(uuid), private.offer_evidence(uuid),
 private.event_state_rule(text, timestamptz, jsonb, timestamptz, boolean) from public, anon, authenticated;

-- Уже записані стани за новими правилами, тихо. Кандидати: відкладені чи скасовані й ті, кого перенесли тихо рівно на
-- годину пізніше. Відкликаний перенос перераховується вдруге: якщо на старому часі подію ніхто не бачить — unknown.
do $$ declare v_event uuid; v_change text; n_corr integer := 0; n_unknown integer := 0; v_reason text :=
  'правила R4 24.10: несвіже «відкладено/скасовано» проти свіжого продавця, годинний зсув поясу — не перенос'; begin
 for v_event in select s.event_id from private.event_state s join public.events e on e.id = s.event_id
  where e.ends_at > now() and (s.state in ('cancelled','postponed')
   or (s.state = 'scheduled' and s.previous_starts_at is not null and s.starts_at - s.previous_starts_at = interval '1 hour'))
  order by s.event_id
 loop
  v_change := private.refresh_event_state(v_event, v_reason);
  if v_change = 'corrected' then
   n_corr := n_corr + 1;
   if private.refresh_event_state(v_event, v_reason) = 'unknown' then n_unknown := n_unknown + 1; end if;
  end if;
 end loop;
 raise notice 'stale_evidence: відкликано %, з них unknown %', n_corr, n_unknown;
end $$;

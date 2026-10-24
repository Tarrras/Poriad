-- Продавці кажуть різне (рішення користувача 24.10): один пише «скасовано» чи «відкладено», а інший той самий сеанс
-- свіжо продає. Свіже свідчення досі перемагало, і подія зникала з афіші, поки на неї продають квитки: «СТЕНДАП
-- СУБОТА», Київ, 31.10 (ffd1d088) — Badseller EventCancelled, Concert.ua EventScheduled/InStock (перший обхід після
-- ввімкнення перемикача, 24.10). Тепер це конфлікт, як і несвіже свідчення з 20261104120000: подія в силі, пуша нема,
-- двічі поспіль → черга від'єднання. А клієнт на деталях каже «Один із продавців, Badseller, повідомив про
-- скасування» — для цього в `offers` з'являється `says`.
--
-- Уже записані стани перераховуються тихо (без пуша), як у 20261104120000_stale_evidence.

-- Тіло — з 20261104120000_stale_evidence; конфлікт — будь-яке «скасовано/відкладено» проти свіжого продавця.
create or replace function private.event_state_rule(p_state text, p_starts timestamptz, p_offers jsonb,
 p_previous timestamptz default null, p_recheck boolean default false,
 out state text, out starts_at timestamptz, out change text, out evidence jsonb, out push boolean)
language plpgsql stable set search_path='' as $$
declare v_strong jsonb; v_moves jsonb; v_times integer; v_disputed jsonb;
begin
 state := p_state; starts_at := p_starts; push := false;
 -- Перенос на час, який стан уже має, — не зміна.
 select coalesce(jsonb_agg(x order by (x->>'at')::timestamptz desc), '[]') into v_strong
 from jsonb_array_elements(p_offers) x
 where x->>'says' in ('cancelled','postponed')
    or (x->>'says' = 'moved' and abs(extract(epoch from (x->>'new_start')::timestamptz - p_starts)) >= 60);

 -- «Скасовано/відкладено» одного продавця, а інший свіжо продає той самий сеанс: не сильне свідчення, а конфлікт —
 -- подія в силі, перечитати всіх, двічі поспіль → черга від'єднання; клієнт показує «Один із продавців повідомив про
 -- скасування» (offers[].says). Уже застосований такий стан відкликається. Спершу так було лише з несвіжим свідченням
 -- (Віталій Лобач: Karabas зняв подію 25.09, Concert.ua продає); 24.10 — і зі свіжим («СТЕНДАП СУБОТА»: Badseller
 -- EventCancelled, Concert.ua EventScheduled), рішення користувача.
 select jsonb_agg(x) into v_disputed from jsonb_array_elements(v_strong) x
 where x->>'says' in ('cancelled','postponed') and exists (select 1 from jsonb_array_elements(p_offers) y
  where y->>'says' in ('alive','listed') and coalesce((y->>'fresh')::boolean, false)
   and abs(extract(epoch from (y->>'starts_at')::timestamptz - p_starts)) < 60 and y->>'slug' <> x->>'slug');
 if v_disputed is not null then
  select coalesce(jsonb_agg(x order by (x->>'at')::timestamptz desc), '[]') into v_strong
  from jsonb_array_elements(v_strong) x
  where not exists (select 1 from jsonb_array_elements(v_disputed) s where s->>'offer_id' = x->>'offer_id');
  if jsonb_array_length(v_strong) = 0 then
   if p_state in ('cancelled','postponed') then
    select y into evidence from jsonb_array_elements(p_offers) y
    where y->>'says' in ('alive','listed') and coalesce((y->>'fresh')::boolean, false)
     and abs(extract(epoch from (y->>'starts_at')::timestamptz - p_starts)) < 60
    order by y->>'says' = 'alive' desc limit 1;
    state := 'scheduled'; change := 'corrected'; push := true; return;
   end if;
   change := 'conflict'; evidence := v_disputed; return;
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


-- Тіло — з 20261026120000_event_state_client; додано `says`: що сторінка продавця прямо каже про цей сеанс — останнє з
-- «в силі», «скасовано», «відкладено» (404 після скасування його не спростовує, як і в R4). Клієнт показує це, лише коли
-- подія в силі: тоді інший продавець її продає.
create or replace function private.event_offers_json(p_event uuid, p_primary text)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('source', x.name, 'url', x.canonical_url,
   'price_min', x.price_min, 'is_free', x.is_free, 'live', x.status = 'live', 'says', x.says))
   order by x.canonical_url is distinct from p_primary, x.status <> 'live', x.weight desc, x.name)
 from (
  select distinct on (o.source_id) o.canonical_url, o.price_min, o.is_free, o.status, s.name, s.weight,
   (select nullif(c.verdict, 'scheduled') from private.offer_checks c
    where c.offer_id = o.id and c.expected = o.starts_at and c.verdict in ('cancelled','postponed','scheduled')
    order by c.checked_at desc limit 1) as says
  from public.event_offers o join public.event_sources s on s.id = o.source_id
  where o.event_id = p_event and o.canonical_url is not null and s.enabled
  order by o.source_id, o.canonical_url is distinct from p_primary, o.status <> 'live', o.price_min nulls last
 ) x;
$$;

revoke all on function private.event_state_rule(text, timestamptz, jsonb, timestamptz, boolean),
 private.event_offers_json(uuid, text) from public, anon, authenticated;

-- Уже записані «скасовано/відкладено», які тепер — конфлікт: подія повертається в афішу тихо.
do $$ declare v_event uuid; n integer := 0; v_ids text := ''; begin
 for v_event in select s.event_id from private.event_state s join public.events e on e.id = s.event_id
  where e.ends_at > now() and s.state in ('cancelled','postponed') order by s.event_id
 loop
  if private.refresh_event_state(v_event, 'продавці кажуть різне, 24.10: «скасовано» одного проти свіжого продажу іншого')
     = 'corrected' then
   n := n + 1; v_ids := v_ids || ' ' || left(v_event::text, 8);
  end if;
 end loop;
 raise notice 'seller_report: повернуто в афішу %:%', n, v_ids;
end $$;

-- Два борги фаз 1–2 (docs/event-offers.md, «Борги фаз 1–2»). Погоджено з користувачем 20.10.
--
-- 1. Черга від'єднання (private.offer_detach_queue) лежала нерозібраною, а фаза 4 показує всіх продавців події, тож
--    хибно прив'язана пропозиція — кнопка не на той сеанс. Тепер черга розбирається сама за одним правилом:
--    пропозиція знята (дамп її вже не бачить), у її події лишається інша жива, а причина досі в силі. Знята
--    від'єднана пропозиція стає окремою знятою подією — у пошуку її нема, збереження лишаються на старій. Живу чи
--    останню живу від'єднує лише людина: інакше з'явиться видимий дубль (заморожене дамп не зливає) чи подія стане
--    «не знайшли» для тих, хто її зберіг.
-- 2. Дублі, яких дамп не зведе. Продавець змінює адресу сеансу (badseller прибрав «(Театр Юного Глядача)» з назви), стара
--    перенаправляє на нову, а дамп групує лише живе: дві події одного сеансу. Пропозиції одного продавця на ту саму
--    хвилину, що ведуть на ту саму сторінку події, — один сеанс: події зливаються (private.merge_event, журнал
--    event_merges). Перейменування повторюються, тож це робить кожна адресна перевірка, а міграція — раз для наявних.

alter table private.offer_detach_queue
 add column resolution text check (resolution in ('detached','kept')),
 add column resolved_at timestamptz;

-- Двійники за кінцевою адресою. Кінцева — final_url останньої перевірки, що прочитала сторінку події (не 404, не
-- перенаправлення на список: інакше дві події, що ведуть на афішу міста, злились би), інакше canonical_url.
-- Назву не порівнюємо: продавець перейменовує саме її («Харків Вечір…», «Прем'єра "Соляріс"»).
-- Лишається жива → та, чия адреса і є кінцевою (продавець зараз там) → старша. Заморожені (manual) не чіпаємо.
-- p_since — сеанси пізніші за нього: перевірка бере майбутнє, міграція — і недавнє минуле.
create or replace function private.merge_url_twins(p_since timestamptz default now()) returns integer
language plpgsql security definer set search_path='' as $$
declare g record; v_ids uuid[]; v_into uuid; v_from uuid; n integer := 0;
begin
 for g in
  with f as (
   select o.event_id, o.source_id, o.starts_at, rtrim(coalesce(c.final_url, o.canonical_url), '/') as url
   from public.event_offers o
   join public.events e on e.id = o.event_id and e.merged_into is null and e.origin = 'import' and e.status = 'published'
   left join lateral (select c.final_url from private.offer_checks c
    where c.offer_id = o.id and c.why <> 'listing' and c.verdict not in ('gone','redirect_away','no_jsonld','error')
    order by c.checked_at desc, c.id desc limit 1) c on true
   where o.canonical_url is not null and o.starts_at > p_since and not private.event_frozen(o.event_id))
  select f.source_id, f.url, array_agg(distinct f.event_id) as ids from f
  group by f.source_id, f.starts_at, f.url having count(distinct f.event_id) > 1
 loop
  -- Подія може бути у двох групах (дві адреси): після першого злиття її id — надгробок.
  v_ids := array(select distinct private.live_event_id(x) from unnest(g.ids) x);
  continue when cardinality(v_ids) < 2;
  select e.id into v_into from public.events e where e.id = any(v_ids)
  order by e.import_status = 'live' desc,
   exists (select 1 from public.event_offers o where o.event_id = e.id and o.source_id = g.source_id
           and rtrim(o.canonical_url, '/') = g.url) desc,
   e.created_at, e.id
  limit 1;
  foreach v_from in array v_ids loop
   continue when v_from = v_into;
   -- Збій одного злиття не зупиняє адресну перевірку (record_offer_checks пише пакет однією транзакцією).
   begin
    perform private.merge_event(v_from, v_into, 'url_twin');
    n := n + 1;
   exception when others then raise warning 'merge_url_twins % -> %: %', v_from, v_into, sqlerrm;
   end;
  end loop;
 end loop;
 return n;
end $$;

-- Розбір черги від'єднання: див. шапку. Що не підпадає, чекає й перевіряється знову щоразу: у події може з'явитись
-- жива пропозиція. Рукою: select private.detach_offer('<offer>') (рядок позначиться сам) або
-- update private.offer_detach_queue set resolution = 'kept', resolved_at = now() where offer_id = '<offer>'.
-- p_since — події, що закінчуються пізніше (як у merge_url_twins).
create or replace function private.process_offer_detach_queue(p_since timestamptz default now()) returns integer
language plpgsql security definer set search_path='' as $$
declare v_offer uuid; n integer := 0;
begin
 update private.offer_detach_queue q set resolution = 'detached', resolved_at = now()
 from public.event_offers o where o.id = q.offer_id and q.resolution is null and o.linked = 'manual';
 for v_offer in
  select q.offer_id from private.offer_detach_queue q
  join public.event_offers o on o.id = q.offer_id
  join public.events e on e.id = o.event_id and e.merged_into is null and e.ends_at > p_since
  where q.resolution is null and o.status = 'withdrawn'
   and exists (select 1 from public.event_offers x where x.event_id = o.event_id and x.id <> o.id and x.status = 'live')
   -- Причина досі в силі: чужа сторінка й зайнята ціль — за свіжим свідченням (сторінка могла знову показати наш
   -- сеанс); конфлікт у черзі вже двічі поспіль.
   and (q.evidence->>'detach' is null or exists (
        select 1 from jsonb_array_elements(private.offer_evidence(o.event_id)) x
        where x->>'offer_id' = o.id::text and x->>'detach' is not null))
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

-- Тіло — з 20261023120000_event_state; додано двійників перед перерахунком стану (пропозиції вже в живій події) і
-- розбір черги після (перерахунок її поповнює).
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
 perform private.process_offer_detach_queue();
 return n;
end $$;

-- Тіло — з 20261023120000_event_state; черга від'єднання — лише нерозібране майбутнє («людині» — жива пропозиція) і
-- скільки від'єднано за період.
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
 select 'черга від''єднання', case when o.status = 'live' then 'людині · ' else 'чекає · ' end || o.event_id::text, 1,
  q.evidence->>'url'
 from private.offer_detach_queue q join public.event_offers o on o.id = q.offer_id
 join public.events e on e.id = o.event_id and e.ends_at > now()
 where q.resolution is null
 union all
 select 'черга від''єднання', 'від''єднано за період', count(*), null from private.offer_detach_queue q
 where q.resolution = 'detached' and q.resolved_at > now() - make_interval(days => p_days)
 union all
 -- Вибірка для ручного аудиту: відкрити посилання й звірити.
 select * from (select 'аудит', w.change || ' ' || e.title || ' ' || to_char(w.from_starts_at, 'DD.MM HH24:MI')
  || case when w.change = 'moved' then ' → ' || to_char(w.to_starts_at, 'DD.MM HH24:MI') else '' end, 1::bigint, w.evidence->>'url'
  from w join public.events e on e.id = w.event_id order by w.at desc limit 30) a;
$$;

revoke all on function private.merge_url_twins(timestamptz), private.process_offer_detach_queue(timestamptz),
 private.record_offer_checks(jsonb), private.shadow_report(integer) from public, anon, authenticated;

-- Наявні: спершу двійники (злиття може перенести пропозицію з черги в іншу подію), потім черга — за 30 днів, щоб
-- результат не залежав від дня, коли міграцію застосують. Стан злитих подій перерахує наступна перевірка їхніх сторінок.
do $$ declare v_merged integer; v_detached integer; begin
 v_merged := private.merge_url_twins(now() - interval '30 days');
 v_detached := private.process_offer_detach_queue(now() - interval '30 days');
 raise notice 'offer_cleanup: злито %, від''єднано %, у черзі чекає %', v_merged, v_detached,
  (select count(*) from private.offer_detach_queue where resolution is null);
end $$;

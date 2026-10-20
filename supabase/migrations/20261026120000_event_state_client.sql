-- Стан події й продавці — клієнтам (docs/event-offers.md, фаза 4: R8, R10, R11). Лише додає поля: випущені збірки
-- (iOS 1.3.0) читають ті самі `canonical_url`, `source_name`, `import_status`, `price_min` з тими самими значеннями,
-- а невідомі ключі пропускають.
--
-- - `state`: `scheduled` / `cancelled` / `postponed` / `unknown` — лише для афіші (у спільнотних подій свій `status`).
--   Береться з `private.event_state` (фаза 2), коли його час збігається з рядком події. Тінь фази 2 ще не переносить
--   `events.starts_at`, тож стан з іншим часом про цей рядок нічого не каже: тоді, як і досі, вирішує
--   `import_status` (знята → `unknown`, «не знайшли в продажу»).
-- - `previous_starts_at`: лише в перенесеної (`scheduled`) події, стара дата для «~~пт 21.11~~ → нд 23.11».
-- - `checked_at`: коли адресна перевірка R5 востаннє читала сторінки продавців («Перевірено сьогодні о 09:00»).
-- - `offers`: продавці події, по одному на джерело — основний першим, далі живі за вагою. Знятих теж віддаємо: людина
--   з квитком скасованої події повертає його там, де купила. Вимкнене джерело (opt-out, §8) не показуємо.

alter type public.event_result
 add attribute state text,
 add attribute previous_starts_at timestamptz,
 add attribute checked_at timestamptz,
 add attribute offers jsonb;

create or replace function private.event_offers_json(p_event uuid, p_primary text)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('source', x.name, 'url', x.canonical_url,
   'price_min', x.price_min, 'is_free', x.is_free, 'live', x.status = 'live'))
   order by x.canonical_url is distinct from p_primary, x.status <> 'live', x.weight desc, x.name)
 from (
  select distinct on (o.source_id) o.canonical_url, o.price_min, o.is_free, o.status, s.name, s.weight
  from public.event_offers o join public.event_sources s on s.id = o.source_id
  where o.event_id = p_event and o.canonical_url is not null and s.enabled
  order by o.source_id, o.canonical_url is distinct from p_primary, o.status <> 'live', o.price_min nulls last
 ) x;
$$;

-- Стан для клієнта: див. шапку. Null — спільнотна подія.
create or replace function private.event_client_state(p_event uuid, p_origin text, p_starts timestamptz,
 p_import_status text, out state text, out previous_starts_at timestamptz, out checked_at timestamptz)
language sql stable set search_path='' as $$
 select
  case when p_origin = 'community' then null
       when s.event_id is not null and abs(extract(epoch from s.starts_at - p_starts)) < 60 then s.state
       when p_import_status = 'withdrawn' then 'unknown' else 'scheduled' end,
  case when p_origin <> 'community' and s.state = 'scheduled' and abs(extract(epoch from s.starts_at - p_starts)) < 60
        and abs(extract(epoch from s.previous_starts_at - p_starts)) >= 60 then s.previous_starts_at end,
  case when p_origin <> 'community' then s.checked_at end
 from (select 1) one left join private.event_state s on s.event_id = p_event;
$$;

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
 (select pe.title from public.events pe where pe.id=e.companion_of),
 cs.state, cs.previous_starts_at, cs.checked_at,
 case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end
 from public.events e
 left join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
 where e.id=any(p_ids) and private.has_event_access(e.id)
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$$;

create or replace function private.event_cards(p_ids uuid[])
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(card order by starts_at, id), '[]'::jsonb) from (
  select e.starts_at, e.id, jsonb_strip_nulls(jsonb_build_object(
    'id', e.id, 'title', e.title, 'description', nullif(e.description,''), 'category', e.category,
    'city', e.city, 'address', e.address,
    'place_id', e.place_id, 'place_name', pl.name,
    'starts_at', e.starts_at, 'ends_at', e.ends_at, 'time_zone', e.time_zone, 'status', e.status,
    'latitude', e.latitude, 'longitude', e.longitude, 'image_url', e.image_url,
    'organizer_id', e.organizer_id, 'organizer_name', coalesce(p.display_name, s.name),
    'capacity', e.capacity,
    'attendee_count', case when e.origin='community' then
      (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved') end,
    'joined', case when e.origin='community' and auth.uid() is not null then
      exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved') end,
    'membership', case when e.origin='community' and auth.uid() is not null then
      (select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()) end,
    'min_age', nullif(e.min_age, private.min_signup_age()), 'max_age', e.max_age,
    'approval_required', case when e.approval_required then true end,
    'origin', e.origin, 'source_name', s.name, 'canonical_url', e.canonical_url,
    'import_status', e.import_status, 'price_min', e.price_min, 'is_free', e.is_free,
    'state', cs.state, 'previous_starts_at', cs.previous_starts_at, 'checked_at', cs.checked_at,
    'offers', case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end,
    'artists', (select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'kind', a.kind, 'role', ea.role)
                                 order by ea.position, a.name)
                from public.event_artists ea join public.artists a on a.id = ea.artist_id
                where ea.event_id = e.id))) as card
  from public.events e
  left join public.profiles p on p.id = e.organizer_id
  left join public.event_sources s on s.id = e.source_id
  left join public.places pl on pl.id = e.place_id
  cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
  where e.id = any(p_ids) and private.has_event_access(e.id)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
 ) t;
$$;

revoke all on function private.event_offers_json(uuid, text) from public, anon, authenticated;
revoke all on function private.event_client_state(uuid, text, timestamptz, text) from public, anon, authenticated;

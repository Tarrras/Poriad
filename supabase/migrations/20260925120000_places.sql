-- Місця: один рядок на фізичну точку. Досі місце існувало лише як пара координат, за якою
-- MapPins на клієнті групує піни й «Що тут»; `public.venues` — це кеш геокодера з ключем
-- (назва, адреса), де один заклад лежить кількома рядками (664 рядки на 323 точки). Тут
-- канонічна назва, посилання з подій і пошук за назвою. `venues` не чіпаємо: у нього своя робота.

create table public.places (
 id uuid primary key default gen_random_uuid(),
 name text not null check (length(name) between 1 and 200),
 city text not null,
 address text,
 latitude double precision not null check (latitude between -90 and 90),
 longitude double precision not null check (longitude between -180 and 180),
 location gis.geography(Point,4326) generated always as
  (gis.st_setsrid(gis.st_makepoint(longitude,latitude),4326)::gis.geography) stored,
 -- Звідки назва: 'manual' (aliases.json) > 'osm' > 'photon'/'source' (назва з афіші). Дамп
 -- перетирає назву лише щаблем не нижчим за поточний: ручна вивірка не губиться.
 source text not null default 'source' check (source in ('manual','osm','photon','source')),
 osm_ref text,
 search tsvector generated always as
  (to_tsvector('simple', name || ' ' || coalesce(address,''))) stored,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 -- Точка = місце: той самий ключ, що в MapPins.placeOf на клієнті.
 unique (latitude, longitude)
);
create index places_search_idx on public.places using gin (search);
create index places_location_idx on public.places using gist ((location::gis.geometry));
create index places_city_idx on public.places (city);

alter table public.places enable row level security;
create policy places_read on public.places for select to anon, authenticated using (true);
grant select on public.places to anon, authenticated;

alter table public.events add column place_id uuid references public.places(id) on delete set null;
create index events_place_idx on public.events (place_id) where status = 'published';

-- Ранг джерела назви. Використовується і тут, і в дампі (`tools/ingest/emit.py`).
create or replace function private.place_source_rank(p_source text) returns integer
language sql immutable set search_path='' as $$
 select case p_source when 'manual' then 3 when 'osm' then 2 else 1 end;
$$;

-- ---- Наповнення з того, що вже є: живі імпортовані події + найкраща назва з кешу геокодера.
with points as (
 select distinct e.latitude, e.longitude, e.city, e.address
 from public.events e
 where e.origin='import' and e.status='published' and e.import_status='live' and e.ends_at > now()
), best as (
 select distinct on (p.latitude, p.longitude) p.latitude, p.longitude, p.city, p.address,
  coalesce(v.display_name, split_part(p.address, ',', 1)) as name,
  coalesce(v.source, 'source') as source, v.osm_ref
 from points p
 left join public.venues v on v.latitude = p.latitude and v.longitude = p.longitude
 order by p.latitude, p.longitude, private.place_source_rank(coalesce(v.source,'source')) desc, v.confidence desc nulls last
)
insert into public.places (name, city, address, latitude, longitude, source, osm_ref)
select left(name, 200), city, address, latitude, longitude, source, osm_ref from best
where name <> ''
on conflict (latitude, longitude) do nothing;

update public.events e set place_id = p.id
from public.places p
where e.place_id is null and e.origin='import' and e.latitude = p.latitude and e.longitude = p.longitude;

-- ---- Пошук місць: за назвою чи адресою, лише ті, де є майбутні видимі події.
-- Рамка необовʼязкова: без неї — усе місто, з нею — те, що на екрані.
create or replace function public.search_places(
 p_text text, p_city text default null,
 p_south double precision default null, p_west double precision default null,
 p_north double precision default null, p_east double precision default null,
 p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text := nullif(btrim(p_text), ''); v_limit integer;
begin
 if q is null then return '[]'::jsonb; end if;
 if length(q) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
 return coalesce((
  select jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', p.name, 'city', p.city, 'address', p.address,
    'latitude', p.latitude, 'longitude', p.longitude, 'upcoming', p.upcoming)
   order by p.upcoming desc, p.name)
  from (
   select pl.*, (
     select count(*)::integer from public.events e
     where e.place_id = pl.id and e.status='published' and e.ends_at > now()
       and private.is_discoverable(e.origin, e.import_status, e.quality)) as upcoming
   from public.places pl
   where (p_city is null or pl.city = p_city)
     and (p_south is null or p_north is null or p_west is null or p_east is null
          or pl.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
     -- Префікс слова через tsquery і підрядок через ilike: «малев» знаходить «Малевич», «feels» — «ВДНГ Feels».
     and (pl.search @@ (websearch_to_tsquery('simple', q)::text || ':*')::tsquery
          or pl.name ilike '%' || q || '%')
   ) p
  where p.upcoming > 0
  limit v_limit), '[]'::jsonb);
end $$;
revoke all on function public.search_places(text,text,double precision,double precision,double precision,double precision,integer) from public,anon,authenticated;
grant execute on function public.search_places(text,text,double precision,double precision,double precision,double precision,integer) to anon,authenticated;

-- ---- «Що тут» з сервера: майбутні події місця, картками, незалежно від зуму мапи.
-- definer, як discover_index: у anon немає прямого select на events, доступ фільтрує event_cards.
create or replace function public.place_events(p_place_id uuid, p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ids uuid[];
begin
 if p_place_id is null then return '[]'::jsonb; end if;
 select array_agg(e.id order by greatest(e.starts_at, now()), e.id) into ids
 from (
  select e.id, e.starts_at from public.events e
  where e.place_id = p_place_id and e.status='published' and e.ends_at > now()
    and private.is_discoverable(e.origin, e.import_status, e.quality)
  order by greatest(e.starts_at, now()), e.id
  limit least(greatest(coalesce(p_limit,100),1),100)) e;
 return private.event_cards(coalesce(ids, '{}'::uuid[]));
end $$;
revoke all on function public.place_events(uuid,integer) from public,anon,authenticated;
grant execute on function public.place_events(uuid,integer) to anon,authenticated;

-- ---- Картка події знає своє місце: клієнт відкриває «Що тут» за place_id, не за координатою.
-- Тіло — з 20260911070031, плюс два поля.
create or replace function private.event_cards(p_ids uuid[]) returns jsonb
language sql stable security definer set search_path='' as $$
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
    'import_status', e.import_status, 'price_min', e.price_min, 'is_free', e.is_free)) as card
  from public.events e
  left join public.profiles p on p.id = e.organizer_id
  left join public.event_sources s on s.id = e.source_id
  left join public.places pl on pl.id = e.place_id
  where e.id = any(p_ids) and private.has_event_access(e.id)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
 ) t;
$$;

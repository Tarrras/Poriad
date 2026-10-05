-- Сеанс, що вже йде, не пропонуємо: на стендап, який почався годину тому, ніхто не встигне. Прокат (виставка,
-- ярмарок, фестиваль — понад добу) лишається до кінця, туди йдуть і посеред. Межа — тривалість, як `Event.isMultiDay`:
-- серед подій на 4–24 години вистави з вигаданим кінцем, тож нижча межа знову впустила б театр.
-- Ціна: одноденний ярмарок (10:00–18:00) зникає з видачі, щойно відкрився.
--
-- Лише там, де людина шукає нове: мапа й пошук, заклад, артист, підписки (стрічка й пуші через `followed_events`).
-- Свої плани, деталі, чат, рейтинги й блокування лишаються на `ends_at > now()`.
-- Тіла — з живої бази (20260911120000, 20260925120000, 20261002120000, 20261003120000); змінено лише умову часу.

create function private.is_listed(p_starts timestamptz, p_ends timestamptz)
returns boolean language sql stable set search_path='' as $$
 -- Дзеркало `Event.isListed` (core/domain).
 select p_ends > now() and (p_starts > now() or p_ends - p_starts > interval '24 hours');
$$;

-- ---- Мапа, пошук, «У місті».
create or replace function private.discover_index(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text, p_from timestamptz, p_to timestamptz, p_text text, p_available boolean,
 p_limit integer, p_cards integer)
returns table(index jsonb, total integer, truncated boolean, card_ids uuid[])
language sql stable security definer set search_path='' as $$
 with matched as (
  select e.id, e.starts_at, e.latitude, e.longitude, e.category, e.time_zone, e.title,
         e.origin, e.capacity, e.source_id
  from public.events e
  where e.status='published' and private.is_listed(e.starts_at, e.ends_at)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
    and (nullif(btrim(p_text),'') is null
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), lower(btrim(p_text))) > 0)
    -- `case` замість `and`: порядок обчислення кон'юнкції не гарантований.
    and (not coalesce(p_available,false)
         or case when e.capacity is null then false else private.event_has_space(e.id) end)
    and (p_category is null or e.category = p_category)
    and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
    and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
      or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
       or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326)))))
 , ranked as (
  select m.*, row_number() over (order by greatest(m.starts_at, now()), m.id) as rank,
         count(*) over () as total
  from matched m
 )
 , page as (select r.* from ranked r where r.rank <= p_limit)
 select
  coalesce((select jsonb_agg(jsonb_build_array(
     p.id, p.latitude, p.longitude, p.category, p.starts_at, p.time_zone, p.title, p.origin,
     s.slug,
     p.capacity,
     case when p.origin='community' then
       (select count(*)::integer from public.event_members mm where mm.event_id=p.id and mm.status='approved')
     else 0 end
   ) order by p.rank) from page p left join public.event_sources s on s.id=p.source_id), '[]'::jsonb),
  coalesce((select max(r.total)::integer from ranked r), 0),
  coalesce((select max(r.total) from ranked r), 0) > p_limit,
  coalesce((select array_agg(p.id order by p.rank) from page p where p.rank <= p_cards), '{}'::uuid[]);
$$;

-- ---- Запасний шлях для старих збірок.
create or replace function public.search_events_in_view(p_south double precision,p_west double precision,p_north double precision,p_east double precision,p_category text default null,p_from timestamptz default null,p_to timestamptz default null,p_text text default null,p_available boolean default false)
 returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text)>120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and private.is_listed(e.starts_at, e.ends_at)
 and private.is_discoverable(e.origin,e.import_status,e.quality)
 and (nullif(btrim(p_text),'') is null or strpos(lower(concat_ws(' ',e.title,e.description,e.city,e.address)),lower(btrim(p_text)))>0)
 and (not coalesce(p_available,false) or case when e.capacity is null then false else private.event_has_space(e.id) end)
 and (p_category is null or e.category=p_category)
 and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
 and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
 or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
 or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326))))
 order by greatest(e.starts_at,now()),e.id limit 300)) r order by greatest(r.starts_at,now()),r.id;
end $$;

-- ---- Заклад: афіша й лічильник у пошуку (рахують те саме, що показують).
create or replace function public.place_events(p_place_id uuid, p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ids uuid[];
begin
 if p_place_id is null then return '[]'::jsonb; end if;
 select array_agg(e.id order by greatest(e.starts_at, now()), e.id) into ids
 from (
  select e.id, e.starts_at from public.events e
  where e.place_id = p_place_id and e.status='published' and private.is_listed(e.starts_at, e.ends_at)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
  order by greatest(e.starts_at, now()), e.id
  limit least(greatest(coalesce(p_limit,100),1),100)) e;
 return private.event_cards(coalesce(ids, '{}'::uuid[]));
end $$;

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
     where e.place_id = pl.id and e.status='published' and private.is_listed(e.starts_at, e.ends_at)
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

-- ---- Артист: афіша й лічильник у пошуку.
create or replace function public.artist_events(p_artist_id uuid, p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ids uuid[];
begin
 if p_artist_id is null then return '[]'::jsonb; end if;
 select array_agg(x.id order by greatest(x.starts_at, now()), x.id) into ids from (
  select e.id, e.starts_at
  from public.event_artists ea join public.events e on e.id = ea.event_id
  where ea.artist_id = p_artist_id and e.status='published' and private.is_listed(e.starts_at, e.ends_at)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
  order by greatest(e.starts_at, now()), e.id
  limit least(greatest(coalesce(p_limit, 100), 1), 100)) x;
 return private.event_cards(coalesce(ids, '{}'::uuid[]));
end $$;

create or replace function public.search_artists(p_text text, p_city text default null, p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text := nullif(btrim(p_text), ''); v_limit integer;
begin
 if q is null then return '[]'::jsonb; end if;
 if length(q) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
 return coalesce((
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', t.id, 'name', t.name, 'kind', t.kind, 'upcoming', t.upcoming)) order by t.upcoming desc, t.name)
  from (
   select a.id, a.name, a.kind, u.upcoming
   from public.artists a
   cross join lateral (
    select count(distinct lower(btrim(e.title)))::integer as upcoming
    from public.event_artists ea join public.events e on e.id = ea.event_id
    where ea.artist_id = a.id and e.status='published' and private.is_listed(e.starts_at, e.ends_at)
      and (p_city is null or e.city = p_city)
      and private.is_discoverable(e.origin, e.import_status, e.quality)) u
   where (a.search @@ (websearch_to_tsquery('simple', q)::text || ':*')::tsquery
          or a.name ilike '%' || q || '%')
     and u.upcoming > 0
   order by u.upcoming desc, a.name
   limit v_limit) t), '[]'::jsonb);
end $$;

-- ---- Підписки: стрічка на головній і обидва пуші читають цей вигляд.
create or replace view private.followed_events as
 select f.user_id, f.target_kind, f.target_id, f.created_at as followed_at,
  e.id as event_id, e.title, e.created_at as event_created_at, e.starts_at, e.place_id
 from public.follows f
 join public.events e on e.place_id = f.target_id
 where f.target_kind = 'place' and e.origin = 'import' and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at)
  and private.is_discoverable(e.origin, e.import_status, e.quality)
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at,
  e.id, e.title, e.created_at, e.starts_at, null::uuid
 from public.follows f
 join public.events e on e.organizer_id = f.target_id
 where f.target_kind = 'organizer' and e.origin = 'community' and e.companion_of is null
  and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at)
  and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id)
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at,
  e.id, e.title, e.created_at, e.starts_at, e.place_id
 from public.follows f
 join public.event_artists ea on ea.artist_id = f.target_id
 join public.events e on e.id = ea.event_id
 where f.target_kind = 'artist' and e.origin = 'import' and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at)
  and private.is_discoverable(e.origin, e.import_status, e.quality);

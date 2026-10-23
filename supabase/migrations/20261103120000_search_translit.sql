-- Пошук знаходить латинську назву за кириличним запитом і навпаки. Було (dev 24.10): «Атлас» на мапі — 0 подій
-- і жодного закладу, хоча в адресі восьми подій «ATLAS, Київ», а заклад зветься «Atlas»; «atlas» знаходив усе.
-- Тепер до запиту додається другий варіант — той самий запит іншою абеткою, і збіг рахується за будь-яким.
-- Розширень не треба (unaccent і pg_trgm не стоять): replace для кількох літер, translate для решти.
-- Тіла — з 20261006130000 (discover_index, search_events_in_view) і 20261008120000 (search_places,
-- search_artists); змінено лише умову збігу.

-- ponytail: одна таблиця на кшталт КМУ-2010, без правил початку слова (є/ю/я/ї/й) і без англійського
-- читання («Хаб» не знайде «Hub», «jazz» — «джаз»). Мало — тоді кілька варіантів або pg_trgm.
-- Порожній варіант (запит «ь») — null: інакше strpos і ilike '%%' збіглися б з усім.
create function private.search_translit(p_text text) returns text
language sql immutable set search_path='' as $$
 select nullif(case when s ~ '[а-яёіїєґ]' then
  translate(replace(replace(replace(replace(replace(replace(replace(replace(replace(s,
    'щ','shch'),'ж','zh'),'х','kh'),'ц','ts'),'ч','ch'),'ш','sh'),'є','ie'),'ю','iu'),'я','ia'),
   'абвгґдезиіїйклмнопрстуфыэёьъ''’ʼ', 'abvhgdezyiiiklmnoprstufyee')
 else
  translate(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(s,
    'shch','щ'),'zh','ж'),'kh','х'),'ts','ц'),'ch','ч'),'sh','ш'),'ck','k'),'ya','я'),'yu','ю'),'ye','є'),'yi','ий'),
    'j','дж'),'x','кс'),
   'abcdefghiklmnopqrstuvwyz', 'абкдефггіклмнопкрстуввиз')
 end, '')
 from (select lower(btrim(p_text)) as s) x;
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
  where e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
    -- Варіант у підзапиті: рахується раз на виклик, а не на кожен рядок.
    and (nullif(btrim(p_text),'') is null
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), lower(btrim(p_text))) > 0
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), (select private.search_translit(p_text))) > 0)
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
declare q2 text := private.search_translit(p_text);
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text)>120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
 and private.is_discoverable(e.origin,e.import_status,e.quality)
 and (nullif(btrim(p_text),'') is null or strpos(lower(concat_ws(' ',e.title,e.description,e.city,e.address)),lower(btrim(p_text)))>0
  or strpos(lower(concat_ws(' ',e.title,e.description,e.city,e.address)),q2)>0)
 and (not coalesce(p_available,false) or case when e.capacity is null then false else private.event_has_space(e.id) end)
 and (p_category is null or e.category=p_category)
 and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
 and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
 or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
 or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326))))
 order by greatest(e.starts_at,now()),e.id limit 300)) r order by greatest(r.starts_at,now()),r.id;
end $$;

-- ---- Заклади й артисти: другий варіант — лише підрядком імені («Атлас» → «Клуб ATLAS», «Atlas»).
create or replace function public.search_artists(p_text text, p_city text default null, p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text := nullif(btrim(p_text), ''); q2 text := private.search_translit(p_text); v_limit integer;
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
    select count(distinct (lower(btrim(e.title)), coalesce(e.place_id::text, e.city)))::integer as upcoming,
           count(*) filter (where p_city is null or e.city = p_city) as in_city
    from public.event_artists ea join public.events e on e.id = ea.event_id
    where ea.artist_id = a.id and e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
      and private.is_discoverable(e.origin, e.import_status, e.quality)) u
   where (a.search @@ (websearch_to_tsquery('simple', q)::text || ':*')::tsquery
          or a.name ilike '%' || q || '%' or a.name ilike '%' || q2 || '%')
     and u.upcoming > 0 and u.in_city > 0
   order by u.upcoming desc, a.name
   limit v_limit) t), '[]'::jsonb);
end $$;

create or replace function public.search_places(p_text text, p_city text default null,
  p_south double precision default null, p_west double precision default null,
  p_north double precision default null, p_east double precision default null, p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text := nullif(btrim(p_text), ''); q2 text := private.search_translit(p_text); v_limit integer;
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
     select count(distinct lower(btrim(e.title)))::integer from public.events e
     where e.place_id = pl.id and e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
       and private.is_discoverable(e.origin, e.import_status, e.quality)) as upcoming
   from public.places pl
   where (p_city is null or pl.city = p_city)
     and (p_south is null or p_north is null or p_west is null or p_east is null
          or pl.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
     -- Префікс слова через tsquery і підрядок через ilike: «малев» знаходить «Малевич», «feels» — «ВДНГ Feels».
     and (pl.search @@ (websearch_to_tsquery('simple', q)::text || ':*')::tsquery
          or pl.name ilike '%' || q || '%' or pl.name ilike '%' || q2 || '%')
   ) p
  where p.upcoming > 0
  limit v_limit), '[]'::jsonb);
end $$;

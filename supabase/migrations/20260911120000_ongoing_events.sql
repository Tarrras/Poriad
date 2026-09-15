-- Події, що вже йдуть: виставки й фестивалі відсікались за часом початку. Умова переходить на
-- `ends_at`, але спершу знімаємо з публікації постійні пропозиції з вигаданим кінцем; далі межу
-- прокату тримає `tools/ingest/pipeline.py` (`PERMANENT_RUN`).
-- Не чіпаємо: `p_from`/`p_to` лишаються на `starts_at` («на вихідних» — про те, що почнеться);
-- `public.events_in_view` теж, її ніхто не викликає.

-- ---- 1. Постійні пропозиції (океанаріум, музей медуз) з `endDate` через 560 днів висіли б як
-- «триває зараз» місяцями. `withdrawn`, а не `delete`: збережений запис лишається. Межа 90 днів, як у pipeline.py.
update public.events set import_status='withdrawn', updated_at=now()
where origin='import' and import_status='live' and ends_at - starts_at > interval '90 days';

-- ---- 2. Умова й порядок в індексі. `ends_at > now()` впускає прокати, а `order by
-- greatest(starts_at, now())` не дає найдовшому прокату вічно стояти першим: усе, що вже йде,
-- згортається в точку «зараз». Решта тіла — з 20260911070031, сигнатура та сама.
create or replace function private.discover_index(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text, p_from timestamptz, p_to timestamptz, p_text text, p_available boolean,
 p_limit integer, p_cards integer)
returns table(index jsonb, total integer, truncated boolean, card_ids uuid[])
-- Без `plan_cache_mode='force_custom_plan'`, як у 20260911070031.
language sql stable security definer set search_path='' as $$
 with matched as (
  select e.id, e.starts_at, e.latitude, e.longitude, e.category, e.time_zone, e.title,
         e.origin, e.capacity, e.source_id
  from public.events e
  where e.status='published' and e.ends_at > now()
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

-- ---- 3. Те саме в запасному шляху для старих збірок. Порядок у двох місцях: у підзапиті з
-- `limit 300` і в зовнішньому `order by`.
create or replace function public.search_events_in_view(p_south double precision,p_west double precision,p_north double precision,p_east double precision,p_category text default null,p_from timestamptz default null,p_to timestamptz default null,p_text text default null,p_available boolean default false)
 returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text)>120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and e.ends_at > now()
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

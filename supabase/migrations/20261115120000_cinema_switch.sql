-- Вимикач кіно без нової збірки (docs/cinema-import.md, «Вимикач»). Кіно видно, лише коли ввімкнено прапорець
-- `cinema` (private.flags) і мережа-джерело не вимкнена (`event_sources.enabled`). За замовчуванням прапорець вимкнено:
-- після накочування на prod кіно не з'являється, доки власник його не ввімкне, — скажімо, коли мережі відповіли на листи.
--
--   update private.flags set enabled = true, changed_at = now() where name = 'cinema';      -- кіно всім
--   update public.event_sources set enabled = false where slug = 'planeta_kino';             -- без однієї мережі
--
-- Вимкнена мережа зникає одразу (видача, «Що тут», пошук місць, підписки на заклад), а обхід її пропозицій більше не
-- пише (private.ingest_offers). Збережені й квитки лишаються: event_cards_by_ids відкриває свій план завжди.
-- «Що тут» і пошук місць дістали `p_cinema`, як видача (20261112120000): збірки 1.3.x кіно там теж не бачать.

insert into private.flags (name) values ('cinema') on conflict (name) do nothing;

create function private.cinema_shown(p_source uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.flag('cinema') and exists (select 1 from public.event_sources s where s.id = p_source and s.enabled);
$$;
revoke all on function private.cinema_shown(uuid) from public, anon, authenticated;

-- ───────────────────────────────────────────── видача

-- Тіло — з 20261113120000_artist_radar, змінено лише умову кіно.
create or replace function private.discover_index(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text, p_from timestamptz, p_to timestamptz, p_text text, p_available boolean,
 p_limit integer, p_cards integer, p_cinema boolean)
returns table(index jsonb, total integer, truncated boolean, card_ids uuid[])
language sql stable security definer set search_path='' as $$
 with matched as (
  select e.id, e.starts_at, e.latitude, e.longitude, e.category, e.time_zone, e.title,
         e.origin, e.capacity, e.source_id, e.place_id
  from public.events e
  where e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
    and (e.category <> 'cinema' or (coalesce(p_cinema,false) and private.cinema_shown(e.source_id)))
    -- Варіант у підзапиті: рахується раз на виклик, а не на кожен рядок.
    and (nullif(btrim(p_text),'') is null
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), lower(btrim(p_text))) > 0
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), (select private.search_translit(p_text))) > 0)
    -- `case` замість `and`: порядок обчислення кон'юнкції не гарантований.
    and (not coalesce(p_available,false)
         or case when e.capacity is null then exists (select 1 from private.company_intents ci where ci.event_id = e.id)
                 else private.event_has_space(e.id) end)
    and (p_category is null or e.category = p_category)
    and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
    and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
      or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
       or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326)))))
 , runs as (
  select m.*,
         case when m.category = 'cinema' then row_number() over w end as nth,
         case when m.category = 'cinema' then
           jsonb_agg(jsonb_build_array(m.id, m.starts_at)) over (w rows between unbounded preceding and unbounded following)
         end as sessions
  from matched m
  -- Без місця кіносеанс — сам собі прокат: інакше злиплись би всі сеанси фільму без точки.
  window w as (partition by m.category = 'cinema', coalesce(m.place_id::text, m.id::text), lower(btrim(m.title))
               order by m.starts_at, m.id)
 )
 , ranked as (
  select r.*, row_number() over (order by r.category = 'cinema', greatest(r.starts_at, now()), r.id) as rank,
         count(*) over () as total
  from runs r where r.nth is null or r.nth = 1
 )
 , page as (select r.* from ranked r where r.rank <= p_limit)
 select
  coalesce((select jsonb_agg(jsonb_build_array(
     p.id, p.latitude, p.longitude, p.category, p.starts_at, p.time_zone, p.title, p.origin,
     s.slug,
     p.capacity,
     case when p.origin='community' then
       (select count(*)::integer from public.event_members mm where mm.event_id=p.id and mm.status='approved')
     else 0 end,
     -- ponytail: рахуємо всіх, без блоків і неактивних — точне число дає `company_teaser` на деталях.
     case when p.origin='import' then
       (select count(*)::integer from private.company_intents ci where ci.event_id=p.id)
     else 0 end,
     case when p.category='cinema' then pl.name end,
     p.sessions
   ) order by p.rank) from page p left join public.event_sources s on s.id=p.source_id
     left join public.places pl on pl.id=p.place_id), '[]'::jsonb),
  coalesce((select max(r.total)::integer from ranked r), 0),
  coalesce((select max(r.total) from ranked r), 0) > p_limit,
  coalesce((select array_agg(p.id order by p.rank) from page p where p.rank <= p_cards), '{}'::uuid[]);
$$;

-- ───────────────────────────────────────────── «Що тут»

-- Тіло — з 20261006130000_drop_in_fairs; `p_cinema` і умова кіно. Нова сигнатура — стару видаляємо: дві перевантажені з
-- типовими значеннями PostgREST не розрізнить.
drop function public.place_events(uuid, integer);
create function public.place_events(p_place_id uuid, p_limit integer default 100, p_cinema boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ids uuid[];
begin
 if p_place_id is null then return '[]'::jsonb; end if;
 select array_agg(e.id order by greatest(e.starts_at, now()), e.id) into ids
 from (
  select e.id, e.starts_at from public.events e
  where e.place_id = p_place_id and e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
    and (e.category <> 'cinema' or (coalesce(p_cinema,false) and private.cinema_shown(e.source_id)))
  order by greatest(e.starts_at, now()), e.id
  limit least(greatest(coalesce(p_limit,100),1),100)) e;
 return private.event_cards(coalesce(ids, '{}'::uuid[]));
end $$;
revoke all on function public.place_events(uuid, integer, boolean) from public, anon, authenticated;
grant execute on function public.place_events(uuid, integer, boolean) to anon, authenticated;

-- ───────────────────────────────────────────── пошук місць

-- Тіло — з 20261103120000_search_translit; `p_cinema` і умова кіно в лічильнику: кінотеатр без видимого кіно — місце
-- без подій, і пошук його не показує.
drop function public.search_places(text, text, double precision, double precision, double precision, double precision, integer);
create function public.search_places(p_text text, p_city text default null,
  p_south double precision default null, p_west double precision default null,
  p_north double precision default null, p_east double precision default null, p_limit integer default 20,
  p_cinema boolean default false)
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
       and private.is_discoverable(e.origin, e.import_status, e.quality)
       and (e.category <> 'cinema' or (coalesce(p_cinema,false) and private.cinema_shown(e.source_id)))) as upcoming
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
revoke all on function public.search_places(text, text, double precision, double precision, double precision, double precision, integer, boolean) from public, anon, authenticated;
grant execute on function public.search_places(text, text, double precision, double precision, double precision, double precision, integer, boolean) to anon, authenticated;

-- ───────────────────────────────────────────── підписки на заклад

-- Тіло — з 20261006130000_drop_in_fairs; у гілці закладу — умова кіно: вимкнене кіно не приходить ні в «Ви стежите», ні
-- пушем про нове в закладі.
create or replace view private.followed_events as
 select f.user_id, f.target_kind, f.target_id, f.created_at as followed_at,
  e.id as event_id, e.title, e.created_at as event_created_at, e.starts_at, e.place_id
 from public.follows f
 join public.events e on e.place_id = f.target_id
 where f.target_kind = 'place' and e.origin = 'import' and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.is_discoverable(e.origin, e.import_status, e.quality)
  and (e.category <> 'cinema' or private.cinema_shown(e.source_id))
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at,
  e.id, e.title, e.created_at, e.starts_at, null::uuid
 from public.follows f
 join public.events e on e.organizer_id = f.target_id
 where f.target_kind = 'organizer' and e.origin = 'community' and e.companion_of is null
  and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id)
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at,
  e.id, e.title, e.created_at, e.starts_at, e.place_id
 from public.follows f
 join public.event_artists ea on ea.artist_id = f.target_id
 join public.events e on e.id = ea.event_id
 where f.target_kind = 'artist' and e.origin = 'import' and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.is_discoverable(e.origin, e.import_status, e.quality);

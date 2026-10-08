-- Лічильники подій рахують прокат так само, як клієнт його показує: одна картка — назва в одному місці.
--
-- Було (аудит 2026-10-08): пошук артистів, «Підписки» й пуш рахували різні назви по всіх містах — тур МУР
-- «Грай, [Марку]» (Київ ×3, Дніпро ×2, Львів ×2, Одеса) був «1 подією», а екран артиста показував чотири
-- картки (`EventSeries.fold`: місце + назва). Стрічка «Ваше» лишала з туру лише найближче місто, а пуш
-- рахував три нові міста однією подією. Пошук місць рахував сеанси, «Підписки» — назви (у 86 зі 250 місць
-- числа різнились). `search_artists(p_city)` рахував лише місто пошуку, а екран артиста показує всі міста.
--
-- Тепер: артист — пари (назва, місце) по всіх містах; місто пошуку лише вирішує, чи показати артиста.
-- Місце — різні назви (місце одне). Назва — `lower(btrim(title))`, як і раніше.

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
    select count(distinct (lower(btrim(e.title)), coalesce(e.place_id::text, e.city)))::integer as upcoming,
           count(*) filter (where p_city is null or e.city = p_city) as in_city
    from public.event_artists ea join public.events e on e.id = ea.event_id
    where ea.artist_id = a.id and e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
      and private.is_discoverable(e.origin, e.import_status, e.quality)) u
   where (a.search @@ (websearch_to_tsquery('simple', q)::text || ':*')::tsquery
          or a.name ilike '%' || q || '%')
     and u.upcoming > 0 and u.in_city > 0
   order by u.upcoming desc, a.name
   limit v_limit) t), '[]'::jsonb);
end $$;

create or replace function public.search_places(p_text text, p_city text default null,
  p_south double precision default null, p_west double precision default null,
  p_north double precision default null, p_east double precision default null, p_limit integer default 20)
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
     select count(distinct lower(btrim(e.title)))::integer from public.events e
     where e.place_id = pl.id and e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
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

create or replace function private.my_follows()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(t.item order by t.since desc, t.name), '[]'::jsonb) from (
  select f.created_at as since, p.name,
   jsonb_strip_nulls(jsonb_build_object('kind','place','id',p.id,'name',p.name,'city',p.city,'address',p.address,
    'latitude',p.latitude,'longitude',p.longitude,'since',f.created_at,
    'upcoming',(select count(distinct lower(btrim(v.title)))::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'place' and v.target_id = p.id))) as item
  from public.follows f join public.places p on p.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'place'
  union all
  select f.created_at, pr.display_name,
   jsonb_strip_nulls(jsonb_build_object('kind','organizer','id',pr.id,'name',pr.display_name,'avatar_url',pr.avatar_url,
    'since',f.created_at,
    'upcoming',(select count(*)::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'organizer' and v.target_id = pr.id)))
  from public.follows f join public.profiles pr on pr.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'organizer'
   and private.account_active(pr.id) and not private.blocked_between(f.user_id, pr.id)
  union all
  select f.created_at, a.name,
   jsonb_strip_nulls(jsonb_build_object('kind','artist','id',a.id,'name',a.name,'artist_kind',a.kind,
    'since',f.created_at,
    'upcoming',(select count(distinct (lower(btrim(v.title)), coalesce(v.place_id::text, '')))::integer
                from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'artist' and v.target_id = a.id)))
  from public.follows f join public.artists a on a.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'artist'
 ) t;
$$;

create or replace function private.follow_events(p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_ids uuid[];
begin
 if auth.uid() is null then return '[]'::jsonb; end if;
 select array_agg(x.event_id order by x.sort_at, x.event_id) into v_ids from (
  select r.event_id, greatest(r.starts_at, now()) as sort_at from (
   -- Прокат — одна картка: місце + назва. Для артиста місце в ключі: тур показує кожне місто, а не лише найближче.
   select distinct on (v.target_kind, v.target_id, case
      when v.target_kind = 'place' then lower(btrim(v.title))
      when v.target_kind = 'artist' then lower(btrim(v.title)) || '|' || coalesce(v.place_id::text, '')
      else v.event_id::text end)
    v.event_id, v.starts_at
   from private.followed_events v where v.user_id = auth.uid()
   order by v.target_kind, v.target_id, case
      when v.target_kind = 'place' then lower(btrim(v.title))
      when v.target_kind = 'artist' then lower(btrim(v.title)) || '|' || coalesce(v.place_id::text, '')
      else v.event_id::text end,
    v.starts_at, v.event_id) r
  order by greatest(r.starts_at, now()), r.event_id
  limit least(greatest(coalesce(p_limit, 20), 1), 50)) x;
 return private.event_cards(coalesce(v_ids, '{}'::uuid[]));
end $$;

create or replace function private.notify_artist_follows()
returns integer language plpgsql security definer set search_path='' as $$
declare v_row record; v_sent integer := 0;
begin
 if (select e.url from private.push_endpoint() e) is null then return 0; end if;
 -- Той самий замок, що в notify_place_follows: обидва читають і пишуть одну таблицю ліміту.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('notify_place_follows', 0));
 for v_row in
  with due as (
   -- Прокат — назва в одному місці: нові міста туру — окремі події, а не одна.
   select v.user_id, v.target_id as artist_id, v.event_id, v.starts_at,
          lower(btrim(v.title)) || '|' || coalesce(v.place_id::text, '') as run
   from private.followed_events v
   left join private.follow_pushes p on p.user_id = v.user_id
   where v.target_kind = 'artist' and v.event_created_at > v.followed_at
    and (p.sent_at is null or p.sent_at <= now() - interval '24 hours')
    and not exists (select 1 from private.follow_announced a where a.user_id = v.user_id and a.event_id = v.event_id)
    and exists (select 1 from public.push_tokens t where t.user_id = v.user_id)
  ), runs as (
   -- Прокат із кількох сеансів одного артиста — одна подія.
   select distinct on (d.user_id, d.artist_id, d.run) d.user_id, d.artist_id, d.event_id, d.starts_at, d.run
   from due d order by d.user_id, d.artist_id, d.run, d.starts_at, d.event_id
  ), by_artist as (
   select u.user_id, u.artist_id, count(*)::integer as n, min(u.starts_at) as first_at
   from runs u group by u.user_id, u.artist_id
  ), shows as (
   -- Подія з двома артистами, за якими стежать, одна: рахуємо за прокатом, не за парою.
   select distinct on (r.user_id, r.run) r.user_id, r.event_id, r.starts_at
   from runs r order by r.user_id, r.run, r.starts_at, r.event_id
  )
  select g.user_id, count(*)::integer as total,
   (select count(*)::integer from by_artist b where b.user_id = g.user_id) as artist_count,
   (select jsonb_agg(jsonb_build_object('id', x.artist_id, 'n', x.n) order by x.n desc, x.first_at, x.artist_id)
    from (select b.* from by_artist b where b.user_id = g.user_id order by b.n desc, b.first_at, b.artist_id limit 5) x) as artists,
   (select jsonb_agg(y.event_id order by y.starts_at, y.event_id)
    from (select s.* from shows s where s.user_id = g.user_id order by s.starts_at, s.event_id limit 3) y) as event_ids,
   (select array_agg(d.event_id) from due d where d.user_id = g.user_id) as seen
  from shows g group by g.user_id
 loop
  insert into private.follow_pushes (user_id, sent_at) values (v_row.user_id, now())
   on conflict (user_id) do update set sent_at = excluded.sent_at;
  insert into private.follow_announced (user_id, event_id) select v_row.user_id, s from unnest(v_row.seen) s on conflict do nothing;
  perform private.notify_push(jsonb_build_object('type','follow','kind','artist','user_id',v_row.user_id,
   'total',v_row.total,'artist_count',v_row.artist_count,'artists',v_row.artists,'event_ids',v_row.event_ids));
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $$;

-- Артисти: хто виступає на події (docs/artists-discovery-2026-10.md). Досі подія знала лише назву й
-- місце. Тут окрема сутність «артист» зі словником імен і зв'язок із подією; конвеєр імпорту
-- (tools/ingest/artists.py) заповнює їх, клієнт показує чип у картці, шукає й дає «Стежити».
--
-- Артист прив'язаний до сеансу (рядка events), а не до шоу: «СТЕНДАП В УКРИТТІ» щодня має інший склад.
-- Майданчик не артист («Театр на Подолі»): це відсікає конвеєр до запису, тут про це нічого не відомо.
-- `key` — нормалізоване ім'я (tools/ingest/artists.key): однакові написання («Phil It», «Phil it»,
-- різні апострофи) сходяться в один рядок. Хибне злиття гірше за дубль, тож за схожістю не зливаємо.

create table public.artists (
 id uuid primary key default gen_random_uuid(),
 name text not null check (length(name) between 1 and 120),
 key text not null unique check (length(key) between 1 and 160),
 -- person | group | company | show; null — вид невідомий (насіння й правила його не знають).
 kind text check (kind in ('person','group','company','show')),
 -- Звідки ім'я: 'manual' (artists.json) > 'auto' (структура, лайнап, словник, правила) > 'llm'.
 -- Перетираємо назву лише щаблем не нижчим за поточний: ручна вивірка не губиться.
 source text not null default 'auto' check (source in ('manual','auto','llm')),
 search tsvector generated always as (to_tsvector('simple', name)) stored,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index artists_search_idx on public.artists using gin (search);

alter table public.artists enable row level security;
create policy artists_read on public.artists for select to anon, authenticated using (true);
grant select on public.artists to anon, authenticated;

create table public.event_artists (
 event_id uuid not null references public.events(id) on delete cascade,
 artist_id uuid not null references public.artists(id) on delete cascade,
 role text not null default 'headliner' check (role in ('headliner','support','host')),
 position smallint not null default 0,
 -- Яким щаблем знайдено: source | lineup | dictionary | rules | llm. Для звіту й дебагу, клієнт не бачить.
 how text not null check (how in ('source','lineup','dictionary','rules','llm')),
 confidence numeric(3,2) check (confidence between 0 and 1),
 primary key (event_id, artist_id)
);
create index event_artists_artist_idx on public.event_artists (artist_id);

-- Прямого доступу немає: подію бачать через картку, а картку фільтрує event_cards.
alter table public.event_artists enable row level security;
revoke all on public.event_artists from public, anon, authenticated;

create function private.artist_source_rank(p_source text) returns integer
language sql immutable set search_path='' as $$
 select case p_source when 'manual' then 3 when 'auto' then 2 else 1 end;
$$;

-- ---- Пошук артистів: за іменем, лише ті, що мають майбутні видимі події (у місті, якщо задано).
create function public.search_artists(p_text text, p_city text default null, p_limit integer default 20)
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
    select count(*)::integer as upcoming
    from public.event_artists ea join public.events e on e.id = ea.event_id
    where ea.artist_id = a.id and e.status='published' and e.ends_at > now()
      and (p_city is null or e.city = p_city)
      and private.is_discoverable(e.origin, e.import_status, e.quality)) u
   -- Префікс слова через tsquery й підрядок через ilike, як у search_places.
   where (a.search @@ (websearch_to_tsquery('simple', q)::text || ':*')::tsquery
          or a.name ilike '%' || q || '%')
     and u.upcoming > 0
   order by u.upcoming desc, a.name
   limit v_limit) t), '[]'::jsonb);
end $$;
revoke all on function public.search_artists(text,text,integer) from public, anon, authenticated;
grant execute on function public.search_artists(text,text,integer) to anon, authenticated;

-- ---- Майбутні події артиста картками. definer, як place_events: прямого select на events у anon немає.
create function public.artist_events(p_artist_id uuid, p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ids uuid[];
begin
 if p_artist_id is null then return '[]'::jsonb; end if;
 select array_agg(x.id order by greatest(x.starts_at, now()), x.id) into ids from (
  select e.id, e.starts_at
  from public.event_artists ea join public.events e on e.id = ea.event_id
  where ea.artist_id = p_artist_id and e.status='published' and e.ends_at > now()
    and private.is_discoverable(e.origin, e.import_status, e.quality)
  order by greatest(e.starts_at, now()), e.id
  limit least(greatest(coalesce(p_limit, 100), 1), 100)) x;
 return private.event_cards(coalesce(ids, '{}'::uuid[]));
end $$;
revoke all on function public.artist_events(uuid,integer) from public, anon, authenticated;
grant execute on function public.artist_events(uuid,integer) to anon, authenticated;

-- ---- Картка події знає своїх артистів: чип у картці. Тіло — з 20260925120000, додано одне поле.
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
    'import_status', e.import_status, 'price_min', e.price_min, 'is_free', e.is_free,
    'artists', (select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'kind', a.kind, 'role', ea.role)
                                 order by ea.position, a.name)
                from public.event_artists ea join public.artists a on a.id = ea.artist_id
                where ea.event_id = e.id))) as card
  from public.events e
  left join public.profiles p on p.id = e.organizer_id
  left join public.event_sources s on s.id = e.source_id
  left join public.places pl on pl.id = e.place_id
  where e.id = any(p_ids) and private.has_event_access(e.id)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
 ) t;
$$;

-- ---- «Стежити» за артистом (20260928160000). Лише зберігання, список і головна: пуш про нові події
-- артиста — окремий крок (функція `push` і `notify_*`), тут його ще немає.
alter table public.follows drop constraint follows_target_kind_check;
alter table public.follows add constraint follows_target_kind_check
 check (target_kind in ('place','organizer','artist'));

-- Артист — афіша з імпорту, як заклад: спільнотних подій у нього нема.
create or replace view private.followed_events as
 select f.user_id, f.target_kind, f.target_id, f.created_at as followed_at,
  e.id as event_id, e.title, e.created_at as event_created_at, e.starts_at, e.place_id
 from public.follows f
 join public.events e on e.place_id = f.target_id
 where f.target_kind = 'place' and e.origin = 'import' and e.status = 'published' and e.ends_at > now()
  and private.is_discoverable(e.origin, e.import_status, e.quality)
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at,
  e.id, e.title, e.created_at, e.starts_at, null::uuid
 from public.follows f
 join public.events e on e.organizer_id = f.target_id
 where f.target_kind = 'organizer' and e.origin = 'community' and e.companion_of is null
  and e.status = 'published' and e.ends_at > now()
  and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id)
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at,
  e.id, e.title, e.created_at, e.starts_at, e.place_id
 from public.follows f
 join public.event_artists ea on ea.artist_id = f.target_id
 join public.events e on e.id = ea.event_id
 where f.target_kind = 'artist' and e.origin = 'import' and e.status = 'published' and e.ends_at > now()
  and private.is_discoverable(e.origin, e.import_status, e.quality);

create or replace function private.follow(p_kind text, p_target uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_kind is null or p_kind not in ('place','organizer','artist') or p_target is null then
  raise exception 'INVALID_FOLLOW' using errcode='22023'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_kind = 'place' then
  if not exists (select 1 from public.places where id = p_target) then
   raise exception 'FOLLOW_UNAVAILABLE' using errcode='P0001'; end if;
 elsif p_kind = 'artist' then
  if not exists (select 1 from public.artists where id = p_target) then
   raise exception 'FOLLOW_UNAVAILABLE' using errcode='P0001'; end if;
 else
  -- Одна відповідь на все, зокрема на блокування в будь-який бік: інакше `follow` за чужим id казав би, хто заблокував.
  -- Організатор — той, хто вже проводить спільнотні події: на решту людей стежити нема за чим.
  if p_target = v_user or private.blocked_between(v_user, p_target) or not private.account_active(p_target) or not exists (
   select 1 from public.events e where e.organizer_id = p_target and e.origin = 'community' and e.status = 'published') then
   raise exception 'FOLLOW_UNAVAILABLE' using errcode='P0001'; end if;
 end if;
 -- Стеля: кожна підписка — рядок у списку й у кожному прогоні зведення; більше двохсот — це вже скрипт.
 if (select count(*) from public.follows where user_id = v_user) >= 200 and not exists (
  select 1 from public.follows where user_id = v_user and target_kind = p_kind and target_id = p_target) then
  raise exception 'TOO_MANY_FOLLOWS' using errcode='P0001'; end if;
 insert into public.follows (user_id, target_kind, target_id) values (v_user, p_kind, p_target) on conflict do nothing;
end $$;

create or replace function private.my_follows() returns jsonb
language sql stable security definer set search_path='' as $$
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
    'upcoming',(select count(distinct lower(btrim(v.title)))::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'artist' and v.target_id = a.id)))
  from public.follows f join public.artists a on a.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'artist'
 ) t;
$$;

-- Головна: прокат одного артиста з кількох сеансів — одна картка, як у закладу.
create or replace function private.follow_events(p_limit integer default 20) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_ids uuid[];
begin
 if auth.uid() is null then return '[]'::jsonb; end if;
 select array_agg(x.event_id order by x.sort_at, x.event_id) into v_ids from (
  select r.event_id, greatest(r.starts_at, now()) as sort_at from (
   select distinct on (v.target_kind, v.target_id, case when v.target_kind in ('place','artist') then lower(btrim(v.title)) else v.event_id::text end)
    v.event_id, v.starts_at
   from private.followed_events v where v.user_id = auth.uid()
   order by v.target_kind, v.target_id, case when v.target_kind in ('place','artist') then lower(btrim(v.title)) else v.event_id::text end,
    v.starts_at, v.event_id) r
  order by greatest(r.starts_at, now()), r.event_id
  limit least(greatest(coalesce(p_limit, 20), 1), 50)) x;
 return private.event_cards(coalesce(v_ids, '{}'::uuid[]));
end $$;

-- ---- Копія своїх даних уже віддає `follows` цілком, окремої правки не потрібно.

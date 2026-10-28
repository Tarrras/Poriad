-- Радар артистів (docs/artist-radar.md): «твій артист їде у твоє місто». Три речі:
--  1. Місто кожного пристрою з дозволом на сповіщення — гостя чи акаунта (`radar_devices`). Пуш артиста тепер лише про
--     подію в місті людини; міста не знаємо — як раніше, без фільтра.
--  2. Гість стежить за артистами без акаунта: список живе на телефоні, сервер знає його за токеном (`radar_artists`),
--     а зведення `notify_radar_devices` шле пуш на сам пристрій, як `send_winbacks`.
--  3. Читання для клієнта: «Ваші артисти» (`artist_radar`) і «Кого слухаєте?» (`popular_artists`).
--
-- Окремо від `private.devices` (канал повернення, 20261030140000): той пристрій живе лише з увімкненим дайджестом, а
-- радар від дайджесту не залежить.
--
-- РОЗГОРТАННЯ: спершу функція `push` (вона вчить `follow/artist` з токеном замість людини), потім ця міграція:
-- зведення записує подію «оголошеною» ще до виклику `push`, і 400 на невідомий формат загубив би її назавжди.

create table private.radar_devices (
 token text primary key,                 -- APNs (64 hex) або FCM; той самий, що в push_tokens
 platform text not null check (platform in ('android','ios')),
 city text,                              -- з HomeLocation; null — своє місце на мапі
 updated_at timestamptz not null default now()
);
create index radar_devices_updated_idx on private.radar_devices(updated_at);

create table private.radar_artists (
 token text not null references private.radar_devices(token) on delete cascade,
 artist_id uuid not null references public.artists(id) on delete cascade,
 created_at timestamptz not null default now(), -- «нове» — подія, що з'явилась після цього
 primary key (token, artist_id)
);
create index radar_artists_artist_idx on private.radar_artists(artist_id);

-- Про що пристрою вже казали й коли востаннє: як `follow_announced` і `follow_pushes`, але ключем — токен.
create table private.radar_announced (
 token text not null references private.radar_devices(token) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 primary key (token, event_id)
);
create table private.radar_pushes (
 token text primary key references private.radar_devices(token) on delete cascade,
 sent_at timestamptz not null
);
revoke all on private.radar_devices, private.radar_artists, private.radar_announced, private.radar_pushes
 from public, anon, authenticated;

-- ---- Клієнт: пристрій і артисти гостя

-- Публічний ключ може насипати рядків, тож формат строгий (як `touch_device`), а нові пристрої вище стелі мовчки не
-- пишемо. Акаунт шле порожній список: його артисти — у `public.follows`. Невідомі id відкидаються мовчки: артиста могли
-- злити чи прибрати, поки він лежав на телефоні.
create function private.set_radar(p_token text, p_platform text, p_city text, p_artists uuid[]) returns void
language plpgsql security definer set search_path='' as $$
declare v_artists uuid[] := coalesce(p_artists, '{}');
begin
 if p_platform is null or p_platform not in ('android','ios') then raise exception 'INVALID_PLATFORM' using errcode='22023'; end if;
 if p_token is null or (p_platform = 'ios' and p_token !~ '^[0-9a-f]{64}$')
   or (p_platform = 'android' and (p_token !~ '^[A-Za-z0-9_:-]+$' or length(p_token) not between 100 and 4096)) then
  raise exception 'INVALID_TOKEN' using errcode='22023';
 end if;
 if p_city is not null and p_city not in ('Київ','Харків','Одеса','Дніпро','Львів') then raise exception 'INVALID_CITY' using errcode='22023'; end if;
 if cardinality(v_artists) > 200 or array_position(v_artists, null) is not null then raise exception 'INVALID_ARTISTS' using errcode='22023'; end if;
 update private.radar_devices set platform = p_platform, city = p_city, updated_at = now() where token = p_token;
 if not found then
  if (select count(*) from private.radar_devices) >= 100000 then
   raise warning 'set_radar: devices ceiling reached, new device not stored';
   return;
  end if;
  insert into private.radar_devices(token, platform, city) values (p_token, p_platform, p_city)
  on conflict (token) do update set platform = excluded.platform, city = excluded.city, updated_at = now();
 end if;
 delete from private.radar_artists r where r.token = p_token and not (r.artist_id = any(v_artists));
 -- Той, що лишився, зберігає свій `created_at`: інакше кожне відкриття обнуляло б «нове».
 insert into private.radar_artists(token, artist_id)
 select p_token, a.id from public.artists a where a.id = any(v_artists)
 on conflict do nothing;
end $$;

-- Дозволу нема чи токен змінився: пристрій зникає разом з артистами й обліком.
create function private.forget_radar(p_token text) returns void language sql security definer set search_path='' as $$
 delete from private.radar_devices where token = p_token;
$$;
create function public.set_radar(p_token text, p_platform text, p_city text, p_artists uuid[]) returns void
language sql security invoker set search_path='' as $$ select private.set_radar(p_token, p_platform, p_city, p_artists); $$;
create function public.forget_radar(p_token text) returns void language sql security invoker set search_path='' as $$
 select private.forget_radar(p_token);
$$;
revoke all on function private.set_radar(text,text,text,uuid[]), private.forget_radar(text),
 public.set_radar(text,text,text,uuid[]), public.forget_radar(text) from public, anon, authenticated;
grant execute on function private.set_radar(text,text,text,uuid[]), private.forget_radar(text),
 public.set_radar(text,text,text,uuid[]), public.forget_radar(text) to anon, authenticated;
-- Функція `push` прибирає мертві токени ключем service role.
grant execute on function private.forget_radar(text), public.forget_radar(text) to service_role;

-- ---- Клієнт: «Ваші артисти» і «Кого слухаєте?»

-- Видимі майбутні події артистів: одне правило для обох читань і зведення гостя.
create function private.radar_events(p_ids uuid[])
returns table(artist_id uuid, event_id uuid, title text, starts_at timestamptz, time_zone text, city text, place_id uuid)
language sql stable security definer set search_path='' as $$
 select ea.artist_id, e.id, e.title, e.starts_at, e.time_zone, e.city, e.place_id
 from public.event_artists ea
 join public.events e on e.id = ea.event_id
 where ea.artist_id = any(p_ids) and e.status = 'published' and e.companion_of is null
  and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.is_discoverable(e.origin, e.import_status, e.quality);
$$;
revoke all on function private.radar_events(uuid[]) from public, anon, authenticated;

-- На артиста: найближча подія в місті, скільки їх там (прокат — одна), і до трьох інших міст із найближчою датою.
-- Порядок рядків — у клієнті (`RadarRules`): там же текст «Поки не в Києві · Львів 20.12». Прокат, що вже йде, —
-- з сьогоднішньою датою, а не з днем прем'єри: піти можна вже зараз.
create function public.artist_radar(p_ids uuid[], p_city text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_ids uuid[] := coalesce(p_ids, '{}');
begin
 if cardinality(v_ids) > 200 then raise exception 'INVALID_ARTISTS' using errcode='22023'; end if;
 if cardinality(v_ids) = 0 then return '[]'::jsonb; end if;
 return coalesce((
  with ev as (select * from private.radar_events(v_ids))
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
   'id', a.id, 'name', a.name, 'kind', a.kind,
   'next', (select jsonb_build_object('id', x.event_id, 'title', x.title, 'starts_at', greatest(x.starts_at, now()), 'time_zone', x.time_zone)
            from ev x where x.artist_id = a.id and x.city = p_city order by x.starts_at, x.event_id limit 1),
   'in_city', (select count(distinct lower(btrim(x.title)) || '|' || coalesce(x.place_id::text, ''))
               from ev x where x.artist_id = a.id and x.city = p_city),
   'elsewhere', (select jsonb_agg(jsonb_build_object('city', c.city, 'starts_at', c.first_at) order by c.first_at)
                 from (select x.city, min(greatest(x.starts_at, now())) as first_at from ev x
                       where x.artist_id = a.id and x.city is distinct from p_city and x.city is not null
                       group by x.city order by min(x.starts_at) limit 3) c)
  )) order by a.name)
  from public.artists a where a.id = any(v_ids)), '[]'::jsonb);
end $$;

-- Хто їде в місто: найбільше подій попереду першими (прокат з кількох сеансів — одна), до [p_limit]. Без міста
-- (онбординг: геолокацію ще не питали) — по всій країні, спершу ті, хто виступає в найбільшій кількості міст.
create function public.popular_artists(p_city text, p_limit integer default 24)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_limit integer := least(greatest(coalesce(p_limit, 24), 1), 60);
begin
 return coalesce((
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
   'id', t.id, 'name', t.name, 'kind', t.kind, 'upcoming', t.upcoming, 'first_at', t.first_at, 'category', t.category))
   order by t.cities desc, t.upcoming desc, t.first_at, t.name)
  from (
   select a.id, a.name, a.kind,
    case when p_city is null then count(distinct e.city)::integer else 1 end as cities,
    count(distinct lower(btrim(e.title)) || '|' || coalesce(e.place_id::text, ''))::integer as upcoming,
    min(greatest(e.starts_at, now())) as first_at,
    (array_agg(e.category order by e.starts_at))[1] as category
   from public.artists a
   join public.event_artists ea on ea.artist_id = a.id
   join public.events e on e.id = ea.event_id
   where (p_city is null or e.city = p_city) and e.status = 'published' and e.companion_of is null
    and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
   group by a.id, a.name, a.kind
   order by cities desc, upcoming desc, first_at, a.name
   limit v_limit) t), '[]'::jsonb);
end $$;
revoke all on function public.artist_radar(uuid[], text), public.popular_artists(text, integer) from public;
grant execute on function public.artist_radar(uuid[], text), public.popular_artists(text, integer) to anon, authenticated;

-- ---- Сервер: пуш акаунту — лише про подію в його місті

-- Міста людини — з її пристроїв: радар (нові збірки) і канал повернення (1.3.2 з дайджестом). Порожньо — фільтра нема.
create or replace function private.notify_artist_follows()
returns integer language plpgsql security definer set search_path='' as $$
declare v_row record; v_sent integer := 0;
begin
 if (select e.url from private.push_endpoint() e) is null then return 0; end if;
 -- Той самий замок, що в notify_place_follows: обидва читають і пишуть одну таблицю ліміту.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('notify_place_follows', 0));
 for v_row in
  with cities as (
   select t.user_id, array_agg(distinct x.city) as list
   from public.push_tokens t
   join lateral (
    select r.city from private.radar_devices r where r.token = t.token
    union all
    select d.city from private.devices d where d.token = t.token
   ) x on x.city is not null
   group by t.user_id
  ), due as (
   -- Прокат — назва в одному місці: нові міста туру — окремі події, а не одна.
   select v.user_id, v.target_id as artist_id, v.event_id, v.starts_at,
          lower(btrim(v.title)) || '|' || coalesce(v.place_id::text, '') as run
   from private.followed_events v
   join public.events ev on ev.id = v.event_id
   left join cities c on c.user_id = v.user_id
   left join private.follow_pushes p on p.user_id = v.user_id
   where v.target_kind = 'artist' and v.event_created_at > v.followed_at
    -- Радар: лише своє місто. Чужі лишаються не «оголошеними» й видні в «Ваші артисти».
    and (c.list is null or ev.city = any(c.list))
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
revoke all on function private.notify_artist_follows() from public, anon, authenticated;

-- ---- Сервер: пуш гостю — на пристрій

-- Як `notify_artist_follows`, але ключем — токен: «нове» після того, як артист потрапив у список пристрою, раз на добу,
-- лише місто пристрою (нема — без фільтра). Пристрій, чий токен уже в `push_tokens`, пропускаємо: людина ввійшла, і її
-- артисти переїхали в акаунт. Тихі години — ворота `notify_push`, як для всіх `follow`.
create function private.notify_radar_devices() returns integer
language plpgsql security definer set search_path='' as $$
declare v_row record; v_sent integer := 0;
begin
 delete from private.radar_devices where updated_at < now() - interval '120 days';
 delete from private.radar_announced a using public.events e where e.id = a.event_id and e.ends_at < now() - interval '2 days';
 if (select e.url from private.push_endpoint() e) is null then return 0; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('notify_radar_devices', 0));
 for v_row in
  with due as (
   select r.token, r.artist_id, x.event_id, x.starts_at,
          lower(btrim(x.title)) || '|' || coalesce(x.place_id::text, '') as run
   from private.radar_artists r
   join private.radar_devices d on d.token = r.token
   join lateral (select * from private.radar_events(array[r.artist_id])) x on true
   join public.events e on e.id = x.event_id
   left join private.radar_pushes p on p.token = r.token
   where e.origin = 'import' and e.created_at > r.created_at
    and (d.city is null or x.city = d.city)
    and (p.sent_at is null or p.sent_at <= now() - interval '24 hours')
    and not exists (select 1 from private.radar_announced a where a.token = r.token and a.event_id = x.event_id)
    and not exists (select 1 from public.push_tokens t where t.token = r.token)
  ), runs as (
   select distinct on (d.token, d.artist_id, d.run) d.token, d.artist_id, d.event_id, d.starts_at, d.run
   from due d order by d.token, d.artist_id, d.run, d.starts_at, d.event_id
  ), by_artist as (
   select u.token, u.artist_id, count(*)::integer as n, min(u.starts_at) as first_at
   from runs u group by u.token, u.artist_id
  ), shows as (
   select distinct on (r.token, r.run) r.token, r.event_id, r.starts_at
   from runs r order by r.token, r.run, r.starts_at, r.event_id
  )
  select g.token, (select d.platform from private.radar_devices d where d.token = g.token) as platform,
   count(*)::integer as total,
   (select count(*)::integer from by_artist b where b.token = g.token) as artist_count,
   (select jsonb_agg(jsonb_build_object('id', x.artist_id, 'n', x.n) order by x.n desc, x.first_at, x.artist_id)
    from (select b.* from by_artist b where b.token = g.token order by b.n desc, b.first_at, b.artist_id limit 5) x) as artists,
   (select jsonb_agg(y.event_id order by y.starts_at, y.event_id)
    from (select s.* from shows s where s.token = g.token order by s.starts_at, s.event_id limit 3) y) as event_ids,
   (select array_agg(d.event_id) from due d where d.token = g.token) as seen
  from shows g group by g.token
 loop
  insert into private.radar_pushes (token, sent_at) values (v_row.token, now())
   on conflict (token) do update set sent_at = excluded.sent_at;
  insert into private.radar_announced (token, event_id) select v_row.token, s from unnest(v_row.seen) s on conflict do nothing;
  perform private.notify_push(jsonb_build_object('type','follow','kind','artist','token',v_row.token,'platform',v_row.platform,
   'total',v_row.total,'artist_count',v_row.artist_count,'artists',v_row.artists,'event_ids',v_row.event_ids));
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $$;
revoke all on function private.notify_radar_devices() from public, anon, authenticated;

-- Щогодини о :03, де є pg_cron (на prod є): :02 — артисти акаунтів, :05 — черга тихих годин, :07 — заклади.
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('notify-radar-devices', '3 * * * *', 'select private.notify_radar_devices()')$cron$;
 end if;
end $$;

-- ---- «З ким піти» на мапі (аудит головної 28.10)

-- На головній «Від людей» і «Шукають компанію» стали однією рейкою «З ким піти», і її «Усі N» веде на мапу з тим самим
-- фільтром. Тож p_available тепер — зустріч із вільним місцем АБО афіша, на яку хтось шукає компанію.
-- Тіло — з 20261112120000_cinema_category.sql (кіно, гілка cinema-import), змінено лише умову p_available. Тому ця
-- міграція йде після кіно: інакше кіно перезапише функцію старим тілом.
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
    and (coalesce(p_cinema,false) or e.category <> 'cinema')
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

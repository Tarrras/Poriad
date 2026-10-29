-- «Мої місця» (docs/my-places.md): пристрій стежить за зонами — район міста чи коло 1–3 км — і чує про нові події
-- від людей у них. Три речі:
--  1. Зони пристрою (`zone_areas`): список живе на телефоні, сервер знає його за токеном пуша, як артистів гостя в
--     радарі. Пристрій — той самий рядок `radar_devices`: без дозволу на сповіщення зон на сервері нема.
--  2. Зведення `notify_zone_devices`: нова зустріч чи «Йдемо разом» у зоні — пуш на пристрій, не частіше разу на добу.
--     Афіші тут нема: її поруч забагато (у Києві ~70 нових на день), вона йде дайджестом на телефоні.
--  3. Організатору — `zone_audience`: скільки людей поруч почують про подію в цій точці. Менше трьох — null: «1 людина
--     поруч» видавала б сусіда.
--
-- РОЗГОРТАННЯ: після 20261113 (радар — тут його пристрої). Спершу функція `push` (вона вчить тип `zone`), потім ця
-- міграція: зведення записує подію «оголошеною» ще до виклику `push`.

create table private.zone_areas (
 token text not null references private.radar_devices(token) on delete cascade,
 -- 'd:<id району>' або 'c:<широта>,<довгота>,<радіус>' з точкою, округленою до ~100 м: той самий ключ при кожній
 -- синхронізації, тож `created_at` зони не скидається.
 key text not null check (key ~ '^(d:-?[0-9]{1,19}|c:-?[0-9]{1,2}\.[0-9]{3},-?[0-9]{1,3}\.[0-9]{3},[0-9]{4})$'),
 area gis.geography not null,
 created_at timestamptz not null default now(), -- «нове» — подія, що з'явилась після цього
 primary key (token, key)
);
create index zone_areas_area_idx on private.zone_areas using gist(area);

-- Про що пристрою вже казали й коли востаннє: як `radar_announced` і `radar_pushes`.
create table private.zone_announced (
 token text not null references private.radar_devices(token) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 primary key (token, event_id)
);
create table private.zone_pushes (
 token text primary key references private.radar_devices(token) on delete cascade,
 sent_at timestamptz not null
);
revoke all on private.zone_areas, private.zone_announced, private.zone_pushes from public, anon, authenticated;

-- ---- Клієнт: зони пристрою

-- Пристрій — спільний з радаром: перевірка формату й стеля, які раніше жили в `set_radar`. False — новий пристрій
-- вище стелі, не записано. Токен APNs — 64–200 hex, як у функції `push`: Apple не обіцяє довжини, а симулятор iOS 26
-- уже дає 80 байтів.
create function private.radar_device(p_token text, p_platform text, p_city text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if p_platform is null or p_platform not in ('android','ios') then raise exception 'INVALID_PLATFORM' using errcode='22023'; end if;
 if p_token is null or (p_platform = 'ios' and p_token !~ '^[0-9a-f]{64,200}$')
   or (p_platform = 'android' and (p_token !~ '^[A-Za-z0-9_:-]+$' or length(p_token) not between 100 and 4096)) then
  raise exception 'INVALID_TOKEN' using errcode='22023';
 end if;
 if p_city is not null and p_city not in ('Київ','Харків','Одеса','Дніпро','Львів') then raise exception 'INVALID_CITY' using errcode='22023'; end if;
 update private.radar_devices set platform = p_platform, city = p_city, updated_at = now() where token = p_token;
 if found then return true; end if;
 if (select count(*) from private.radar_devices) >= 100000 then
  raise warning 'radar_device: devices ceiling reached, new device not stored';
  return false;
 end if;
 insert into private.radar_devices(token, platform, city) values (p_token, p_platform, p_city)
 on conflict (token) do update set platform = excluded.platform, city = excluded.city, updated_at = now();
 return true;
end $$;
revoke all on function private.radar_device(text,text,text) from public, anon, authenticated;

-- Тіло — з 20261113120000, пристрій тепер пише `radar_device`.
create or replace function private.set_radar(p_token text, p_platform text, p_city text, p_artists uuid[]) returns void
language plpgsql security definer set search_path='' as $$
declare v_artists uuid[] := coalesce(p_artists, '{}');
begin
 if cardinality(v_artists) > 200 or array_position(v_artists, null) is not null then raise exception 'INVALID_ARTISTS' using errcode='22023'; end if;
 if not private.radar_device(p_token, p_platform, p_city) then return; end if;
 delete from private.radar_artists r where r.token = p_token and not (r.artist_id = any(v_artists));
 -- Той, що лишився, зберігає свій `created_at`: інакше кожне відкриття обнуляло б «нове».
 insert into private.radar_artists(token, artist_id)
 select p_token, a.id from public.artists a where a.id = any(v_artists)
 on conflict do nothing;
end $$;

-- Ключ і межа кожної зони зі списку клієнта; формат уже перевірено.
create function private.zone_inputs(p_districts bigint[], p_circles jsonb) returns table (key text, area gis.geography)
language sql stable security definer set search_path='' as $$
 select 'd:' || d.id, d.boundary::gis.geography from public.districts d where d.id = any(p_districts)
 union all
 select distinct on (1) 'c:' || to_char(x.lat, 'FM90.000') || ',' || to_char(x.lon, 'FM990.000') || ',' || x.r,
        gis.st_buffer(gis.st_setsrid(gis.st_makepoint(x.lon::float8, x.lat::float8), 4326)::gis.geography, x.r::float8)
 from (select round((c->>'lat')::numeric, 3) as lat, round((c->>'lon')::numeric, 3) as lon, (c->>'r')::integer as r
       from jsonb_array_elements(p_circles) c) x;
$$;
revoke all on function private.zone_inputs(bigint[], jsonb) from public, anon, authenticated;

-- Повний список зон пристрою: райони за id з `city_districts` (місцевість — теж район, її межа — коло) і кола
-- [{lat, lon, r}] з радіусом 1000, 2000 чи 3000 м. Точку кола округлюємо до ~100 м: місце, де людина живе, точніше
-- знати не треба. Невідомі райони відкидаються мовчки, як невідомі артисти в радарі.
create function private.set_zones(p_token text, p_platform text, p_city text, p_districts bigint[], p_circles jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare v_districts bigint[] := coalesce(p_districts, '{}'); v_circles jsonb := coalesce(p_circles, '[]'::jsonb);
begin
 if cardinality(v_districts) > 20 or array_position(v_districts, null) is not null then raise exception 'INVALID_DISTRICTS' using errcode='22023'; end if;
 if jsonb_typeof(v_circles) <> 'array' or jsonb_array_length(v_circles) > 10 or exists (
   select 1 from jsonb_array_elements(v_circles) c
   where jsonb_typeof(c->'lat') is distinct from 'number' or jsonb_typeof(c->'lon') is distinct from 'number'
    or (c->>'lat')::numeric not between 44 and 53 or (c->>'lon')::numeric not between 22 and 41
    or (c->>'r') is null or (c->>'r') not in ('1000','2000','3000')) then
  raise exception 'INVALID_CIRCLES' using errcode='22023';
 end if;
 if not private.radar_device(p_token, p_platform, p_city) then return; end if;
 delete from private.zone_areas z where z.token = p_token
  and z.key <> all(array(select i.key from private.zone_inputs(v_districts, v_circles) i));
 -- Та, що лишилась, зберігає свій `created_at`: інакше кожне відкриття обнуляло б «нове».
 insert into private.zone_areas(token, key, area) select p_token, i.key, i.area from private.zone_inputs(v_districts, v_circles) i
 on conflict do nothing;
end $$;
create function public.set_zones(p_token text, p_platform text, p_city text, p_districts bigint[], p_circles jsonb) returns void
language sql security invoker set search_path='' as $$ select private.set_zones(p_token, p_platform, p_city, p_districts, p_circles); $$;
revoke all on function private.set_zones(text,text,text,bigint[],jsonb), public.set_zones(text,text,text,bigint[],jsonb)
 from public, anon, authenticated;
grant execute on function private.set_zones(text,text,text,bigint[],jsonb), public.set_zones(text,text,text,bigint[],jsonb)
 to anon, authenticated;

-- ---- Організатор: скільки людей поруч почують

-- Пристрої, чия зона накриває точку, крім пристроїв самого організатора. Менше трьох — null: «1 людина поруч» видавала
-- б, що поруч хтось живе. Лише з акаунтом: подію створює акаунт.
create function public.zone_audience(p_lat double precision, p_lon double precision) returns integer
language sql stable security definer set search_path='' as $$
 select case when x.n >= 3 then x.n end from (
  select count(distinct z.token)::integer as n
  from private.zone_areas z
  where p_lat between 44 and 53 and p_lon between 22 and 41
   and gis.st_covers(z.area, gis.st_setsrid(gis.st_makepoint(p_lon, p_lat), 4326)::gis.geography)
   and not exists (select 1 from public.push_tokens t where t.token = z.token and t.user_id = auth.uid())
 ) x;
$$;
revoke all on function public.zone_audience(double precision, double precision) from public, anon, authenticated;
grant execute on function public.zone_audience(double precision, double precision) to authenticated;

-- ---- Сервер: пуш на пристрій

-- Нове = подія від людей (зустріч чи «Йдемо разом»), що з'явилась у зоні після того, як пристрій за нею стежить, ще
-- попереду і пристрою про неї не казали. Раз на добу; що не влізло, лишається «новим» і їде наступним прогоном.
-- Своя подія й подія того, з ким людина заблокована, — не новина. Тихі години — ворота `notify_push`.
create function private.notify_zone_devices() returns integer
language plpgsql security definer set search_path='' as $$
declare v_row record; v_sent integer := 0;
begin
 delete from private.zone_announced a using public.events e where e.id = a.event_id and e.starts_at < now() - interval '2 days';
 if (select e.url from private.push_endpoint() e) is null then return 0; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('notify_zone_devices', 0));
 for v_row in
  with fresh as (
   select e.id, e.starts_at, e.organizer_id, e.location, e.created_at from public.events e
   where e.origin = 'community' and e.status = 'published' and e.starts_at > now()
    and e.created_at > now() - interval '7 days'
  ), due as (
   select distinct z.token, f.id as event_id, f.starts_at
   from fresh f
   join private.zone_areas z on gis.st_covers(z.area, f.location) and f.created_at > z.created_at
   left join private.zone_pushes p on p.token = z.token
   where (p.sent_at is null or p.sent_at <= now() - interval '24 hours')
    and not exists (select 1 from private.zone_announced a where a.token = z.token and a.event_id = f.id)
    and not exists (select 1 from public.push_tokens t where t.token = z.token
                    and (t.user_id = f.organizer_id or private.blocked_between(t.user_id, f.organizer_id)))
  )
  select d.token, (select r.platform from private.radar_devices r where r.token = d.token) as platform,
   count(*)::integer as total,
   (array_agg(d.event_id order by d.starts_at, d.event_id))[1] as event_id,
   array_agg(d.event_id) as seen
  from due d group by d.token
 loop
  insert into private.zone_pushes (token, sent_at) values (v_row.token, now())
   on conflict (token) do update set sent_at = excluded.sent_at;
  insert into private.zone_announced (token, event_id) select v_row.token, s from unnest(v_row.seen) s on conflict do nothing;
  perform private.notify_push(jsonb_build_object('type','zone','token',v_row.token,'platform',v_row.platform,
   'event_id',v_row.event_id,'total',v_row.total));
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $$;
revoke all on function private.notify_zone_devices() from public, anon, authenticated;

-- Тіло — з 20261110120000, у ранкову чергу йде ще й `zone`: «нова подія біля вас» о третій ночі не потрібна.
create or replace function private.notify_push(p_payload jsonb) returns void language plpgsql security definer set search_path='' as $$
declare v_url text; v_secret text;
begin
 select url,secret into v_url,v_secret from private.push_endpoint();
 if v_url is null or v_secret is null then return; end if;
 -- «Стежити», компанія й зони вночі — у чергу до ранку: `flush_deferred_pushes` відправить, функція `push` ще раз
 -- перевірить, що подія жива. Решта типів — транзакційні, їх не тримаємо.
 if p_payload->>'type' in ('follow','company','zone') and private.quiet_hours() then
  insert into private.deferred_pushes(payload) values (p_payload);
  return;
 end if;
 -- Асинхронно: відповідь функції транзакцію не тримає.
 perform net.http_post(
  url:=v_url,
  body:=p_payload,
  headers:=jsonb_build_object('Content-Type','application/json','x-push-secret',v_secret),
  timeout_milliseconds:=5000
 );
exception when others then
 -- Пуш — доповнення: збій доставки не має зламати запис повідомлення чи запиту.
 raise warning 'push notify failed: %', sqlerrm;
end $$;

-- Кожні 10 хвилин, де є pg_cron (на prod є): подій від людей мало, і про нову поруч краще сказати одразу.
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('notify-zone-devices', '*/10 * * * *', 'select private.notify_zone_devices()')$cron$;
 end if;
end $$;

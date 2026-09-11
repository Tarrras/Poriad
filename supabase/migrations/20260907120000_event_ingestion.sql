-- Імпорт подій із зовнішніх джерел. Обґрунтування джерел і виміряні числа — docs/event-discovery.md.
--
-- Головна межа цієї міграції: подія має рід. `community` створює людина, до неї приєднуються.
-- `import` приходить із конвеєра, і приєднатися до неї неможливо — не тому, що клієнт ховає кнопку,
-- а тому, що це заборонено в тій самій функції, де зібрані всі інші причини відмови.

-- ------------------------------------------------------------------ джерела

create table public.event_sources (
 id uuid primary key default gen_random_uuid(),
 slug text not null unique check (slug ~ '^[a-z0-9_]{2,40}$'),
 name text not null check (char_length(btrim(name)) between 1 and 80),  -- показуємо як «Афіша · <name>»
 kind text not null check (kind in ('listing_jsonld','sitemap_jsonld','ics','rss','api','telegram','manual')),
 base_url text not null check (base_url like 'https://%'),
 -- Сторінки-списки за містами. Виміряно: один запит до concert.ua/uk/kyiv дає 118 подій,
 -- до kyiv.karabas.com — 149. Тому це головний режим обходу, а не sitemap.
 listing_urls text[] not null default '{}',
 city text,
 -- Синтетичний акаунт джерела. events.organizer_id -> profiles.id -> auth.users.id, тож це має бути
 -- справжній обліковий запис: створюється один раз адміністратором, міграція його не вигадує.
 organizer_id uuid references public.profiles(id) on delete restrict,
 weight numeric not null default 0.5 check (weight between 0 and 1),
 crawl_delay_seconds integer not null default 5 check (crawl_delay_seconds between 0 and 3600),
 -- moemisto.ua віддає локальний київський час зі зсувом +0000 (12 із 12 сторінок вибірки).
 -- Це властивість джерела, а не поправка в парсері, інакше наступне таке джерело зламає все вдруге.
 tz_policy text not null default 'source' check (tz_policy in ('source','force_local')),
 default_time_zone text not null default 'Europe/Kyiv',
 sitemap_min_lastmod date,               -- у moemisto лише 4% з 12 862 URL стосуються цього року
 licence text not null default 'jsonld_public' check (licence in ('partner','jsonld_public','agreed','manual')),
 enabled boolean not null default false, -- джерело вмикається свідомо, а не фактом існування рядка
 etag text, last_modified text, last_run_at timestamptz,
 created_at timestamptz not null default now()
);

-- ------------------------------------------------------------------ кеш майданчиків
--
-- Жодне з перевірених джерел не віддає координат: 0 із 293 записів на сторінках-списках і 0 із 24
-- сторінок подій. Геокодування тут не стадія конвеєра, а сам конвеєр. Рятує концентрація:
-- ~55 майданчиків покривають 267 київських подій.

create table public.venues (
 id uuid primary key default gen_random_uuid(),
 norm_name text not null,
 norm_address text not null default '',
 display_name text,
 latitude double precision not null check (latitude between -90 and 90),
 longitude double precision not null check (longitude between -180 and 180),
 city text,
 -- 'osm' — дамп Overpass під ODbL; 'manual' — ручна вивірка, найточніше; 'photon' — геокодер.
 source text not null default 'manual' check (source in ('osm','manual','photon')),
 osm_ref text,
 confidence numeric not null default 0.5 check (confidence between 0 and 1),
 geocoded_at timestamptz not null default now(),
 unique (norm_name, norm_address)
);
create index venues_city_idx on public.venues(city);

-- ------------------------------------------------------------------ поля імпорту на подіях

alter table public.events
 add column origin text not null default 'community' check (origin in ('community','import','partner')),
 add column source_id uuid references public.event_sources(id) on delete restrict,
 add column source_uid text,
 add column canonical_url text check (canonical_url is null or (canonical_url like 'https://%' and char_length(canonical_url) <= 2048)),
 add column content_hash text,
 add column dedupe_key text,
 add column quality numeric check (quality is null or quality between 0 and 1),
 add column import_status text check (import_status in ('live','stale','withdrawn')),
 add column price_min numeric check (price_min is null or price_min >= 0),
 add column is_free boolean,
 add column ingest_run_id uuid;

-- Рід і походження мають бути узгоджені: імпорт без джерела — це подія-сирота, яку нічим оновити
-- й нікуди відкликати, а спільнотна подія з source_id прикидається чужою.
alter table public.events add constraint events_origin_source_ck check (
 (origin = 'community' and source_id is null and source_uid is null and import_status is null)
 or (origin <> 'community' and source_id is not null and source_uid is not null and import_status is not null)
);

create unique index events_source_uid_uidx on public.events(source_id, source_uid) where source_id is not null;
create index events_dedupe_idx on public.events(dedupe_key) where dedupe_key is not null;
create index events_origin_starts_idx on public.events(origin, starts_at) where status = 'published';

-- ------------------------------------------------------------------ що видно у видачі
--
-- Поріг якості й стан імпорту фільтруються тут, а не в клієнті. Відкликана подія лишається
-- доступною тому, хто її зберіг (порожній збережений запис гірший за позначку «більше не
-- проводиться»), але зникає з мапи й пошуку.
create function private.is_discoverable(p_origin text, p_import_status text, p_quality numeric)
returns boolean language sql immutable set search_path='' as $$
 select p_origin = 'community'
     or (p_import_status = 'live' and coalesce(p_quality,0) >= 0.55);
$$;
revoke all on function private.is_discoverable(text,text,numeric) from public,anon,authenticated;
grant execute on function private.is_discoverable(text,text,numeric) to anon,authenticated;

-- ------------------------------------------------------------------ проєкція
--
-- Перестворення композитного типу тягне за собою залежні функції — вони перебудовані нижче в одній
-- транзакції з ним, тим самим порядком, що й у міграції безпеки.

drop function if exists public.event_details(uuid);
drop function if exists public.my_events();
drop function if exists public.events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz);
drop function if exists public.search_events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean);
drop function if exists private.event_rows(uuid[]);
drop type public.event_result;

create type public.event_result as (
 id uuid,title text,description text,category text,city text,address text,
 organizer_id uuid,organizer_name text,starts_at timestamptz,ends_at timestamptz,time_zone text,status text,
 latitude double precision,longitude double precision,capacity integer,attendee_count integer,joined boolean,image_url text,
 min_age integer,max_age integer,approval_required boolean,membership text,
 origin text,source_name text,canonical_url text,import_status text,price_min numeric,is_free boolean
);

create function private.event_rows(p_ids uuid[]) returns setof public.event_result language sql stable security definer set search_path = '' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,p.display_name,
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
 e.origin,s.name,e.canonical_url,e.import_status,e.price_min,e.is_free
 from public.events e
 join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 where e.id=any(p_ids) and private.has_event_access(e.id)
 and (e.organizer_id=auth.uid() or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$$;
revoke all on function private.event_rows(uuid[]) from public,anon,authenticated;
grant execute on function private.event_rows(uuid[]) to anon,authenticated;

create function public.event_details(p_event_id uuid) returns setof public.event_result language sql stable security invoker set search_path = '' as $$
 select * from private.event_rows(array[p_event_id]);
$$;

create function public.events_in_view(p_south double precision,p_west double precision,p_north double precision,p_east double precision,p_category text default null,p_from timestamptz default null,p_to timestamptz default null)
 returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and e.starts_at > now()
 and private.is_discoverable(e.origin,e.import_status,e.quality)
 and (p_category is null or e.category=p_category)
 and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
 and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
 or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
 or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326))))
 order by e.starts_at,e.id limit 300)) r order by r.starts_at,r.id;
end $$;

create function public.my_events() returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e where e.organizer_id=auth.uid()
 or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid())
 or exists(select 1 from public.saved_events s where s.user_id=auth.uid() and s.event_id=e.id))) r order by r.starts_at,r.id;
end $$;

create function public.search_events_in_view(p_south double precision,p_west double precision,p_north double precision,p_east double precision,p_category text default null,p_from timestamptz default null,p_to timestamptz default null,p_text text default null,p_available boolean default false)
 returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text)>120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and e.starts_at > now()
 and private.is_discoverable(e.origin,e.import_status,e.quality)
 and (nullif(btrim(p_text),'') is null or strpos(lower(concat_ws(' ',e.title,e.description,e.city,e.address)),lower(btrim(p_text)))>0)
 and (not coalesce(p_available,false) or private.event_has_space(e.id))
 and (p_category is null or e.category=p_category)
 and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
 and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
 or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
 or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326))))
 order by e.starts_at,e.id limit 300)) r order by r.starts_at,r.id;
end $$;

revoke all on function public.event_details(uuid),public.my_events(),
 public.events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz),
 public.search_events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean)
 from public,anon,authenticated;
grant execute on function public.event_details(uuid),
 public.events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz),
 public.search_events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean) to anon,authenticated;
grant execute on function public.my_events() to authenticated;

-- ------------------------------------------------------------------ запобіжники
--
-- Приєднання до імпортованої події неможливе. Правило стоїть тут, а не в клієнті: інакше воно
-- тримається лише до першого пропатченого застосунку. Місткості чужого концерту ми не знаємо й не
-- керуємо нею, тож «приєднатися» було б обіцянкою, яку нема кому виконати.
create or replace function private.assert_can_join(p_user uuid,p_event public.events) returns void language plpgsql stable security definer set search_path='' as $$
declare v_age integer;
begin
 if p_event.origin <> 'community' then raise exception 'IMPORTED_EVENT' using errcode='P0001'; end if;
 if not private.account_active(p_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.blocked_between(p_user,p_event.organizer_id) then raise exception 'BLOCKED' using errcode='42501'; end if;
 v_age := private.age_of(p_user);
 if v_age is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 if v_age < p_event.min_age then raise exception 'TOO_YOUNG' using errcode='P0001'; end if;
 if p_event.max_age is not null and v_age > p_event.max_age then raise exception 'TOO_OLD' using errcode='P0001'; end if;
end $$;

-- Редагувати чужу імпортовану подію не можна навіть її синтетичному акаунту: єдиний законний шлях
-- змінити її — наступний запуск конвеєра, який пише як власник бази.
create or replace function private.assert_event_editable(p_event public.events) returns void language plpgsql immutable set search_path='' as $$
begin
 if p_event.origin <> 'community' then raise exception 'IMPORTED_EVENT' using errcode='P0001'; end if;
end $$;
revoke all on function private.assert_event_editable(public.events) from public,anon,authenticated;
grant execute on function private.assert_event_editable(public.events) to authenticated;

-- ------------------------------------------------------------------ сире й проміжне
--
-- Живе поза public: користувачам цього бачити нема чого, і Data API сюди не дістає.

create table private.ingest_runs (
 id uuid primary key default gen_random_uuid(),
 source_id uuid not null references public.event_sources(id) on delete cascade,
 started_at timestamptz not null default now(),
 finished_at timestamptz,
 fetched int not null default 0, parsed int not null default 0, geocoded int not null default 0,
 published int not null default 0, merged int not null default 0,
 rejected int not null default 0, review int not null default 0,
 error text
);
create index ingest_runs_source_idx on private.ingest_runs(source_id, started_at desc);

create table private.ingest_items (
 id uuid primary key default gen_random_uuid(),
 run_id uuid not null references private.ingest_runs(id) on delete cascade,
 source_id uuid not null references public.event_sources(id) on delete cascade,
 source_uid text not null,
 url text,
 raw jsonb not null,
 content_hash text,
 stage text not null check (stage in ('fetched','parsed','normalized','geocoded','deduped','published','rejected','review')),
 reject_reason text,
 candidate_event_id uuid,
 similarity numeric,
 created_at timestamptz not null default now()
);
create index ingest_items_run_idx on private.ingest_items(run_id, stage);
create index ingest_items_review_idx on private.ingest_items(stage) where stage in ('review','rejected');

alter table public.event_sources enable row level security;
alter table public.venues enable row level security;

revoke all on public.event_sources, public.venues from anon, authenticated;
-- Джерела читаються всіма: назва джерела стоїть на картці як обов'язкова атрибуція, тож без
-- цього рядка картка імпортованої події не може виконати умову з розділу 8 event-ingestion.md.
grant select on public.event_sources to anon, authenticated;
create policy event_sources_read on public.event_sources for select to anon,authenticated using (true);

-- venues лишається без політик свідомо: це внутрішній кеш геокодування, клієнтам він не потрібен —
-- координати вони отримують уже в проєкції події. RLS без політик = доступу немає ні в кого,
-- окрім власника бази, який і пише туди з конвеєра.

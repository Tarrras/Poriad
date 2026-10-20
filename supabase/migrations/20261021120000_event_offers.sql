-- Подія з кількома продавцями (docs/event-offers.md, фаза 1: R1–R3).
--
-- Було: рядок events — це сеанс одного продавця з ключем імпорту (source_id, source_uid). Злиття дублів знімало
-- рядок-копію (`import_status='withdrawn'`), переможця вибирали заново щопрогону, тож ідентичність скакала між
-- рядками, а збереження й артисти лишались на знятому. Тепер:
-- - `public.event_offers` — пропозиція одного продавця, ключ імпорту переїхав сюди. `events` лишається подією.
-- - Колонки events, які читають випущені клієнти (source_id/source_uid/canonical_url — основна пропозиція,
--   price_min/is_free — мінімум живих, import_status — live, поки жива хоч одна), веде тригер з пропозицій. Тому
--   event_rows / event_cards / discover_index не змінюються (R3).
-- - Злита подія лишається надгробком `merged_into`; зв'язки переходять на живу (`private.merge_event`), старий id
--   розгортають `event_details` і `event_cards_by_ids`.
-- - Дамп пише пропозиції функцією `private.ingest_offers` (tools/ingest/emit.py).

-- ───────────────────────────────────────────── таблиці

create table public.event_offers (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.events(id) on delete cascade,
 source_id uuid not null references public.event_sources(id) on delete restrict,
 source_uid text not null,
 canonical_url text check (canonical_url is null or (canonical_url like 'https://%' and char_length(canonical_url) <= 2048)),
 -- Назва продавця, а не події: тихий перенос зіставляється з нею, коли основний продавець пише назву інакше.
 title text not null,
 starts_at timestamptz not null,
 price_min numeric check (price_min is null or price_min >= 0),
 is_free boolean,
 -- withdrawn з ingest_run_id is null — ручне зняття: дамп його не повертає (як було в events).
 status text not null default 'live' check (status in ('live','withdrawn')),
 ingest_run_id uuid,
 -- Як пропозицію приєднано до події. manual — рука людини: конвеєр її не переносить, а її подію не зливає.
 linked text not null default 'rule' check (linked in ('rule','agent','manual')),
 seen_at timestamptz not null default now(),
 checked_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (source_id, source_uid)
);
create index event_offers_event_idx on public.event_offers (event_id);
create index event_offers_url_idx on public.event_offers (source_id, canonical_url);
alter table public.event_offers enable row level security;
revoke all on public.event_offers from public, anon, authenticated;

alter table public.events add column merged_into uuid references public.events(id) on delete set null;
alter table public.events add constraint events_merged_into_ck
 check (merged_into is null or (merged_into <> id and origin <> 'community'));
create index events_merged_into_idx on public.events (merged_into) where merged_into is not null;
-- Ключ імпорту тепер у пропозиціях. У events source_uid — дзеркало основної, і надгробок може носити той самий.
drop index public.events_source_uid_uidx;

-- Журнал злиттів: що куди злито й скільки зв'язків перенесено (звіт R2 і щоденні злиття дампу).
create table private.event_merges (
 from_id uuid not null,
 into_id uuid not null,
 reason text not null,
 moved jsonb not null,
 merged_at timestamptz not null default now()
);
create index event_merges_at_idx on private.event_merges (merged_at desc);
revoke all on private.event_merges from public, anon, authenticated;

-- Кожен імпортований рядок стає своєю пропозицією. Тригер ще не висить: дзеркала й так збігаються.
insert into public.event_offers (event_id, source_id, source_uid, canonical_url, title, starts_at, price_min, is_free,
 status, ingest_run_id, seen_at, created_at, updated_at)
select e.id, e.source_id, e.source_uid, e.canonical_url, e.title, e.starts_at, e.price_min, e.is_free,
 case when e.import_status = 'withdrawn' then 'withdrawn' else 'live' end, e.ingest_run_id, e.updated_at, e.created_at,
 e.updated_at
from public.events e where e.origin <> 'community';

-- ───────────────────────────────────────────── функції

-- Назва для зіставлення: без хвоста в дужках («Гедда Габлер (Театр на Подолі)»), лапок, розділових і пробілів.
-- Символи перелічено явно: класи залежать від локалі бази. Раніше жила текстом у emit._title_key_sql.
create or replace function private.title_key(p_title text) returns text
language sql immutable set search_path='' as $$
 select regexp_replace(regexp_replace(lower(p_title), '\s*\([^()]*\)\s*$', ''), '[\s«»"“”„''`ʼ’‘!?.,:;…–—-]+', '', 'g');
$$;

create or replace function private.live_event_id(p_id uuid) returns uuid
language sql stable security definer set search_path='' as $$
 select coalesce((select e.merged_into from public.events e where e.id = p_id), p_id);
$$;

create or replace function private.event_frozen(p_event uuid) returns boolean
language sql stable set search_path='' as $$
 select exists (select 1 from public.event_offers o where o.event_id = p_event and o.linked = 'manual');
$$;

-- Дзеркала події з її пропозицій (R3). Основна — поточна, поки жива; інакше жива з найбільшою вагою джерела;
-- без живих поточна лишається, щоб кнопка вела туди, де подію бачили востаннє.
create or replace function private.sync_event(p_event uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_event public.events; v_primary public.event_offers; v_live integer; v_price numeric; v_free boolean; v_status text;
begin
 select * into v_event from public.events where id = p_event;
 if not found or v_event.merged_into is not null then return; end if;
 select o.* into v_primary from public.event_offers o join public.event_sources s on s.id = o.source_id
 where o.event_id = p_event
 order by o.status = 'live' desc, (o.source_id = v_event.source_id and o.source_uid = v_event.source_uid) desc,
          s.weight desc, o.created_at, o.id
 limit 1;
 if not found then return; end if;           -- подія без пропозицій (спільнотна чи тестова) — не наша справа
 select count(*), min(o.price_min), bool_or(o.is_free) into v_live, v_price, v_free
 from public.event_offers o where o.event_id = p_event and o.status = 'live';
 v_status := case when v_live = 0 then 'withdrawn'
                  when v_event.import_status = 'stale' and v_event.ends_at < now() then 'stale' else 'live' end;
 if v_live = 0 then v_price := v_event.price_min; v_free := v_event.is_free; end if;
 update public.events e set source_id = v_primary.source_id, source_uid = v_primary.source_uid,
  canonical_url = v_primary.canonical_url, price_min = v_price, is_free = v_free, import_status = v_status,
  ingest_run_id = v_primary.ingest_run_id, updated_at = now()
 where e.id = p_event and (e.source_id, e.source_uid, e.canonical_url, e.price_min, e.is_free, e.import_status, e.ingest_run_id)
  is distinct from (v_primary.source_id, v_primary.source_uid, v_primary.canonical_url, v_price, v_free, v_status,
                    v_primary.ingest_run_id);
end $$;

create or replace function private.on_offer_changed() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op = 'DELETE' then perform private.sync_event(old.event_id); return old; end if;
 perform private.sync_event(new.event_id);
 if tg_op = 'UPDATE' and old.event_id <> new.event_id then perform private.sync_event(old.event_id); end if;
 return new;
end $$;

create trigger event_offers_sync after insert or update or delete on public.event_offers
for each row execute function private.on_offer_changed();

-- Злиття двох імпортованих подій (R2): усе з `p_from` переходить на `p_into`, `p_from` стає надгробком. Дублі за
-- первинним ключем відкидаються (у `p_into` вже є той самий рядок), нічого не губиться каскадом: рядок події не
-- видаляється. Переносимо UPDATE-ом, а не вставкою: тригер вставки event_members інакше слав би пуш організатору.
create or replace function private.merge_event(p_from uuid, p_into uuid, p_reason text default 'pipeline') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_from public.events; v_into public.events; v jsonb := '{}'; n integer; d integer;
begin
 select * into v_from from public.events where id = p_from for update;
 select * into v_into from public.events where id = p_into for update;
 if v_from.id is null or v_into.id is null or p_from = p_into or v_from.origin = 'community'
    or v_into.origin = 'community' or v_into.merged_into is not null then
  raise exception 'MERGE_REFUSED % -> %', p_from, p_into using errcode = '22023';
 end if;
 if v_from.merged_into = p_into then return v; end if;
 if v_from.merged_into is not null then
  raise exception 'MERGE_REFUSED % already merged into %', p_from, v_from.merged_into using errcode = '22023';
 end if;

 update public.saved_events x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.saved_events y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.saved_events where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('saved_events', n, 'saved_events_dup', d);

 update public.event_members x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_members y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.event_members where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_members', n, 'event_members_dup', d);

 update public.event_waitlist x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_waitlist y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.event_waitlist where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_waitlist', n, 'event_waitlist_dup', d);

 update public.event_ratings x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_ratings y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.event_ratings where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_ratings', n, 'event_ratings_dup', d);

 update public.event_messages set event_id = p_into where event_id = p_from;
 get diagnostics n = row_count;
 v := v || jsonb_build_object('event_messages', n);

 -- Прочитане — пізніша з двох позначок.
 update public.chat_reads y set read_at = greatest(y.read_at, x.read_at) from public.chat_reads x
 where y.event_id = p_into and x.event_id = p_from and x.user_id = y.user_id;
 update public.chat_reads x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.chat_reads y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.chat_reads where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('chat_reads', n, 'chat_reads_dup', d);

 update public.event_artists x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_artists y where y.event_id = p_into and y.artist_id = x.artist_id);
 get diagnostics n = row_count; delete from public.event_artists where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_artists', n, 'event_artists_dup', d);

 update private.follow_announced x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from private.follow_announced y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from private.follow_announced where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('follow_announced', n, 'follow_announced_dup', d);

 update private.follow_seen x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from private.follow_seen y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from private.follow_seen where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('follow_seen', n, 'follow_seen_dup', d);

 -- Супутники йдуть за подією. Другий збір того самого організатора на ту саму подію заборонено
 -- (events_companion_once_idx): такий лишається на надгробку й рахується окремо.
 update public.events c set companion_of = p_into where c.companion_of = p_from
  and not (c.status = 'published' and exists (select 1 from public.events o where o.companion_of = p_into
           and o.organizer_id = c.organizer_id and o.status = 'published'));
 get diagnostics n = row_count;
 v := v || jsonb_build_object('companions', n,
  'companions_kept', (select count(*) from public.events c where c.companion_of = p_from));

 update public.event_offers set event_id = p_into where event_id = p_from;
 get diagnostics n = row_count;
 v := v || jsonb_build_object('offers', n);
 update public.events set merged_into = p_into where merged_into = p_from;     -- без ланцюгів надгробків

 update public.events set description = v_from.description, updated_at = now()
 where id = p_into and description = '' and v_from.description <> '';
 update public.events set image_url = v_from.image_url where id = p_into and image_url is null and v_from.image_url is not null;
 update public.events set merged_into = p_into, import_status = 'withdrawn', updated_at = now() where id = p_from;
 perform private.sync_event(p_into);
 insert into private.event_merges (from_id, into_id, reason, moved) values (p_from, p_into, p_reason, v);
 return v;
end $$;

-- Ручне від'єднання (R1): пропозиція стає окремою подією, збереження лишаються на старій. linked='manual' заморожує
-- нову подію: наступні прогони її назад не приєднують (private.ingest_offers).
create or replace function private.detach_offer(p_offer uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_offer public.event_offers; v_event public.events; v_id uuid := gen_random_uuid();
begin
 select * into v_offer from public.event_offers where id = p_offer for update;
 if not found then raise exception 'OFFER_NOT_FOUND' using errcode = 'P0002'; end if;
 select * into v_event from public.events where id = v_offer.event_id for update;
 if (select count(*) from public.event_offers where event_id = v_event.id) < 2 then
  raise exception 'OFFER_ALONE: у події одна пропозиція' using errcode = '22023';
 end if;
 insert into public.events (id, organizer_id, title, description, category, city, address, latitude, longitude, place_id,
  starts_at, ends_at, time_zone, capacity, image_url, min_age, origin, source_id, source_uid, canonical_url, dedupe_key,
  quality, import_status, price_min, is_free, ingest_run_id)
 values (v_id, v_event.organizer_id, v_offer.title, v_event.description, v_event.category, v_event.city, v_event.address,
  v_event.latitude, v_event.longitude, v_event.place_id, v_offer.starts_at,
  v_offer.starts_at + (v_event.ends_at - v_event.starts_at), v_event.time_zone, null, v_event.image_url, v_event.min_age,
  v_event.origin, v_offer.source_id, v_offer.source_uid, v_offer.canonical_url, v_event.dedupe_key, v_event.quality,
  case when v_offer.status = 'live' then 'live' else 'withdrawn' end, v_offer.price_min, v_offer.is_free,
  v_offer.ingest_run_id);
 insert into public.event_artists (event_id, artist_id, role, position, how, confidence)
 select v_id, artist_id, role, position, how, confidence from public.event_artists where event_id = v_event.id;
 update public.event_offers set event_id = v_id, linked = 'manual', updated_at = now() where id = p_offer;
 return v_id;
end $$;

-- Запис пропозицій дампом (tools/ingest/emit.py). Рядок без `winner_slug` — переможець групи: подія = подія його
-- пропозиції → інакше подія будь-якої пропозиції групи (`members`) → інакше нова. Рядок з `winner_slug` — копія:
-- її пропозиція йде в подію переможця; якщо вона вже в іншій події, та подія зливається сюди. Заморожені події
-- (є manual-пропозиція) не зливаються й наявних пропозицій не приймають.
--
-- Вміст події (назва, час, місце) пише переможець групи, що містить основну пропозицію: час не скаче, коли
-- продавець, що не є основним, тихо переніс сеанс. Інші лише заповнюють порожній опис і обкладинку.
-- Вимкнене джерело (opt-out) не пишеться; ручне зняття пропозиції (withdrawn без run_id) upsert не скасовує.
create or replace function private.ingest_offers(p_run uuid, p_rows jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare
 r record; v_source uuid; v_offer public.event_offers; v_target uuid; v_event uuid; v_new boolean; v_writer boolean;
 n integer := 0;
begin
 for r in select * from jsonb_to_recordset(p_rows) as x(
  id uuid, slug text, uid text, url text, title text, description text, category text, city text, address text,
  lat float8, lon float8, starts timestamptz, ends timestamptz, tz text, image text, dedupe text, quality numeric,
  price numeric, free boolean, members jsonb, winner_slug text, winner_uid text, linked text)
 loop
  v_source := (select s.id from public.event_sources s where s.slug = r.slug and s.enabled);
  continue when v_source is null;
  v_offer := null; v_target := null; v_event := null; v_new := false;
  select * into v_offer from public.event_offers o where o.source_id = v_source and o.source_uid = r.uid;
  if r.winner_slug is not null then
   select o.event_id into v_target from public.event_offers o join public.event_sources s on s.id = o.source_id
   where s.slug = r.winner_slug and o.source_uid = r.winner_uid;
  end if;

  if v_offer.id is not null then
   v_event := v_offer.event_id;
   if v_target is not null and v_target <> v_event and v_offer.linked <> 'manual'
      and not private.event_frozen(v_target) then
    if private.event_frozen(v_event) then
     update public.event_offers set event_id = v_target, linked = coalesce(r.linked, 'rule'), updated_at = now()
     where id = v_offer.id;
    else
     perform private.merge_event(v_event, v_target, 'ingest:' || coalesce(r.linked, 'rule'));
     update public.event_offers set linked = coalesce(r.linked, 'rule') where id = v_offer.id;
    end if;
    v_event := v_target;
   end if;
  elsif v_target is not null then
   v_event := v_target;
  elsif r.winner_slug is not null then
   continue;                       -- переможця не записано (вимкнене джерело): копія без нього події не заводить
  elsif r.members is not null then
   select o.event_id into v_event
   from jsonb_to_recordset(r.members) m(slug text, uid text)
   join public.event_sources s on s.slug = m.slug
   join public.event_offers o on o.source_id = s.id and o.source_uid = m.uid
   join public.events e on e.id = o.event_id
   order by e.created_at, e.id limit 1;
  end if;

  if v_event is null then
   v_event := r.id;
   -- Обчислений id може носити інша подія: перенесений сеанс лишає старий id, а колишній ключ повертається.
   if v_event is null or exists (select 1 from public.events where id = v_event) then v_event := gen_random_uuid(); end if;
   insert into public.events (id, organizer_id, title, description, category, city, address, latitude, longitude,
    place_id, starts_at, ends_at, time_zone, capacity, image_url, origin, source_id, source_uid, canonical_url,
    dedupe_key, quality, import_status, price_min, is_free, ingest_run_id)
   select v_event, s.organizer_id, r.title, coalesce(r.description, ''), r.category, r.city, r.address, r.lat, r.lon,
    (select p.id from public.places p where p.latitude = r.lat and p.longitude = r.lon),
    r.starts, r.ends, r.tz,
    null,                          -- місткості в афіші немає (20260907150000)
    r.image, 'import', v_source, r.uid, r.url, r.dedupe, r.quality, 'live', r.price, r.free, p_run
   from public.event_sources s where s.id = v_source;
   v_new := true;
  end if;

  insert into public.event_offers as o (event_id, source_id, source_uid, canonical_url, title, starts_at, price_min,
   is_free, status, ingest_run_id, linked, seen_at)
  values (v_event, v_source, r.uid, r.url, r.title, r.starts, r.price, r.free, 'live', p_run, coalesce(r.linked, 'rule'),
   now())
  on conflict (source_id, source_uid) do update set
   canonical_url = excluded.canonical_url, title = excluded.title, starts_at = excluded.starts_at,
   price_min = excluded.price_min, is_free = excluded.is_free,
   status = case when o.status = 'withdrawn' and o.ingest_run_id is null then 'withdrawn' else 'live' end,
   ingest_run_id = case when o.status = 'withdrawn' and o.ingest_run_id is null then null else excluded.ingest_run_id end,
   seen_at = now(), updated_at = now();

  if not v_new and r.winner_slug is null then
   select (e.source_id = v_source and e.source_uid = r.uid)
       or exists (select 1 from jsonb_to_recordset(coalesce(r.members, '[]')) m(slug text, uid text)
                  join public.event_sources s on s.slug = m.slug where s.id = e.source_id and m.uid = e.source_uid)
   into v_writer from public.events e where e.id = v_event;
   if v_writer then
    update public.events e set title = r.title, description = coalesce(nullif(r.description, ''), e.description),
     category = r.category, city = r.city, address = r.address, latitude = r.lat, longitude = r.lon,
     place_id = (select p.id from public.places p where p.latitude = r.lat and p.longitude = r.lon),
     starts_at = r.starts, ends_at = r.ends, time_zone = r.tz, image_url = coalesce(r.image, e.image_url),
     dedupe_key = r.dedupe, quality = r.quality, updated_at = now()
    where e.id = v_event;
    perform private.sync_event(v_event);        -- перенесена завершена подія знову live
   else
    update public.events e set description = r.description, updated_at = now()
    where e.id = v_event and e.description = '' and coalesce(r.description, '') <> '';
    update public.events e set image_url = r.image where e.id = v_event and e.image_url is null and r.image is not null;
   end if;
  end if;
  n := n + 1;
 end loop;
 return n;
end $$;

revoke all on function private.title_key(text), private.live_event_id(uuid), private.event_frozen(uuid),
 private.sync_event(uuid), private.on_offer_changed(), private.merge_event(uuid, uuid, text),
 private.detach_offer(uuid), private.ingest_offers(uuid, jsonb) from public, anon, authenticated;
grant execute on function private.live_event_id(uuid) to anon, authenticated;

-- Старий id (пуш, нагадування, poriad.app/e/{id}) відкриває живу подію.
create or replace function public.event_details(p_event_id uuid)
returns setof public.event_result language sql stable set search_path='' as $$
 select * from private.event_rows(array[private.live_event_id(p_event_id)]);
$$;

-- Клієнт 1.3.0 бере заклад і артистів деталей з картки за тим самим id.
create or replace function public.event_cards_by_ids(p_ids uuid[])
returns jsonb language plpgsql stable set search_path='' as $$
begin
 if p_ids is null then return '[]'::jsonb; end if;
 if array_length(p_ids, 1) > 100 then raise exception 'TOO_MANY_IDS' using errcode='22023'; end if;
 return private.event_cards(array(select private.live_event_id(x) from unnest(p_ids) x));
end $$;

-- ───────────────────────────────────────────── перенесення наявних даних (R2)

-- Знятий рядок-дубль з живою копією стає пропозицією копії, сам рядок — надгробком. Пари, від найнадійнішої:
-- 1) рішення самого конвеєра (ingest_items, stage='duplicate' → candidate_event_id, останній запис копії);
-- 2) та сама хвилина, місто й назва;
-- 3) тихий перенос: той самий продавець і посилання, інша дата до 90 днів, стара ще в майбутньому, жива — одна.
-- Завжди в живий (чи завершений) рядок; ручне зняття (withdrawn без run_id) не чіпаємо.
do $$
declare p record; v_merged integer := 0;
begin
 for p in
  with imp as (select e.*, private.title_key(e.title) tk from public.events e where e.origin <> 'community'),
  a as (select distinct on (c.id) c.id copy_id, w.id winner_id from private.ingest_items i
   join imp c on c.source_id = i.source_id and c.source_uid = i.source_uid join imp w on w.id = i.candidate_event_id
   where i.stage = 'duplicate' and c.id <> w.id order by c.id, i.created_at desc),
  pa as (select case when w.import_status in ('live','stale') then c.id else w.id end from_id,
                case when w.import_status in ('live','stale') then w.id else c.id end into_id, 1 prio, 'migration:pipeline' why
   from a join imp c on c.id = a.copy_id join imp w on w.id = a.winner_id
   where (w.import_status in ('live','stale') and c.import_status = 'withdrawn' and c.ingest_run_id is not null)
      or (c.import_status in ('live','stale') and w.import_status = 'withdrawn' and w.ingest_run_id is not null)),
  pb as (select distinct on (d.id) d.id from_id, l.id into_id, 2 prio, 'migration:same_minute' why
   from imp d join imp l on l.city = d.city and l.starts_at = d.starts_at and l.tk = d.tk and l.id <> d.id
   join public.event_sources s on s.id = l.source_id
   where d.import_status = 'withdrawn' and d.ingest_run_id is not null and l.import_status in ('live','stale')
   order by d.id, s.weight desc, l.id),
  pc as (select d.id from_id, min(l.id::text)::uuid into_id, 3 prio, 'migration:silent_move' why
   from imp d join imp l on l.source_id = d.source_id and l.canonical_url = d.canonical_url and l.id <> d.id
    and l.import_status = 'live' and l.tk = d.tk and abs(extract(epoch from l.starts_at - d.starts_at)) <= 90 * 86400
   where d.import_status = 'withdrawn' and d.ingest_run_id is not null and d.starts_at > now()
   group by d.id having count(*) = 1)
  select distinct on (from_id) from_id, into_id, why
  from (select * from pa union all select * from pb union all select * from pc) u
  order by from_id, prio
 loop
  perform private.merge_event(p.from_id, p.into_id, p.why);
  v_merged := v_merged + 1;
 end loop;
 raise notice 'event_offers: злито % рядків', v_merged;
end $$;

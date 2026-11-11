-- Як потрапити на подію (docs/creation-platform-plan-2026-11.md, етап 1, п. 3; рішення власника 11.11). Досі подія від
-- людей — це кімната: місця, список, «Йду». Концерт у кафе чи вечір закладу так не живе: туди йдуть за квитком або
-- просто заходять. Тепер організатор обирає в кабінеті:
--   signup  — «Запис у „Поряд"», як було;
--   tickets — «Квитки за посиланням»: кнопка «Квитки» веде на сторінку продажу (`canonical_url`);
--   open    — «Вільний вхід, без запису».
-- Подія без запису лишається подією організатора (правка, скасування, заклад, артист, підписники), а клієнтам
-- віддається як оголошення: `origin = 'partner'`. Застосунки й сайт такий рядок уже показують як афішу — з кнопкою
-- «Квитки», «Зберегти» й «Шукаю компанію», без «Йду» й без місць (EventDto: кімната лише для `community`). Тому нової
-- збірки не треба. Місткості в такої події нема (null, як в афіші), записатись на неї не можна.

alter table public.events add column entry text not null default 'signup' check (entry in ('signup','tickets','open'));
alter table public.events drop constraint events_community_has_capacity_ck;
alter table public.events add constraint events_community_has_capacity_ck
 check (origin <> 'community' or capacity is not null or entry <> 'signup');
alter table public.events add constraint events_entry_ck check (
 entry = 'signup' or (origin = 'community' and companion_of is null and capacity is null and (entry <> 'tickets' or canonical_url is not null)));

-- Яким рядок бачить клієнт: подія без запису — оголошення.
create function private.shown_origin(p_origin text, p_entry text) returns text language sql immutable set search_path='' as $$
 select case when p_entry <> 'signup' then 'partner' else p_origin end;
$$;

-- Спосіб входу, посилання на квитки й місця — разом: кімната має місця, квитки мають https-адресу.
create function private.assert_entry(p_entry text, p_ticket_url text, p_capacity integer) returns void language plpgsql immutable set search_path='' as $$
begin
 if p_entry is null or p_entry not in ('signup','tickets','open') then raise exception 'INVALID_ENTRY' using errcode='22023'; end if;
 if p_entry = 'signup' and p_capacity is null then raise exception 'INVALID_CAPACITY' using errcode='22023'; end if;
 -- Довжина — окремо: лічильник повторів у регулярці Postgres не більший за 255.
 if p_entry = 'tickets' and (p_ticket_url is null or btrim(p_ticket_url) !~ '^https://[^[:space:]<>"]+$'
    or char_length(btrim(p_ticket_url)) not between 12 and 498) then
  raise exception 'INVALID_TICKET_URL' using errcode='22023'; end if;
end $$;
revoke all on function private.shown_origin(text,text), private.assert_entry(text,text,integer) from public, anon, authenticated;

-- ───────────────────────────────────────────── запис: на подію без запису — ні

-- Тіло — з 20261117120000, додано: entry.
create or replace function private.assert_can_join(p_user uuid,p_event public.events) returns void language plpgsql stable security definer set search_path='' as $$
declare v_age integer;
begin
 -- Подія без запису — оголошення, як афіша: клієнти вже знають цю відмову.
 if p_event.origin <> 'community' or p_event.entry <> 'signup' then raise exception 'IMPORTED_EVENT' using errcode='P0001'; end if;
 if not private.account_active(p_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.blocked_between(p_user,p_event.organizer_id) then raise exception 'BLOCKED' using errcode='42501'; end if;
 v_age := private.age_of(p_user);
 if v_age is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 if (p_event.min_age > private.min_signup_age() or p_event.max_age is not null)
  and (select f.birth_date from public.account_facts f where f.user_id=p_user) is null then
  raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 if v_age < p_event.min_age then raise exception 'TOO_YOUNG' using errcode='P0001'; end if;
 if p_event.max_age is not null and v_age > p_event.max_age then raise exception 'TOO_OLD' using errcode='P0001'; end if;
end $$;

-- ───────────────────────────────────────────── що бачить клієнт

-- Тіло — з 20261125190000, змінено: origin → shown_origin.
create or replace function private.event_rows(p_ids uuid[])
returns setof public.event_result language sql stable security definer set search_path='' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,
 coalesce(p.display_name, s.name),
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
 private.shown_origin(e.origin,e.entry),s.name,e.canonical_url,e.import_status,e.price_min,e.is_free,
 -- Чат — лише своїм: організатору й підтвердженим. Запит і черга ще не всередині.
 case when e.organizer_id=auth.uid()
       or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved')
      then e.contact_url end,
 e.companion_of,
 pe.title,
 cs.state, cs.previous_starts_at, cs.checked_at,
 case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end,
 -- R7а: питання до організатора збору бачать усі, кому видно збір (учасникам — «Організатор вирішує»).
 case when e.status = 'published' then d.proposed_at end,
 case when e.status = 'published' then d.decide_by end,
 pe.starts_at,
 e.media,
 -- Вимкнено (усім чи цьому організатору) — усі бачать «на місці»; правила повернення — лише в онлайн-події.
 e.pay_online and private.pay_online_allowed(e.organizer_id),
 case when e.pay_online and private.pay_online_allowed(e.organizer_id) then e.refund_policy end,
 -- Коли платять: передоплата чи на зустрічі. Онлайн-подія (навіть з вимкненим вимикачем) — теж передоплата.
 e.prepay or e.pay_online
 from public.events e
 left join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 left join public.events pe on pe.id=e.companion_of
 left join private.companion_decisions d on d.companion_id=e.id
 cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
 where e.id=any(p_ids) and private.has_event_access(e.id)
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$$;

-- Тіло — з 20261111120000, змінено: origin → shown_origin.
create or replace function private.event_cards(p_ids uuid[])
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(card order by starts_at, id), '[]'::jsonb) from (
  select e.starts_at, e.id, jsonb_strip_nulls(jsonb_build_object(
    'id', e.id, 'title', e.title, 'blurb', e.blurb, 'pitch', e.pitch, 'description', nullif(e.description,''), 'category', e.category,
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
    'origin', private.shown_origin(e.origin,e.entry), 'source_name', s.name, 'canonical_url', e.canonical_url,
    'import_status', e.import_status, 'price_min', e.price_min, 'is_free', e.is_free,
    'state', cs.state, 'previous_starts_at', cs.previous_starts_at, 'checked_at', cs.checked_at,
    'offers', case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end,
    'artists', (select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'kind', a.kind, 'role', ea.role)
                                 order by ea.position, a.name)
                from public.event_artists ea join public.artists a on a.id = ea.artist_id
                where ea.event_id = e.id))) as card
  from public.events e
  left join public.profiles p on p.id = e.organizer_id
  left join public.event_sources s on s.id = e.source_id
  left join public.places pl on pl.id = e.place_id
  cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
  where e.id = any(p_ids) and private.has_event_access(e.id)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
 ) t;
$$;

-- Тіло — з 20261115120000, змінено: origin → shown_origin; наміри «пішов би з компанією» — на все, що не кімната.
create or replace function private.discover_index(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text, p_from timestamptz, p_to timestamptz, p_text text, p_available boolean,
 p_limit integer, p_cards integer, p_cinema boolean)
returns table(index jsonb, total integer, truncated boolean, card_ids uuid[])
language sql stable security definer set search_path='' as $$
 with matched as (
  select e.id, e.starts_at, e.latitude, e.longitude, e.category, e.time_zone, e.title,
         private.shown_origin(e.origin, e.entry) as origin, e.capacity, e.source_id, e.place_id
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
     case when p.origin<>'community' then
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

-- ───────────────────────────────────────────── «Шукаю компанію» й «Пішов би з компанією» — і на подію без запису

-- Тіло — з 20261110120000, змінено: умова на подію, до якої шукають компанію.
create or replace function private.create_companion(p_parent_id uuid, p_meet_at timestamptz, p_meet_note text default null, p_capacity integer default 4) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_parent public.events; v_note text := nullif(btrim(p_meet_note),''); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 -- Той самий замок, що в create_event: ліміт на добу рахується без гонки.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 select * into v_parent from public.events where id=p_parent_id;
 if not found or v_parent.status <> 'published' or v_parent.starts_at <= now()
    or not ((v_parent.origin = 'import' and v_parent.import_status = 'live') or v_parent.entry <> 'signup') then
  raise exception 'COMPANION_UNAVAILABLE' using errcode='P0001'; end if;
 -- Повтор після непевної відповіді чи другий тап — той самий супутник, а не другий.
 select e.id into v_id from public.events e where e.companion_of=p_parent_id and e.organizer_id=v_user and e.status='published';
 if found then return v_id; end if;
 if p_meet_at is null or p_meet_at <= now() or p_meet_at > v_parent.starts_at or p_meet_at < v_parent.starts_at - interval '3 hours' then
  raise exception 'INVALID_MEET_TIME' using errcode='22023'; end if;
 if p_capacity is null or p_capacity not between 2 and 8 then raise exception 'INVALID_CAPACITY' using errcode='22023'; end if;
 if char_length(v_note) > 140 then raise exception 'INVALID_MEET_NOTE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_note);
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 return private.insert_companion(v_user, v_parent, p_meet_at, v_note, p_capacity);
end $$;

create or replace function private.company_event_ok(p_event uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.events e where e.id = p_event and e.status = 'published' and e.starts_at > now()
  and ((e.origin = 'import' and e.import_status = 'live') or e.entry <> 'signup')
  and private.is_listed(e.starts_at, e.ends_at, e.title) and private.is_discoverable(e.origin, e.import_status, e.quality));
$$;

-- ───────────────────────────────────────────── створення й правка

-- Старі сигнатури зникають: PostgREST не має вибирати між двома.
drop function public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean);
drop function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean);
drop function public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean);
drop function private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean);

-- Тіло — з 20261125190000, додано: p_entry, p_ticket_url. Без запису: місць, заявок, чату й оплати наперед нема.
create function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_via text default 'app', p_price integer default null, p_pay_online boolean default null, p_refund_policy text default null, p_prepay boolean default null, p_entry text default null, p_ticket_url text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events; v_media jsonb := coalesce(p_media,'[]'::jsonb);
 v_price integer := nullif(p_price,0); v_online boolean; v_entry text := coalesce(p_entry,'signup'); v_room boolean;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into v_existing from public.events where id=p_id for update;
 if found then
  if v_existing.organizer_id is distinct from v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
  return p_id;
 end if;
 if p_via not in ('app','web') then raise exception 'INVALID_VIA' using errcode='22023'; end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 perform private.assert_contact_url(p_contact_url);
 perform private.assert_image_url(p_image_url, v_user, p_id);
 perform private.assert_media(v_media, v_user, p_id);
 perform private.assert_price(p_price);
 perform private.assert_entry(v_entry, p_ticket_url, p_capacity);
 v_room := v_entry = 'signup';
 -- Місто й адреса теж показуються всім на мапі й картці — той самий стоп-словник.
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 if private.has_payment_details(concat_ws(' ', p_title, p_description, p_address, p_contact_url)) then
  raise exception 'PAYMENT_DETAILS' using errcode='22023'; end if;
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 v_online := v_room and coalesce(p_pay_online,false) and v_price is not null;
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required,contact_url,media,created_via,price_min,pay_online,refund_policy,prepay,entry,canonical_url,is_free)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,case when v_room then p_capacity end,
  case when p_media is null then p_image_url else private.media_cover(p_media,null) end,p_min_age,p_max_age,v_room and (p_approval_required or v_online),
  case when v_room then nullif(btrim(p_contact_url),'') end,v_media,p_via,v_price,v_online,case when v_online then p_refund_policy end,
  v_room and coalesce(p_prepay,false) and v_price is not null,
  v_entry, case when v_entry = 'tickets' then btrim(p_ticket_url) end, case when v_entry = 'open' then v_price is null end);
 return p_id;
end $$;

-- `p_entry = null` — «не чіпати», як `p_media` й `p_price`: старий клієнт способу входу не знає.
create function private.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_price integer default null, p_pay_online boolean default null, p_refund_policy text default null, p_prepay boolean default null, p_entry text default null, p_ticket_url text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events; v_price numeric; v_online boolean; v_entry text; v_room boolean; v_ticket text;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_existing from public.events where id=p_id for update;
 perform private.assert_organizer(v_existing, v_user);
 if v_existing.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 v_entry := coalesce(p_entry, v_existing.entry);
 v_room := v_entry = 'signup';
 v_ticket := coalesce(nullif(btrim(p_ticket_url),''), v_existing.canonical_url);
 perform private.assert_entry(v_entry, v_ticket, p_capacity);
 -- Спосіб входу міняється, поки ніхто не записався: список людей не зникає мовчки й не з'являється нізвідки.
 if v_entry <> v_existing.entry and (exists(select 1 from public.event_members where event_id=p_id)
   or exists(select 1 from public.event_waitlist where event_id=p_id) or exists(select 1 from public.events c where c.companion_of=p_id and c.status='published')
   or exists(select 1 from private.company_intents ci where ci.event_id=p_id)) then
  raise exception 'ENTRY_LOCKED' using errcode='P0001'; end if;
 if p_capacity < (select count(*) from public.event_members where event_id=p_id and status='approved') then raise exception 'CAPACITY_BELOW_ATTENDANCE' using errcode='P0001'; end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 perform private.assert_contact_url(p_contact_url);
 perform private.assert_image_url(p_image_url, v_user, p_id);
 perform private.assert_media(p_media, v_user, p_id);
 perform private.assert_price(p_price);
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 if private.has_payment_details(concat_ws(' ', p_title, p_description, p_address, p_contact_url)) then
  raise exception 'PAYMENT_DETAILS' using errcode='22023'; end if;
 v_price := case when p_price is null then v_existing.price_min else nullif(p_price,0) end;
 v_online := v_room and coalesce(p_pay_online, v_existing.pay_online) and v_price is not null;
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=case when v_room then p_capacity end,
 entry=v_entry, canonical_url=case when v_entry = 'tickets' then v_ticket end, is_free=case when v_entry = 'open' then v_price is null end,
 image_url=case when p_media is null then p_image_url else private.media_cover(p_media,null) end,
 media=coalesce(p_media,media),
 price_min=v_price, pay_online=v_online, refund_policy=case when v_online then coalesce(p_refund_policy, v_existing.refund_policy) end,
 prepay=v_room and coalesce(p_prepay, v_existing.prepay) and v_price is not null,
 min_age=p_min_age,max_age=p_max_age,approval_required=v_room and (p_approval_required or v_online),contact_url=case when v_room then nullif(btrim(p_contact_url),'') end,updated_at=now() where id=p_id;
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

create function public.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_via text default 'app',p_price integer default null,p_pay_online boolean default null,p_refund_policy text default null,p_prepay boolean default null,p_entry text default null,p_ticket_url text default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_via,p_price,p_pay_online,p_refund_policy,p_prepay,p_entry,p_ticket_url);
$$;

create function public.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_price integer default null,p_pay_online boolean default null,p_refund_policy text default null,p_prepay boolean default null,p_entry text default null,p_ticket_url text default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.update_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_price,p_pay_online,p_refund_policy,p_prepay,p_entry,p_ticket_url);
$$;

revoke all on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text), public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text), public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text)
 from public,anon,authenticated;
grant execute on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text), public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text), public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text)
 to authenticated;

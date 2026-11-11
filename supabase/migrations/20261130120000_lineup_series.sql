-- Склад і серія (docs/creation-platform-plan-2026-11.md, етап 1, п. 4 і 5).
--
-- Склад: організатор у кабінеті називає, хто виступає на його події, — артистів з каталогу чи нових. Подія з'являється
-- на сторінці артиста (`artist_events`) і чипами «Хто виступає» в картці. Пуш підписникам артиста, як і раніше, іде
-- лише про афішу з кас і про події самого артиста-власника (20261126120000): чужа подія підписників не будить.
-- Свого артиста (власник) подія несе й так, тригером; тут — решта, `how = 'lineup'`.
--
-- Серія: «щотижня» в кабінеті — це окремі події пачкою. Кабінет створює їх по одній (фото копіює, як «Повторити»),
-- а сервер: тримає їх разом (`series_id` — id першої), не рахує в денну стелю окремих подій (у серії до 12, за добу
-- до 40 на акаунт) і шле підписникам організатора один пуш — про першу.

alter table public.artists add column created_by uuid references public.profiles(id) on delete set null;
alter table public.events add column series_id uuid references public.events(id) on delete set null;
create index events_series_idx on public.events (series_id) where series_id is not null;

-- ───────────────────────────────────────────── склад

-- `p_artists` — id з каталогу, у порядку афіші; `p_new` — [{name, kind}] тих, кого в каталозі нема (з тим самим
-- ключем артист уже є — беремо його). Список замінює попередній склад від організатора; свого артиста не чіпає.
create function private.set_event_lineup(p_event uuid, p_artists uuid[], p_new jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_ids uuid[] := coalesce(p_artists, '{}'::uuid[]);
 v_item jsonb; v_name text; v_key text; v_kind text; v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 select * into v_event from public.events where id=p_event for update;
 perform private.assert_organizer(v_event, v_user);
 if v_event.companion_of is not null or jsonb_typeof(coalesce(p_new,'[]'::jsonb)) <> 'array' then
  raise exception 'INVALID_LINEUP' using errcode='22023'; end if;
 for v_item in select value from jsonb_array_elements(coalesce(p_new,'[]'::jsonb)) loop
  v_name := btrim(regexp_replace(coalesce(v_item->>'name',''), '\s+', ' ', 'g'));
  v_key := private.artist_key(v_name);
  v_kind := v_item->>'kind';
  if length(v_name) < 2 or length(v_name) > 120 or v_key = '' then raise exception 'INVALID_ARTIST_NAME' using errcode='22023'; end if;
  if v_kind is not null and v_kind not in ('person','group') then raise exception 'INVALID_ARTIST_KIND' using errcode='22023'; end if;
  perform private.assert_clean_text(v_name);
  select a.id into v_id from public.artists a where a.key = v_key;
  if v_id is null then
   -- Каталог спільний: нових — до десяти на добу з акаунта, і видно, хто додав.
   if (select count(*) from public.artists a where a.created_by = v_user and a.created_at > now()-interval '24 hours') >= 10 then
    raise exception 'TOO_MANY_ARTISTS' using errcode='P0001'; end if;
   insert into public.artists (name, key, kind, source, created_by) values (v_name, v_key, v_kind, 'manual', v_user) returning id into v_id;
  end if;
  v_ids := v_ids || v_id;
 end loop;
 -- Без повторів, у порядку першої появи.
 v_ids := coalesce((select array_agg(s.x order by s.n) from (select t.x, min(t.n) as n from unnest(v_ids) with ordinality t(x, n) group by t.x) s), '{}'::uuid[]);
 if coalesce(array_length(v_ids, 1), 0) > 8 then raise exception 'TOO_MANY_ARTISTS' using errcode='P0001'; end if;
 if exists (select 1 from unnest(v_ids) x where not exists (select 1 from public.artists a where a.id = x)) then
  raise exception 'ARTIST_NOT_FOUND' using errcode='P0001'; end if;
 delete from public.event_artists ea where ea.event_id = p_event and ea.how = 'lineup' and not (ea.artist_id = any(v_ids));
 insert into public.event_artists (event_id, artist_id, role, position, how, confidence)
 select p_event, t.x, 'headliner', t.n::smallint, 'lineup', 1 from unnest(v_ids) with ordinality t(x, n)
 on conflict (event_id, artist_id) do update set position = excluded.position where public.event_artists.how = 'lineup';
 return coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', a.id, 'name', a.name, 'kind', a.kind,
    'own', case when ea.how <> 'lineup' then true end)) order by ea.position, a.name)
  from public.event_artists ea join public.artists a on a.id = ea.artist_id where ea.event_id = p_event), '[]'::jsonb);
end $$;

create function public.set_event_lineup(p_event uuid, p_artists uuid[], p_new jsonb default '[]'::jsonb) returns jsonb
language sql set search_path='' as $$ select private.set_event_lineup(p_event, p_artists, p_new); $$;

revoke all on function private.set_event_lineup(uuid,uuid[],jsonb), public.set_event_lineup(uuid,uuid[],jsonb) from public, anon, authenticated;
grant execute on function private.set_event_lineup(uuid,uuid[],jsonb), public.set_event_lineup(uuid,uuid[],jsonb) to authenticated;

-- ───────────────────────────────────────────── серія

-- Пуш підписникам організатора — про першу подію серії; решта дат не будить людей одинадцять разів поспіль.
create or replace function private.on_event_published() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.series_id is not null and new.series_id <> new.id then return new; end if;
 perform private.notify_push(jsonb_build_object('type','follow','kind','organizer','event_id',new.id));
 return new;
end $$;

-- Стара сигнатура зникає: PostgREST не має вибирати між двома.
drop function public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text);
drop function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text);

-- Тіло — з 20261129120000, додано: p_series і стеля серії.
create function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_via text default 'app', p_price integer default null, p_pay_online boolean default null, p_refund_policy text default null, p_prepay boolean default null, p_entry text default null, p_ticket_url text default null, p_series uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events; v_media jsonb := coalesce(p_media,'[]'::jsonb);
 v_price integer := nullif(p_price,0); v_online boolean; v_entry text := coalesce(p_entry,'signup'); v_room boolean; v_head public.events;
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
 if p_series is null then
  -- Денна стеля рахує окремі події й перші події серій: решта серії йде за своєю стелею нижче.
  if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours'
      and (series_id is null or series_id = id)) >= 6 then
   raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 else
  -- Наступна подія серії: перша — своя звичайна подія; у серії до 12 подій, за добу — до 40 подій на акаунт.
  select * into v_head from public.events where id=p_series for update;
  if not found or v_head.organizer_id is distinct from v_user or v_head.origin <> 'community' or v_head.companion_of is not null
     or v_head.status <> 'published' or (v_head.series_id is not null and v_head.series_id <> v_head.id) then
   raise exception 'INVALID_SERIES' using errcode='22023'; end if;
  if (select count(*) from public.events where series_id=p_series or id=p_series) >= 12
     or (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 40 then
   raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
  update public.events set series_id=id where id=p_series and series_id is null;
 end if;
 v_online := v_room and coalesce(p_pay_online,false) and v_price is not null;
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required,contact_url,media,created_via,price_min,pay_online,refund_policy,prepay,entry,canonical_url,is_free,series_id)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,case when v_room then p_capacity end,
  case when p_media is null then p_image_url else private.media_cover(p_media,null) end,p_min_age,p_max_age,v_room and (p_approval_required or v_online),
  case when v_room then nullif(btrim(p_contact_url),'') end,v_media,p_via,v_price,v_online,case when v_online then p_refund_policy end,
  v_room and coalesce(p_prepay,false) and v_price is not null,
  v_entry, case when v_entry = 'tickets' then btrim(p_ticket_url) end, case when v_entry = 'open' then v_price is null end, p_series);
 return p_id;
end $$;

create function public.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_via text default 'app',p_price integer default null,p_pay_online boolean default null,p_refund_policy text default null,p_prepay boolean default null,p_entry text default null,p_ticket_url text default null,p_series uuid default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_via,p_price,p_pay_online,p_refund_policy,p_prepay,p_entry,p_ticket_url,p_series);
$$;

revoke all on function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid), public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid) from public,anon,authenticated;
grant execute on function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid), public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid) to authenticated;

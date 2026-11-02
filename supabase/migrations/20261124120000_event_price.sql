-- 1.5, «Ціна події» (docs/organizers-1.5.md, 1.7, власник 03.11): організатор вказує ціну входу — і все. Як оплатити,
-- людина домовляється з організатором сама: платформа нова, довіри до оплати через неї ще нема (режими оплати,
-- реквізити й квиток «Поряд» — у гілці paid-tickets). Ціна — у наявному `events.price_min`: його вже віддають картки,
-- стрічка, мапа й `event_details` (для афіші — ціна продавця «від», для події від людей — точна).
--
-- `p_price`: null — не чіпати (старий клієнт; у create_event — безкоштовно), 0 — безкоштовно, 1–100 000 — ціна в гривнях.

-- Старі сигнатури зникають: PostgREST не має вибирати між двома. Друга пара — з гілки paid-tickets, вона вже стоїть на dev.
drop function if exists public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text);
drop function if exists private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text);
drop function if exists public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb);
drop function if exists private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb);
drop function if exists public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,text,text,text);
drop function if exists private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,text,text,text);
drop function if exists public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,text,text,text);
drop function if exists private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,text,text,text);

create or replace function private.assert_price(p_price integer) returns void language plpgsql immutable set search_path='' as $$
begin
 if p_price is not null and p_price <> 0 and p_price not between 1 and 100000 then raise exception 'INVALID_PRICE' using errcode='22023'; end if;
end $$;
revoke all on function private.assert_price(integer) from public,anon,authenticated;

-- Тіло — з 20261118120000, додано: `p_price`.
create function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_via text default 'app', p_price integer default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events; v_media jsonb := coalesce(p_media,'[]'::jsonb);
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
 -- Місто й адреса теж показуються всім на мапі й картці — той самий стоп-словник.
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required,contact_url,media,created_via,price_min)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,
  case when p_media is null then p_image_url else private.media_cover(p_media,null) end,p_min_age,p_max_age,p_approval_required,nullif(btrim(p_contact_url),''),v_media,p_via,
  nullif(p_price,0));
 return p_id;
end $$;

-- Тіло — з 20261118120000, додано: `p_price` (null — ціну не чіпати).
create function private.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_price integer default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_existing from public.events where id=p_id for update;
 perform private.assert_organizer(v_existing, v_user);
 if v_existing.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
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
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=p_capacity,
 image_url=case when p_media is null then p_image_url else private.media_cover(p_media,null) end,
 media=coalesce(p_media,media),
 price_min=case when p_price is null then price_min else nullif(p_price,0) end,
 min_age=p_min_age,max_age=p_max_age,approval_required=p_approval_required,contact_url=nullif(btrim(p_contact_url),''),updated_at=now() where id=p_id;
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

create function public.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_via text default 'app',p_price integer default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_via,p_price);
$$;
create function public.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_price integer default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.update_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_price);
$$;
revoke all on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer),
 public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer),
 public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer)
 from public,anon,authenticated;
grant execute on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer),
 public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer),
 public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer)
 to authenticated;

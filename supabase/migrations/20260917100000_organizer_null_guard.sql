-- Аудит 2026-09-16, K1. Імпортовані події мають organizer_id = null (20260907130000), а перевірка
-- власника була `v.organizer_id <> v_user`: з NULL порівняння дає NULL, `if NULL` у PL/pgSQL не
-- піднімає виняток, і будь-який авторизований користувач редагував та скасовував усю афішу.
-- Одна перевірка в одному місці: працює з NULL і не пускає до імпортованих подій узагалі.

-- Заглушка фільтра тексту: справжня реалізація в 20260917100200_ugc_moderation.sql, а create_event /
-- update_event нижче вже на неї посилаються.
create or replace function private.assert_clean_text(p_text text) returns void
language plpgsql stable set search_path='' as $$ begin return; end $$;
revoke all on function private.assert_clean_text(text) from public, anon, authenticated;

create or replace function private.assert_organizer(p_event public.events, p_user uuid) returns void
language plpgsql immutable set search_path='' as $$
begin
 if p_event.id is null or p_user is null or p_event.organizer_id is distinct from p_user then
  raise exception 'NOT_ORGANIZER' using errcode='42501';
 end if;
 perform private.assert_event_editable(p_event);
end $$;
revoke all on function private.assert_organizer(public.events, uuid) from public, anon, authenticated;

create or replace function private.cancel_event(p_event_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_event public.events;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 perform private.assert_organizer(v_event, auth.uid());
 update public.events set status='cancelled',updated_at=now() where id=p_event_id;
end $$;

create or replace function private.decide_member(p_event_id uuid, p_user_id uuid, p_approve boolean) returns void
language plpgsql security definer set search_path='' as $$
declare v_event public.events;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 perform private.assert_organizer(v_event, auth.uid());
 if not p_approve then delete from public.event_members where event_id=p_event_id and user_id=p_user_id and status='requested'; return; end if;
 if not exists(select 1 from public.event_members where event_id=p_event_id and user_id=p_user_id and status='requested') then return; end if;
 if (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity then raise exception 'EVENT_FULL' using errcode='P0001'; end if;
 -- Правила перевіряються ще раз у момент прийняття: запит міг чекати з часів до підняття вікової межі.
 perform private.assert_can_join(p_user_id,v_event);
 update public.event_members set status='approved',joined_at=now() where event_id=p_event_id and user_id=p_user_id;
end $$;

create or replace function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 -- Повтори серіалізуємо за UUID клієнта, включно з запитами до появи рядка.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into v_existing from public.events where id=p_id for update;
 if found then
  -- Повтор із чужим (зокрема імпортованим, без організатора) id — не «свій» рядок.
  if v_existing.organizer_id is distinct from v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
  return p_id;
 end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 perform private.assert_contact_url(p_contact_url);
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 -- Більше шести подій на день з одного акаунта — скрипт, а не людина.
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required,contact_url)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,nullif(btrim(p_contact_url),''));
 return p_id;
end $$;

create or replace function private.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null) returns uuid
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
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=p_capacity,image_url=p_image_url,
 min_age=p_min_age,max_age=p_max_age,approval_required=p_approval_required,contact_url=nullif(btrim(p_contact_url),''),updated_at=now() where id=p_id;
 -- Підвищення вікової межі не виганяє вже прийнятих.
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

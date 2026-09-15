-- Poruch MVP. Публічні функції — invoker; привілейовані реалізації назовні не видно.
create schema if not exists private;
create schema if not exists gis;
create extension if not exists postgis with schema gis;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private, gis to anon, authenticated;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check (char_length(display_name) between 1 and 80),
 avatar_url text check (avatar_url is null or char_length(avatar_url) <= 2048)
);
create table public.user_preferences (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 categories text[] not null default '{}' check (categories <@ array['music','sport','art','food','games','outdoors','social']::text[]),
 reminders_enabled boolean not null default false
);
create table public.events (
 id uuid primary key,
 organizer_id uuid not null references public.profiles(id) on delete cascade,
 title text not null check (char_length(btrim(title)) between 3 and 120),
 description text not null check (char_length(description) <= 5000),
 category text not null check (category in ('music','sport','art','food','games','outdoors','social')),
 city text not null check (char_length(btrim(city)) between 1 and 160),
 address text not null check (char_length(btrim(address)) between 1 and 300),
 latitude double precision not null check (latitude between -90 and 90),
 longitude double precision not null check (longitude between -180 and 180),
 location gis.geography(Point,4326) generated always as (gis.st_setsrid(gis.st_makepoint(longitude,latitude),4326)::gis.geography) stored,
 starts_at timestamptz not null,
 ends_at timestamptz not null check (ends_at > starts_at),
 time_zone text not null,
 capacity integer not null check (capacity between 1 and 100000),
 status text not null default 'published' check (status in ('published','cancelled')),
 image_url text check (image_url is null or (image_url like 'https://%' and char_length(image_url) <= 2048)),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index events_location_idx on public.events using gist ((location::gis.geometry)) where status = 'published';
create index events_starts_idx on public.events(starts_at,id) where status = 'published';
create index events_category_starts_idx on public.events(category,starts_at) where status = 'published';
create index events_organizer_idx on public.events(organizer_id);
create table public.event_members (
 event_id uuid not null references public.events(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(),
 primary key (event_id,user_id)
);
create index event_members_user_idx on public.event_members(user_id,event_id);
create table public.saved_events (
 user_id uuid not null references public.profiles(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (user_id,event_id)
);
create index saved_events_event_idx on public.saved_events(event_id);

alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;
alter table public.events enable row level security;
alter table public.event_members enable row level security;
alter table public.saved_events enable row level security;

create function private.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,display_name) values (new.id,coalesce(nullif(left(btrim(new.raw_user_meta_data->>'display_name'),80),''),'Учасник'));
 insert into public.user_preferences(user_id) values (new.id);
 return new;
end $$;
revoke all on function private.handle_new_user() from public,anon,authenticated;
create trigger on_poruch_auth_user_created after insert on auth.users for each row execute function private.handle_new_user();

create function private.has_event_access(p_event_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.events e where e.id=p_event_id and
 (e.status='published' or (auth.uid() is not null and (e.organizer_id=auth.uid()
 or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid())
 or exists(select 1 from public.saved_events s where s.event_id=e.id and s.user_id=auth.uid())))));
$$;
create function private.can_view_members(p_event_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and (exists(select 1 from public.events e where e.id=p_event_id and e.organizer_id=auth.uid())
 or exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=auth.uid()));
$$;
revoke all on function private.has_event_access(uuid),private.can_view_members(uuid) from public,anon,authenticated;
grant execute on function private.has_event_access(uuid) to anon,authenticated;
grant execute on function private.can_view_members(uuid) to authenticated;

create policy profiles_read on public.profiles for select to anon,authenticated using (true);
create policy profiles_update on public.profiles for update to authenticated using (id=(select auth.uid())) with check (id=(select auth.uid()));
create policy preferences_owner on public.user_preferences for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy events_read on public.events for select to anon,authenticated using (private.has_event_access(id));
create policy members_read on public.event_members for select to authenticated using (private.can_view_members(event_id));
create policy saved_read on public.saved_events for select to authenticated using (user_id=(select auth.uid()));
create policy saved_insert on public.saved_events for insert to authenticated with check (user_id=(select auth.uid()) and private.has_event_access(event_id));
create policy saved_delete on public.saved_events for delete to authenticated using (user_id=(select auth.uid()));
revoke all on public.profiles,public.events,public.event_members,public.saved_events,public.user_preferences from anon,authenticated;
grant select on public.profiles,public.events to anon,authenticated;
grant update(display_name,avatar_url) on public.profiles to authenticated;
grant select on public.event_members to authenticated;
grant select,insert,delete on public.saved_events to authenticated;
grant select,insert,update,delete on public.user_preferences to authenticated;

create type public.event_result as (
 id uuid,title text,description text,category text,city text,address text,
 organizer_id uuid,organizer_name text,starts_at timestamptz,ends_at timestamptz,time_zone text,status text,
 latitude double precision,longitude double precision,capacity integer,attendee_count integer,joined boolean,image_url text
);
-- Лише ця проєкція під особою може агрегувати приховані записи учасників.
create function private.event_rows(p_ids uuid[]) returns setof public.event_result language sql stable security definer set search_path = '' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,p.display_name,
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),e.image_url
 from public.events e join public.profiles p on p.id=e.organizer_id where e.id=any(p_ids) and private.has_event_access(e.id);
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
revoke all on function public.event_details(uuid),public.events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz),public.my_events() from public,anon,authenticated;
grant execute on function public.event_details(uuid),public.events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz) to anon,authenticated;
grant execute on function public.my_events() to authenticated;

create function private.join_event(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_event public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if v_event.starts_at <= now() then raise exception 'EVENT_STARTED' using errcode='P0001'; end if;
 if v_event.organizer_id=v_user then raise exception 'ORGANIZER_CANNOT_JOIN' using errcode='P0001'; end if;
 if exists(select 1 from public.event_members where event_id=p_event_id and user_id=v_user) then return; end if;
 if (select count(*) from public.event_members where event_id=p_event_id) >= v_event.capacity then raise exception 'EVENT_FULL' using errcode='P0001'; end if;
 insert into public.event_members(event_id,user_id) values(p_event_id,v_user);
end $$;
create function private.leave_event(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform 1 from public.events where id=p_event_id for update;
 delete from public.event_members where event_id=p_event_id and user_id=auth.uid();
end $$;
create function private.cancel_event(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v_event public.events;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 if not found or v_event.organizer_id <> auth.uid() then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
 update public.events set status='cancelled',updated_at=now() where id=p_event_id;
end $$;
create function public.join_event(p_event_id uuid) returns void language sql security invoker set search_path = '' as $$ select private.join_event(p_event_id); $$;
create function public.leave_event(p_event_id uuid) returns void language sql security invoker set search_path = '' as $$ select private.leave_event(p_event_id); $$;
create function public.cancel_event(p_event_id uuid) returns void language sql security invoker set search_path = '' as $$ select private.cancel_event(p_event_id); $$;
revoke all on function private.join_event(uuid),private.leave_event(uuid),private.cancel_event(uuid),public.join_event(uuid),public.leave_event(uuid),public.cancel_event(uuid) from public,anon,authenticated;
grant execute on function private.join_event(uuid),private.leave_event(uuid),private.cancel_event(uuid),public.join_event(uuid),public.leave_event(uuid),public.cancel_event(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('event-images','event-images',true,5242880,array['image/jpeg','image/png','image/webp']);
create function private.owns_image_path(p_name text) returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and split_part(p_name,'/',1)=auth.uid()::text
 and exists(select 1 from public.events e where e.id::text=split_part(p_name,'/',2) and e.organizer_id=auth.uid());
$$;
revoke all on function private.owns_image_path(text) from public,anon,authenticated;
grant execute on function private.owns_image_path(text) to authenticated;
create policy poruch_image_read on storage.objects for select to anon,authenticated using (bucket_id='event-images');
create policy poruch_image_insert on storage.objects for insert to authenticated with check (bucket_id='event-images' and private.owns_image_path(name));
create policy poruch_image_update on storage.objects for update to authenticated using (bucket_id='event-images' and private.owns_image_path(name)) with check (bucket_id='event-images' and private.owns_image_path(name));
create policy poruch_image_delete on storage.objects for delete to authenticated using (bucket_id='event-images' and private.owns_image_path(name));

create function private.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_existing public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 -- Повтори серіалізуємо за UUID клієнта, включно з запитами до появи рядка.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into v_existing from public.events where id=p_id for update;
 if found then
  if v_existing.organizer_id <> v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
  return p_id;
 end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url);
 return p_id;
end $$;
create function public.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null) returns uuid language sql security invoker set search_path = '' as $$ select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url); $$;
revoke all on function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text),public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text) from public,anon,authenticated;
grant execute on function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text),public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text) to authenticated;

create function private.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_existing public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_existing from public.events where id=p_id for update;
 if not found or v_existing.organizer_id <> v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
 if v_existing.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if p_capacity < (select count(*) from public.event_members where event_id=p_id) then raise exception 'CAPACITY_BELOW_ATTENDANCE' using errcode='P0001'; end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=p_capacity,image_url=p_image_url,updated_at=now() where id=p_id;
 return p_id;
end $$;
create function public.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null) returns uuid language sql security invoker set search_path = '' as $$ select private.update_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url); $$;
revoke all on function private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text),public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text) from public,anon,authenticated;
grant execute on function private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text),public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text) to authenticated;

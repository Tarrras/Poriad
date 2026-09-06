-- Waiting list for full events. A full event used to be a dead end; now it holds a queue that is
-- promoted automatically the moment a place frees. The queue is private: each person reads only
-- their own row, so waiting for an event never becomes a public signal.
create table public.event_waitlist (
 event_id uuid not null references public.events(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (event_id,user_id)
);
create index event_waitlist_queue_idx on public.event_waitlist(event_id,created_at,user_id);
alter table public.event_waitlist enable row level security;
create policy waitlist_read on public.event_waitlist for select to authenticated using (user_id=(select auth.uid()));
revoke all on public.event_waitlist from anon,authenticated;
grant select on public.event_waitlist to authenticated;

-- Fills free places from the head of the queue. Every caller already holds the event row lock, so
-- promotion cannot race a concurrent join.
create function private.promote_waitlist(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v_capacity integer; v_next uuid;
begin
 select capacity into v_capacity from public.events where id=p_event_id and status='published';
 if v_capacity is null then return; end if;
 loop
  exit when (select count(*) from public.event_members where event_id=p_event_id) >= v_capacity;
  select user_id into v_next from public.event_waitlist where event_id=p_event_id order by created_at,user_id limit 1;
  exit when v_next is null;
  delete from public.event_waitlist where event_id=p_event_id and user_id=v_next;
  insert into public.event_members(event_id,user_id) values(p_event_id,v_next) on conflict do nothing;
 end loop;
end $$;

create function private.join_waitlist(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_event public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if v_event.starts_at <= now() then raise exception 'EVENT_STARTED' using errcode='P0001'; end if;
 if v_event.organizer_id=v_user then raise exception 'ORGANIZER_CANNOT_JOIN' using errcode='P0001'; end if;
 if exists(select 1 from public.event_members where event_id=p_event_id and user_id=v_user) then raise exception 'ALREADY_MEMBER' using errcode='P0001'; end if;
 -- Queueing for an event that still has room would strand the person behind a promotion that
 -- never runs, so the caller is told to join outright instead.
 if (select count(*) from public.event_members where event_id=p_event_id) < v_event.capacity then raise exception 'EVENT_HAS_SPACE' using errcode='P0001'; end if;
 insert into public.event_waitlist(event_id,user_id) values(p_event_id,v_user) on conflict do nothing;
end $$;

create function private.leave_waitlist(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform 1 from public.events where id=p_event_id for update;
 delete from public.event_waitlist where event_id=p_event_id and user_id=auth.uid();
end $$;

-- Leaving frees a place, so the queue advances in the same locked transaction.
create or replace function private.leave_event(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform 1 from public.events where id=p_event_id for update;
 delete from public.event_members where event_id=p_event_id and user_id=auth.uid();
 delete from public.event_waitlist where event_id=p_event_id and user_id=auth.uid();
 perform private.promote_waitlist(p_event_id);
end $$;

-- Joining outright supersedes any queue position the same person held.
create or replace function private.join_event(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
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
 delete from public.event_waitlist where event_id=p_event_id and user_id=v_user;
end $$;

-- Raising capacity is the other way places appear, so it advances the queue too.
create or replace function private.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null) returns uuid language plpgsql security definer set search_path = '' as $$
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
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

create function public.join_waitlist(p_event_id uuid) returns void language sql security invoker set search_path = '' as $$ select private.join_waitlist(p_event_id); $$;
create function public.leave_waitlist(p_event_id uuid) returns void language sql security invoker set search_path = '' as $$ select private.leave_waitlist(p_event_id); $$;
create function public.my_waitlist() returns setof uuid language sql stable security invoker set search_path = '' as $$
 select w.event_id from public.event_waitlist w where w.user_id=(select auth.uid()) order by w.created_at,w.event_id;
$$;

revoke all on function private.promote_waitlist(uuid),private.join_waitlist(uuid),private.leave_waitlist(uuid),
 public.join_waitlist(uuid),public.leave_waitlist(uuid),public.my_waitlist() from public,anon,authenticated;
grant execute on function public.join_waitlist(uuid),public.leave_waitlist(uuid),public.my_waitlist() to authenticated;

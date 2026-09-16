-- Аудит 2026-09-16, V3 / V6 / S3 / N3: чотири дрібні щілини для зловживань.

-- V3. join → leave → join у циклі давав необмежені пуші організатору. Журнал спроб і стеля
-- 20 приєднань на годину з акаунта — людині вистачить, скрипту ні.
create table if not exists private.join_attempts (
 user_id uuid not null, event_id uuid not null, created_at timestamptz not null default now()
);
create index if not exists join_attempts_user_time_idx on private.join_attempts(user_id, created_at);
revoke all on table private.join_attempts from public, anon, authenticated;

create or replace function private.assert_join_rate(p_user uuid, p_event uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if (select count(*) from private.join_attempts a where a.user_id=p_user and a.created_at > now()-interval '1 hour') >= 20 then
  raise exception 'TOO_MANY_JOINS' using errcode='P0001'; end if;
 insert into private.join_attempts(user_id,event_id) values (p_user,p_event);
 -- Журнал не росте вічно: старше доби нікому не потрібне.
 delete from private.join_attempts a where a.user_id=p_user and a.created_at < now()-interval '1 day';
end $$;
revoke all on function private.assert_join_rate(uuid,uuid) from public, anon, authenticated;

create or replace function private.join_event(p_event_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if v_event.starts_at <= now() then raise exception 'EVENT_STARTED' using errcode='P0001'; end if;
 if v_event.organizer_id=v_user then raise exception 'ORGANIZER_CANNOT_JOIN' using errcode='P0001'; end if;
 if exists(select 1 from public.event_members where event_id=p_event_id and user_id=v_user) then return; end if;
 perform private.assert_can_join(v_user,v_event);
 perform private.assert_join_rate(v_user,p_event_id);
 if v_event.approval_required then
  insert into public.event_members(event_id,user_id,status) values(p_event_id,v_user,'requested');
  delete from public.event_waitlist where event_id=p_event_id and user_id=v_user;
  return;
 end if;
 if (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity then raise exception 'EVENT_FULL' using errcode='P0001'; end if;
 insert into public.event_members(event_id,user_id,status) values(p_event_id,v_user,'approved');
 delete from public.event_waitlist where event_id=p_event_id and user_id=v_user;
end $$;

create or replace function private.join_waitlist(p_event_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if v_event.starts_at <= now() then raise exception 'EVENT_STARTED' using errcode='P0001'; end if;
 if v_event.organizer_id=v_user then raise exception 'ORGANIZER_CANNOT_JOIN' using errcode='P0001'; end if;
 if exists(select 1 from public.event_members where event_id=p_event_id and user_id=v_user) then raise exception 'ALREADY_MEMBER' using errcode='P0001'; end if;
 perform private.assert_can_join(v_user,v_event);
 if (select count(*) from public.event_members where event_id=p_event_id and status='approved') < v_event.capacity then raise exception 'EVENT_HAS_SPACE' using errcode='P0001'; end if;
 if not exists(select 1 from public.event_waitlist where event_id=p_event_id and user_id=v_user) then perform private.assert_join_rate(v_user,p_event_id); end if;
 insert into public.event_waitlist(event_id,user_id) values(p_event_id,v_user) on conflict do nothing;
end $$;

-- V6. Обкладинка спільнотної події — лише з нашого бакета: чужий URL дозволяв трекінг IP глядачів
-- і підміну картинки після модерації. Імпорт пише напряму, його це не стосується.
create or replace function private.assert_image_url(p_url text, p_user uuid, p_event uuid) returns void
language plpgsql stable set search_path='' as $$
begin
 if p_url is null then return; end if;
 if p_url !~ ('^https://[a-z0-9-]+\.supabase\.co/storage/v1/object/public/event-images/' || p_user::text || '/' || p_event::text || '/[^/?#[:space:]]+$') then
  raise exception 'INVALID_IMAGE_URL' using errcode='22023'; end if;
end $$;
revoke all on function private.assert_image_url(text,uuid,uuid) from public, anon, authenticated;
alter table public.profiles drop constraint if exists profiles_avatar_https_ck;
alter table public.profiles add constraint profiles_avatar_https_ck check (avatar_url is null or avatar_url like 'https://%');

create or replace function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into v_existing from public.events where id=p_id for update;
 if found then
  if v_existing.organizer_id is distinct from v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
  return p_id;
 end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 perform private.assert_contact_url(p_contact_url);
 perform private.assert_image_url(p_image_url, v_user, p_id);
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
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
 perform private.assert_image_url(p_image_url, v_user, p_id);
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=p_capacity,image_url=p_image_url,
 min_age=p_min_age,max_age=p_max_age,approval_required=p_approval_required,contact_url=nullif(btrim(p_contact_url),''),updated_at=now() where id=p_id;
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

-- S3. Скарга на повідомлення дедуплікується по самому повідомленню, а не по парі (подія, автор):
-- друга скарга на інше повідомлення того ж автора раніше губилась. Details не переповнює CHECK.
create or replace function public.report_message(p_message_id uuid, p_reason text, p_details text default null) returns uuid
language plpgsql set search_path='' as $$
declare v_message public.event_messages; v_id uuid;
begin
 select * into v_message from public.event_messages where id=p_message_id;
 if not found then raise exception 'MESSAGE_NOT_FOUND' using errcode='P0002'; end if;
 select id into v_id from public.reports where reporter_id=auth.uid() and message_id=p_message_id and status in ('new','reviewing');
 if v_id is not null then return v_id; end if;
 v_id := private.file_report('user',v_message.event_id,v_message.author_id,p_reason,
  left(concat_ws(E'\n',nullif(btrim(p_details),''),'Повідомлення: '||left(v_message.body,500)),2000));
 -- file_report міг повернути наявну скаргу на автора без message_id — привʼяжемо; якщо вже
 -- привʼязана до іншого повідомлення, подамо окрему, щоб модерація бачила обидва.
 if exists(select 1 from public.reports where id=v_id and message_id is not null and message_id<>p_message_id) then
  v_id := private.file_report_message(v_message.event_id,v_message.author_id,p_reason,
   left(concat_ws(E'\n',nullif(btrim(p_details),''),'Повідомлення: '||left(v_message.body,500)),2000));
 end if;
 perform private.attach_report_message(v_id,p_message_id);
 return v_id;
end $$;
create or replace function private.file_report_message(p_event uuid, p_user uuid, p_reason text, p_details text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if (select count(*) from public.reports where reporter_id=v_user and created_at > now()-interval '1 hour') >= 10 then
  raise exception 'TOO_MANY_REPORTS' using errcode='P0001'; end if;
 insert into public.reports(reporter_id,subject_type,event_id,subject_user_id,reason,details)
 values (v_user,'user',p_event,p_user,p_reason,p_details) returning id into v_id;
 return v_id;
end $$;
revoke all on function private.file_report_message(uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function private.file_report_message(uuid,uuid,text,text) to authenticated;

-- N3. Стеля на токени одного акаунта: десять пристроїв вистачить, решта — сміття або зловживання.
create or replace function private.register_push_token(p_token text, p_platform text) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_token is null or length(p_token) < 16 or length(p_token) > 4096 then raise exception 'INVALID_TOKEN' using errcode='22023'; end if;
 if p_platform not in ('android','ios') then raise exception 'INVALID_PLATFORM' using errcode='22023'; end if;
 insert into public.push_tokens(token,user_id,platform) values (p_token,v_user,p_platform)
 on conflict (token) do update set user_id=excluded.user_id,platform=excluded.platform,updated_at=now();
 delete from public.push_tokens t where t.user_id=v_user and t.token not in
  (select token from public.push_tokens where user_id=v_user order by updated_at desc limit 10);
end $$;

-- Безпека: вік, вікові межі подій, підтвердження участі, скарги, блокування, статус акаунта.
-- Усе перевіряється в базі, а не в застосунках: правила мають триматись і для клієнта, який
-- нашим застосунком не користується.

-- ---- Факти про акаунт. Окремо від `profiles`, бо ті читають усі, а дата народження — не публічна.
create table public.account_facts (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 -- Заявляється раз при реєстрації. На це спираються вікові правила й модерація.
 birth_date date check (birth_date is null or birth_date > date '1900-01-01'),
 status text not null default 'active' check (status in ('active','limited','banned')),
 status_note text check (status_note is null or char_length(status_note) <= 500),
 updated_at timestamptz not null default now()
);
alter table public.account_facts enable row level security;
create policy account_facts_owner on public.account_facts for select to authenticated using (user_id=(select auth.uid()));
revoke all on public.account_facts from anon,authenticated;
-- Власник лише читає: записи йдуть через definer-функції, щоб клієнт не міг зробити UPDATE.
grant select on public.account_facts to authenticated;
insert into public.account_facts(user_id) select id from public.profiles on conflict do nothing;

-- Мінімальний вік платформи в одному місці. Знизити — рішення політики з модерацією на додачу.
create function private.min_signup_age() returns integer language sql immutable set search_path='' as $$ select 18 $$;
create function private.age_years(p_birth date) returns integer language sql stable set search_path='' as $$
 select case when p_birth is null then null else extract(year from age(current_date,p_birth))::integer end;
$$;
create function private.age_of(p_user uuid) returns integer language sql stable security definer set search_path='' as $$
 select private.age_years(f.birth_date) from public.account_facts f where f.user_id=p_user;
$$;
create function private.account_active(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select f.status='active' from public.account_facts f where f.user_id=p_user),true);
$$;
revoke all on function private.min_signup_age(),private.age_years(date),private.age_of(uuid),private.account_active(uuid) from public,anon,authenticated;
grant execute on function private.age_of(uuid),private.account_active(uuid) to authenticated;
grant execute on function private.account_active(uuid) to anon;

-- Дата народження їде в метаданих реєстрації: перевіряється в транзакції створення акаунта.
create or replace function private.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_raw text := btrim(coalesce(new.raw_user_meta_data->>'birth_date','')); v_birth date;
begin
 if v_raw <> '' then
  begin v_birth := v_raw::date; exception when others then raise exception 'INVALID_BIRTH_DATE' using errcode='22023'; end;
  if v_birth > current_date then raise exception 'INVALID_BIRTH_DATE' using errcode='22023'; end if;
  if private.age_years(v_birth) < private.min_signup_age() then raise exception 'UNDERAGE' using errcode='P0001'; end if;
 end if;
 insert into public.profiles(id,display_name) values (new.id,coalesce(nullif(left(btrim(new.raw_user_meta_data->>'display_name'),80),''),'Учасник'));
 insert into public.user_preferences(user_id) values (new.id);
 insert into public.account_facts(user_id,birth_date) values (new.id,v_birth);
 return new;
end $$;

-- Старі акаунти без віку вказують його раз; далі зміна — дія модерації.
create function private.set_birth_date(p_birth date) returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_birth is null or p_birth > current_date then raise exception 'INVALID_BIRTH_DATE' using errcode='22023'; end if;
 if (select birth_date from public.account_facts where user_id=v_user) is not null then
  raise exception 'AGE_ALREADY_SET' using errcode='P0001'; end if;
 if private.age_years(p_birth) < private.min_signup_age() then raise exception 'UNDERAGE' using errcode='P0001'; end if;
 insert into public.account_facts(user_id,birth_date) values (v_user,p_birth)
 on conflict (user_id) do update set birth_date=excluded.birth_date,updated_at=now();
end $$;
create function public.set_birth_date(p_birth date) returns void language sql security invoker set search_path='' as $$ select private.set_birth_date(p_birth); $$;
revoke all on function private.set_birth_date(date),public.set_birth_date(date) from public,anon,authenticated;
grant execute on function private.set_birth_date(date),public.set_birth_date(date) to authenticated;

-- ---- Блокування. Симетричне навмисно: людина не має думати, в який бік воно діє.
create table public.user_blocks (
 user_id uuid not null references public.profiles(id) on delete cascade,
 blocked_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (user_id,blocked_id),
 check (user_id <> blocked_id)
);
create index user_blocks_blocked_idx on public.user_blocks(blocked_id);
alter table public.user_blocks enable row level security;
create policy blocks_owner on public.user_blocks for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
revoke all on public.user_blocks from anon,authenticated;
grant select,insert,delete on public.user_blocks to authenticated;

create function private.blocked_between(p_a uuid,p_b uuid) returns boolean language sql stable security definer set search_path='' as $$
 select p_a is not null and p_b is not null and exists(
  select 1 from public.user_blocks b
  where (b.user_id=p_a and b.blocked_id=p_b) or (b.user_id=p_b and b.blocked_id=p_a));
$$;
revoke all on function private.blocked_between(uuid,uuid) from public,anon,authenticated;
grant execute on function private.blocked_between(uuid,uuid) to anon,authenticated;

-- ---- Скарги

create table public.reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.profiles(id) on delete cascade,
 subject_type text not null check (subject_type in ('event','user')),
 event_id uuid references public.events(id) on delete set null,
 subject_user_id uuid references public.profiles(id) on delete set null,
 -- `minors` — окрема причина, щоб чергу можна було нею сортувати.
 reason text not null check (reason in ('minors','safety','harassment','scam','spam','other')),
 details text check (details is null or char_length(details) <= 2000),
 status text not null default 'new' check (status in ('new','reviewing','actioned','dismissed')),
 created_at timestamptz not null default now(),
 constraint reports_subject check (
  (subject_type='event' and event_id is not null) or (subject_type='user' and subject_user_id is not null))
);
create index reports_queue_idx on public.reports(status,reason,created_at);
create index reports_reporter_idx on public.reports(reporter_id,created_at);
alter table public.reports enable row level security;
-- Скаржник бачить лише свої скарги; модерація читає service role.
create policy reports_reporter on public.reports for select to authenticated using (reporter_id=(select auth.uid()));
revoke all on public.reports from anon,authenticated;
grant select on public.reports to authenticated;

create function private.file_report(p_type text,p_event uuid,p_user uuid,p_reason text,p_details text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_reason is null or p_reason not in ('minors','safety','harassment','scam','spam','other') then
  raise exception 'INVALID_REASON' using errcode='22023'; end if;
 if p_type='user' and p_user=v_user then raise exception 'CANNOT_REPORT_SELF' using errcode='P0001'; end if;
 -- Ліміт: скарга безкоштовна, і так чергу заливають, щоб сховати справжню.
 if (select count(*) from public.reports where reporter_id=v_user and created_at > now()-interval '1 hour') >= 10 then
  raise exception 'TOO_MANY_REPORTS' using errcode='P0001'; end if;
 -- Та сама скарга від тієї ж людини — одна, а не дві: не має виглядати як підтвердження.
 select id into v_id from public.reports
 where reporter_id=v_user and subject_type=p_type
 and event_id is not distinct from p_event and subject_user_id is not distinct from p_user
 and status in ('new','reviewing');
 if v_id is not null then return v_id; end if;
 insert into public.reports(reporter_id,subject_type,event_id,subject_user_id,reason,details)
 values (v_user,p_type,p_event,p_user,p_reason,nullif(btrim(p_details),''))
 returning id into v_id;
 return v_id;
end $$;
create function public.report_event(p_event_id uuid,p_reason text,p_details text default null) returns uuid language sql security invoker set search_path='' as $$
 select private.file_report('event',p_event_id,null,p_reason,p_details);
$$;
create function public.report_user(p_user_id uuid,p_reason text,p_details text default null) returns uuid language sql security invoker set search_path='' as $$
 select private.file_report('user',null,p_user_id,p_reason,p_details);
$$;
revoke all on function private.file_report(text,uuid,uuid,text,text),public.report_event(uuid,text,text),public.report_user(uuid,text,text) from public,anon,authenticated;
grant execute on function private.file_report(text,uuid,uuid,text,text),public.report_event(uuid,text,text),public.report_user(uuid,text,text) to authenticated;

-- ---- Події: вікові межі й підтвердження

alter table public.events
 add column min_age integer not null default 18 check (min_age between 0 and 100),
 add column max_age integer check (max_age is null or max_age between 0 and 120),
 add column approval_required boolean not null default false;
alter table public.events add constraint events_age_range check (max_age is null or max_age >= min_age);

-- Членство отримує статус: запит не займає місце, рахуються лише approved.
alter table public.event_members
 add column status text not null default 'approved' check (status in ('requested','approved'));
create index event_members_requests_idx on public.event_members(event_id,joined_at) where status='requested';

-- ---- Проєкції. Композитний тип отримує поля безпеки; залежні функції перебудовані нижче в тій же транзакції.
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
 min_age integer,max_age integer,approval_required boolean,membership text
);

-- Єдина проєкція, що агрегує приховані записи учасників. Тут же зникають заблокований
-- організатор і обмежений акаунт: одразу для мапи, деталей і «моїх подій».
create function private.event_rows(p_ids uuid[]) returns setof public.event_result language sql stable security definer set search_path = '' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,p.display_name,
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none')
 from public.events e join public.profiles p on p.id=e.organizer_id
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

-- Рахує лише approved: черга запитів не виглядає як повна подія.
create or replace function private.event_has_space(p_event_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.events e where e.id=p_event_id
 and private.has_event_access(e.id)
 and (select count(*) from public.event_members m where m.event_id=e.id and m.status='approved')<e.capacity);
$$;

create function public.search_events_in_view(p_south double precision,p_west double precision,p_north double precision,p_east double precision,p_category text default null,p_from timestamptz default null,p_to timestamptz default null,p_text text default null,p_available boolean default false)
 returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text)>120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and e.starts_at > now()
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

-- У списку лише підтверджені: запит — не учасник.
create or replace function private.can_view_members(p_event_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and (exists(select 1 from public.events e where e.id=p_event_id and e.organizer_id=auth.uid())
 or exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=auth.uid() and m.status='approved'));
$$;
create or replace function public.event_attendees(p_event_id uuid, p_limit integer default 24)
 returns setof public.attendee_result language sql stable security invoker set search_path = '' as $$
 select m.user_id, p.display_name, p.avatar_url, m.joined_at
 from public.event_members m join public.profiles p on p.id = m.user_id
 where m.event_id = p_event_id and m.status='approved'
 order by m.joined_at, m.user_id
 limit greatest(1, least(coalesce(p_limit, 24), 100));
$$;

-- ---- Приєднання. Усі причини відмови в одному місці; порядок важливий: найконкретніша перша,
-- і «заблоковано» не має витікати як «повно».
create function private.assert_can_join(p_user uuid,p_event public.events) returns void language plpgsql stable security definer set search_path='' as $$
declare v_age integer;
begin
 if not private.account_active(p_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.blocked_between(p_user,p_event.organizer_id) then raise exception 'BLOCKED' using errcode='42501'; end if;
 v_age := private.age_of(p_user);
 if v_age is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 if v_age < p_event.min_age then raise exception 'TOO_YOUNG' using errcode='P0001'; end if;
 if p_event.max_age is not null and v_age > p_event.max_age then raise exception 'TOO_OLD' using errcode='P0001'; end if;
end $$;
revoke all on function private.assert_can_join(uuid,public.events) from public,anon,authenticated;
grant execute on function private.assert_can_join(uuid,public.events) to authenticated;

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
 perform private.assert_can_join(v_user,v_event);
 -- Запит не займає місце, тому приймається й на повну подію: місткість перевіряється при схваленні.
 if v_event.approval_required then
  insert into public.event_members(event_id,user_id,status) values(p_event_id,v_user,'requested');
  delete from public.event_waitlist where event_id=p_event_id and user_id=v_user;
  return;
 end if;
 if (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity then raise exception 'EVENT_FULL' using errcode='P0001'; end if;
 insert into public.event_members(event_id,user_id,status) values(p_event_id,v_user,'approved');
 delete from public.event_waitlist where event_id=p_event_id and user_id=v_user;
end $$;

create or replace function private.join_waitlist(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_event public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if v_event.starts_at <= now() then raise exception 'EVENT_STARTED' using errcode='P0001'; end if;
 if v_event.organizer_id=v_user then raise exception 'ORGANIZER_CANNOT_JOIN' using errcode='P0001'; end if;
 if exists(select 1 from public.event_members where event_id=p_event_id and user_id=v_user) then raise exception 'ALREADY_MEMBER' using errcode='P0001'; end if;
 -- Черга — теж вхід, ті самі правила.
 perform private.assert_can_join(v_user,v_event);
 if (select count(*) from public.event_members where event_id=p_event_id and status='approved') < v_event.capacity then raise exception 'EVENT_HAS_SPACE' using errcode='P0001'; end if;
 insert into public.event_waitlist(event_id,user_id) values(p_event_id,v_user) on conflict do nothing;
end $$;

-- Просування — приєднання без присутності людини: перевіряє ті ж правила й пропускає тих, хто вже не проходить.
create or replace function private.promote_waitlist(p_event_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v_event public.events; v_next uuid; v_allowed boolean;
begin
 select * into v_event from public.events where id=p_event_id and status='published';
 if not found or v_event.approval_required then return; end if;
 loop
  exit when (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity;
  select user_id into v_next from public.event_waitlist where event_id=p_event_id order by created_at,user_id limit 1;
  exit when v_next is null;
  delete from public.event_waitlist where event_id=p_event_id and user_id=v_next;
  begin perform private.assert_can_join(v_next,v_event); v_allowed := true;
  exception when others then v_allowed := false; end;
  if v_allowed then insert into public.event_members(event_id,user_id,status) values(p_event_id,v_next,'approved') on conflict do nothing; end if;
 end loop;
end $$;

-- ---- Запити організатору. Замінено в 20260906200401: організатор читає своїх учасників під RLS.
create function public.event_requests(p_event_id uuid,p_limit integer default 50) returns setof public.attendee_result language sql stable security definer set search_path='' as $$
 select m.user_id,p.display_name,p.avatar_url,m.joined_at
 from public.event_members m join public.profiles p on p.id=m.user_id
 join public.events e on e.id=m.event_id
 where m.event_id=p_event_id and m.status='requested' and e.organizer_id=auth.uid()
 order by m.joined_at,m.user_id limit greatest(1,least(coalesce(p_limit,50),100));
$$;
create function private.decide_member(p_event_id uuid,p_user_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_event public.events;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 if not found or v_event.organizer_id <> auth.uid() then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
 if not p_approve then delete from public.event_members where event_id=p_event_id and user_id=p_user_id and status='requested'; return; end if;
 if not exists(select 1 from public.event_members where event_id=p_event_id and user_id=p_user_id and status='requested') then return; end if;
 if (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity then raise exception 'EVENT_FULL' using errcode='P0001'; end if;
 -- При схваленні правила перевіряються знову: запит міг лежати з часів до зміни вікової межі.
 perform private.assert_can_join(p_user_id,v_event);
 update public.event_members set status='approved',joined_at=now() where event_id=p_event_id and user_id=p_user_id;
end $$;
create function public.approve_member(p_event_id uuid,p_user_id uuid) returns void language sql security invoker set search_path='' as $$ select private.decide_member(p_event_id,p_user_id,true); $$;
create function public.decline_member(p_event_id uuid,p_user_id uuid) returns void language sql security invoker set search_path='' as $$ select private.decide_member(p_event_id,p_user_id,false); $$;
revoke all on function public.event_requests(uuid,integer),private.decide_member(uuid,uuid,boolean),public.approve_member(uuid,uuid),public.decline_member(uuid,uuid) from public,anon,authenticated;
grant execute on function public.event_requests(uuid,integer),private.decide_member(uuid,uuid,boolean),public.approve_member(uuid,uuid),public.decline_member(uuid,uuid) to authenticated;

-- ---- Створення й редагування

drop function public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text);
drop function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text);
drop function public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text);
drop function private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text);

-- Вікові межі організатора: не нижче за мінімум платформи, бо таких акаунтів не існує.
create function private.assert_age_limits(p_min integer,p_max integer) returns void language plpgsql immutable set search_path='' as $$
begin
 if p_min is null or p_min < private.min_signup_age() or p_min > 100 then raise exception 'INVALID_AGE_LIMIT' using errcode='22023'; end if;
 if p_max is not null and (p_max < p_min or p_max > 120) then raise exception 'INVALID_AGE_LIMIT' using errcode='22023'; end if;
end $$;
revoke all on function private.assert_age_limits(integer,integer) from public,anon,authenticated;
grant execute on function private.assert_age_limits(integer,integer) to authenticated;

create function private.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_existing public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 -- Повтори серіалізуємо за UUID клієнта, включно з запитами до появи рядка.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into v_existing from public.events where id=p_id for update;
 if found then
  if v_existing.organizer_id <> v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
  return p_id;
 end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 -- Більше шести подій на день з одного акаунта — скрипт, а не людина.
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required);
 return p_id;
end $$;

create function private.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_existing public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_existing from public.events where id=p_id for update;
 if not found or v_existing.organizer_id <> v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
 if v_existing.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if p_capacity < (select count(*) from public.event_members where event_id=p_id and status='approved') then raise exception 'CAPACITY_BELOW_ATTENDANCE' using errcode='P0001'; end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=p_capacity,image_url=p_image_url,
 min_age=p_min_age,max_age=p_max_age,approval_required=p_approval_required,updated_at=now() where id=p_id;
 -- Підвищення вікової межі не виганяє вже прийнятих.
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

create function public.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false) returns uuid language sql security invoker set search_path = '' as $$
 select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required);
$$;
create function public.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false) returns uuid language sql security invoker set search_path = '' as $$
 select private.update_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required);
$$;
revoke all on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean),
 public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean),
 public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean)
 from public,anon,authenticated;
grant execute on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean),
 public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean),
 public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean)
 to authenticated;

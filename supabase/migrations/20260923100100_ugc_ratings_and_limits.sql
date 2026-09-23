-- Аудит 2026-09-23, С1 / С2 / С3: коментарі до оцінок як UGC, автоприховування, гонки лімітів.

-- С1. Коментар до оцінки — такий самий UGC, як повідомлення: стоп-словник на вході, блокування
-- з організатором закриває оцінку, модерація може сховати коментар, організатор — поскаржитись.
alter table public.event_ratings add column if not exists comment_hidden_at timestamptz;
-- FK user_id → auth.users: каскад видалення акаунта без індексу сканував би всю таблицю.
create index if not exists event_ratings_user_idx on public.event_ratings(user_id);

create or replace function private.rate_event(p_event_id uuid, p_score integer, p_comment text default null) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_comment text := nullif(btrim(p_comment), '');
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_score is null or p_score not between 1 and 5 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 if char_length(v_comment) > 500 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 perform private.assert_clean_text(v_comment);
 select * into v_event from public.events where id=p_event_id;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if not exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=v_user and m.status='approved') then
  raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 -- Блокування в будь-який бік: коментар інакше став би каналом до того, хто заблокував.
 if private.blocked_between(v_user, v_event.organizer_id) then raise exception 'BLOCKED' using errcode='42501'; end if;
 if v_event.ends_at > now() or v_event.ends_at < now() - interval '14 days' then
  raise exception 'RATING_CLOSED' using errcode='P0001'; end if;
 -- Новий текст — новий розгляд: позначка прихованого з попереднього коментаря не переноситься.
 insert into public.event_ratings as r (event_id, user_id, score, comment) values (p_event_id, v_user, p_score, v_comment)
 on conflict (event_id, user_id) do update set score=excluded.score, comment=excluded.comment, updated_at=now(),
  comment_hidden_at = case when r.comment is not distinct from excluded.comment then r.comment_hidden_at end;
end $$;

-- Прихований модерацією коментар організатор не бачить; автор бачить свій як є.
create or replace function private.event_ratings(p_event_id uuid)
returns table(score smallint, comment text, created_at timestamptz, mine boolean)
language sql stable security definer set search_path='' as $$
 select r.score,
  case when r.user_id=auth.uid() or (r.comment_hidden_at is null and not private.blocked_between(auth.uid(), r.user_id)) then r.comment end,
  r.updated_at, r.user_id=auth.uid()
 from public.event_ratings r join public.events e on e.id=r.event_id
 where r.event_id=p_event_id and auth.uid() is not null and (e.organizer_id=auth.uid() or r.user_id=auth.uid())
 order by r.updated_at desc;
$$;

-- Скарга на коментар. Організатор бачить оцінки без імен, тож коментар ідентифікується так само,
-- як його показує event_ratings: подія + created_at рядка. Автор у скарзі — для модерації.
create or replace function private.report_rating(p_event_id uuid, p_created_at timestamptz, p_reason text, p_details text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_rating public.event_ratings;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select r.* into v_rating from public.event_ratings r join public.events e on e.id=r.event_id
 where r.event_id=p_event_id and r.updated_at=p_created_at and e.organizer_id=auth.uid() and r.comment is not null
 limit 1;
 if not found then raise exception 'RATING_NOT_FOUND' using errcode='P0002'; end if;
 return private.file_report('rating', p_event_id, v_rating.user_id, p_reason,
  left(concat_ws(E'\n', nullif(btrim(p_details),''), 'Коментар: '||v_rating.comment), 2000));
end $$;
create or replace function public.report_rating(p_event_id uuid, p_created_at timestamptz, p_reason text, p_details text default null) returns uuid
language sql security invoker set search_path='' as $$ select private.report_rating(p_event_id, p_created_at, p_reason, p_details); $$;

-- Модерація: сховати / повернути / стерти коментар. Рейтинг (бал) лишається.
create or replace function public.moderate_rating(p_event_id uuid, p_user_id uuid, p_action text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.assert_moderator();
 if p_action='hide' then update public.event_ratings set comment_hidden_at=now() where event_id=p_event_id and user_id=p_user_id and comment_hidden_at is null;
 elsif p_action='unhide' then update public.event_ratings set comment_hidden_at=null where event_id=p_event_id and user_id=p_user_id;
 elsif p_action='delete' then update public.event_ratings set comment=null, comment_hidden_at=null where event_id=p_event_id and user_id=p_user_id;
 else raise exception 'INVALID_ACTION' using errcode='22023'; end if;
end $$;

-- Черга модерації: для скарг на оцінку message_body несе сам коментар, message_hidden — чи він прихований.
create or replace function public.moderation_queue(p_limit integer default 50) returns setof public.moderation_item
language plpgsql stable security definer set search_path='' as $$
begin
 perform private.assert_moderator();
 return query
  select r.id, r.created_at, r.status, r.reason, r.details, r.subject_type,
   rp.display_name, e.id, e.title, e.status,
   su.id, su.display_name, coalesce(sf.status,'active'),
   m.id, coalesce(m.body, g.comment),
   case when g.event_id is not null then g.comment_hidden_at is not null else m.hidden_at is not null end
  from public.reports r
  left join public.profiles rp on rp.id=r.reporter_id
  left join public.events e on e.id=r.event_id
  left join public.profiles su on su.id=r.subject_user_id
  left join public.account_facts sf on sf.user_id=r.subject_user_id
  left join public.event_messages m on m.id=r.message_id
  left join public.event_ratings g on r.subject_type='rating' and g.event_id=r.event_id and g.user_id=r.subject_user_id
  where r.status in ('new','reviewing')
  order by r.created_at desc limit greatest(1, least(coalesce(p_limit,50), 200));
end $$;

revoke all on function private.rate_event(uuid,integer,text), private.event_ratings(uuid),
 private.report_rating(uuid,timestamptz,text,text), public.report_rating(uuid,timestamptz,text,text),
 public.moderate_rating(uuid,uuid,text), public.moderation_queue(integer) from public, anon, authenticated;
grant execute on function private.rate_event(uuid,integer,text), private.event_ratings(uuid),
 private.report_rating(uuid,timestamptz,text,text), public.report_rating(uuid,timestamptz,text,text),
 public.moderate_rating(uuid,uuid,text), public.moderation_queue(integer) to authenticated;

-- С2. Автоприховування: рахуються лише активні акаунти, старші за три дні. Три свіжі
-- реєстрації більше не ховають чужу (зокрема імпортовану) подію.
create or replace function private.on_report_filed() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
 if new.subject_type='event' and new.event_id is not null then
  select count(distinct r.reporter_id) into v_count from public.reports r join auth.users u on u.id=r.reporter_id
   where r.subject_type='event' and r.event_id=new.event_id and r.status in ('new','reviewing')
   and u.created_at <= now()-interval '3 days' and private.account_active(r.reporter_id);
  if v_count >= 3 then
   update public.events set status='hidden', updated_at=now() where id=new.event_id and status='published';
  end if;
 elsif new.message_id is not null then
  select count(distinct r.reporter_id) into v_count from public.reports r join auth.users u on u.id=r.reporter_id
   where r.message_id=new.message_id and r.status in ('new','reviewing')
   and u.created_at <= now()-interval '3 days' and private.account_active(r.reporter_id);
  if v_count >= 3 then
   update public.event_messages set hidden_at=now() where id=new.message_id and hidden_at is null;
  end if;
 end if;
 return new;
end $$;
-- Функція тригера: викликати напряму нікому не треба.
revoke execute on function private.on_report_filed() from public, anon, authenticated;

-- С3. «Порахував → вставив» під блокуванням на користувача: паралельні запити не обходять ліміт.
-- Той самий ключ, що в file_report / assert_join_rate (20260923100000).
create or replace function private.send_message(p_event_id uuid, p_body text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_body text := btrim(p_body); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 2000 then raise exception 'INVALID_MESSAGE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_body);
 select * into v_event from public.events where id=p_event_id;
 if not found or not private.can_view_members(p_event_id) then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 -- Запит без відповіді ще не всередині: can_view_members пускає його до ростера, але не до чату.
 if v_event.organizer_id is distinct from v_user and not exists(
  select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=v_user and m.status='approved') then
  raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 -- Тиждень після кінця — щоб домовитись про фото й речі; далі чат закривається.
 if v_event.ends_at < now() - interval '7 days' then raise exception 'CHAT_CLOSED' using errcode='P0001'; end if;
 -- Двадцять на хвилину — розмова; більше — скрипт. Видалені теж рахуються.
 if (select count(*) from public.event_messages where author_id=v_user and created_at > now()-interval '1 minute') >= 20 then
  raise exception 'TOO_MANY_MESSAGES' using errcode='P0001'; end if;
 insert into public.event_messages(event_id,author_id,body) values (p_event_id,v_user,v_body) returning id into v_id;
 return v_id;
end $$;

create or replace function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events;
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
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 perform private.assert_contact_url(p_contact_url);
 perform private.assert_image_url(p_image_url, v_user, p_id);
 -- Місто й адреса теж показуються всім на мапі й картці — той самий стоп-словник.
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
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
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=p_capacity,image_url=p_image_url,
 min_age=p_min_age,max_age=p_max_age,approval_required=p_approval_required,contact_url=nullif(btrim(p_contact_url),''),updated_at=now() where id=p_id;
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

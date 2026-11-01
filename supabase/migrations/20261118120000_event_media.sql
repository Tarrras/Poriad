-- 1.5, хвиля 1: фото й відео події, звідки її створено, і `via` у списках учасників (docs/organizers-1.5.md, 1.2–1.3).
-- Організатори з Threads показують минулі зустрічі фото й відео — тепер це частина події (до 5 файлів), а
-- `image_url` лишається обкладинкою: мапа, плитки, OG-картинка й старі застосунки беруть її, як і раніше.

-- ───── Схема
alter table public.events add column media jsonb not null default '[]'::jsonb;
alter table public.events add column created_via text not null default 'app' check (created_via in ('app','web'));

-- Відео — окремий бакет: інший тип і розмір, а правило шляху те саме, що для фото (`<uid>/<event>/<файл>`).
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('event-videos','event-videos',true,52428800,array['video/mp4']);
create policy poruch_video_insert on storage.objects for insert to authenticated
 with check (bucket_id='event-videos' and split_part(name,'/',2)<>'avatar' and private.owns_image_path(name));
create policy poruch_video_delete on storage.objects for delete to authenticated
 using (bucket_id='event-videos' and split_part(name,'/',2)<>'avatar' and private.owns_image_path(name));
-- Як 20260923100300: Storage читає щойно вставлений рядок, тож власнику — SELECT своїх файлів.
create policy poruch_video_owner_read on storage.objects for select to authenticated
 using (bucket_id='event-videos' and split_part(name,'/',1)=(select auth.uid())::text);

-- Як `image_url_prefix` (20260923100200), але для будь-якого нашого бакета.
create function private.storage_url_prefix(p_bucket text) returns text language sql stable set search_path='' as $$
 select '^' || coalesce(
  replace(substring(auth.jwt()->>'iss' from '^(https://[a-z0-9-]+\.supabase\.co)/auth/v1$'), '.', '\.'),
  'https://[a-z0-9-]+\.supabase\.co') || '/storage/v1/object/public/' || p_bucket || '/';
$$;
revoke all on function private.storage_url_prefix(text) from public,anon,authenticated;

-- До 5 файлів, лише з наших бакетів і лише з теки цієї події. Постер відео — JPEG у `event-images`.
create function private.assert_media(p_media jsonb, p_user uuid, p_event uuid) returns void language plpgsql stable set search_path='' as $$
declare v_item jsonb; v_folder text := p_user::text || '/' || p_event::text || '/[^/?#[:space:]]+$';
begin
 if p_media is null then return; end if;
 if jsonb_typeof(p_media) <> 'array' or jsonb_array_length(p_media) > 5 then raise exception 'INVALID_MEDIA' using errcode='22023'; end if;
 for v_item in select value from jsonb_array_elements(p_media) loop
  if jsonb_typeof(v_item) <> 'object' or jsonb_typeof(v_item->'url') <> 'string' then raise exception 'INVALID_MEDIA' using errcode='22023'; end if;
  if v_item->>'kind'='photo' then
   if v_item->>'url' !~ (private.storage_url_prefix('event-images') || v_folder) then raise exception 'INVALID_MEDIA' using errcode='22023'; end if;
  elsif v_item->>'kind'='video' then
   if v_item->>'url' !~ (private.storage_url_prefix('event-videos') || v_folder)
    or coalesce(v_item->>'poster','') !~ (private.storage_url_prefix('event-images') || v_folder) then
    raise exception 'INVALID_MEDIA' using errcode='22023'; end if;
  else raise exception 'INVALID_MEDIA' using errcode='22023'; end if;
 end loop;
end $$;
revoke all on function private.assert_media(jsonb,uuid,uuid) from public,anon,authenticated;

-- Обкладинка з медіа: перше фото, а якщо самі відео — постер першого. Порожній список — обкладинка як передали.
create function private.media_cover(p_media jsonb, p_image_url text) returns text language sql immutable set search_path='' as $$
 select coalesce(
  (select m->>'url' from jsonb_array_elements(p_media) with ordinality t(m,i) where m->>'kind'='photo' order by i limit 1),
  (select m->>'poster' from jsonb_array_elements(p_media) with ordinality t(m,i) where m->>'kind'='video' order by i limit 1),
  p_image_url);
$$;
revoke all on function private.media_cover(jsonb,text) from public,anon,authenticated;

-- ───── Створення й редагування. Старі сигнатури зникають: PostgREST не має вибирати між двома.
drop function public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text);
drop function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text);
drop function public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text);
drop function private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text);

-- Тіло — з 20260923100100, додано: `p_media` (null — старий клієнт, медіа не чіпаємо) і `p_via` (кабінет на вебі).
create function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_via text default 'app') returns uuid
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
 -- Місто й адреса теж показуються всім на мапі й картці — той самий стоп-словник.
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required,contact_url,media,created_via)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,
  private.media_cover(v_media,p_image_url),p_min_age,p_max_age,p_approval_required,nullif(btrim(p_contact_url),''),v_media,p_via);
 return p_id;
end $$;

-- Тіло — з 20260923100100, додано: `p_media` (null — медіа й обкладинка як передав старий клієнт).
create function private.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null) returns uuid
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
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=p_capacity,
 image_url=case when p_media is null then p_image_url else private.media_cover(p_media,p_image_url) end,
 media=coalesce(p_media,media),
 min_age=p_min_age,max_age=p_max_age,approval_required=p_approval_required,contact_url=nullif(btrim(p_contact_url),''),updated_at=now() where id=p_id;
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

create function public.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_via text default 'app') returns uuid language sql security invoker set search_path = '' as $$
 select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_via);
$$;
create function public.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.update_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media);
$$;
revoke all on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text),
 public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb),
 public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb)
 from public,anon,authenticated;
grant execute on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text),
 public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb),
 public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb)
 to authenticated;

-- ───── Клієнтам: медіа в деталях
alter type public.event_result add attribute media jsonb;

-- Тіло — з 20261029120000, додано: `e.media`.
create or replace function private.event_rows(p_ids uuid[])
returns setof public.event_result language sql stable security definer set search_path='' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,
 coalesce(p.display_name, s.name),
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
 e.origin,s.name,e.canonical_url,e.import_status,e.price_min,e.is_free,
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
 e.media
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

-- ───── Учасники: звідки записались (кабінет показує «застосунок» чи «веб»)
alter type public.attendee_result add attribute via text;

-- Тіло — з 20260906195750, додано: `m.via`.
create or replace function public.event_attendees(p_event_id uuid, p_limit integer default 24)
 returns setof public.attendee_result language sql stable security invoker set search_path = '' as $$
 select m.user_id, p.display_name, p.avatar_url, m.joined_at, m.via
 from public.event_members m join public.profiles p on p.id = m.user_id
 where m.event_id = p_event_id and m.status='approved'
 order by m.joined_at, m.user_id
 limit greatest(1, least(coalesce(p_limit, 24), 100));
$$;

-- Тіло — з 20260906200401, додано: `m.via`.
create or replace function public.event_requests(p_event_id uuid,p_limit integer default 50) returns setof public.attendee_result language sql stable security invoker set search_path='' as $$
 select m.user_id,p.display_name,p.avatar_url,m.joined_at,m.via
 from public.event_members m join public.profiles p on p.id=m.user_id
 join public.events e on e.id=m.event_id
 where m.event_id=p_event_id and m.status='requested' and e.organizer_id=auth.uid()
 order by m.joined_at,m.user_id limit greatest(1,least(coalesce(p_limit,50),100));
$$;

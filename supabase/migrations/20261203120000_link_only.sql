-- «Лише за посиланням» (docs/link-only-2026-11.md). Подію відкривають за посиланням і за id, а знайти її ніде не можна:
-- ні на мапі, ні в пошуку, ні на головній, сайті, у Telegram, на сторінках закладу й артиста, у «Ви стежите». Пушів про
-- неї теж нема: ні людям поруч, ні підписникам, ні winback. «Йдемо разом» до неї теж прихована.

alter table public.events add column link_only boolean not null default false;
-- Функції з security invoker (events_in_view, search_events_in_view) читають колонку правами аноніма.
grant select (link_only) on public.events to anon, authenticated;

-- ---- Спільний фільтр видачі

create function private.is_discoverable(p_origin text, p_import_status text, p_quality numeric, p_link_only boolean)
returns boolean language sql immutable set search_path='' as $$
 select not coalesce(p_link_only, false)
    and (p_origin = 'community' or (p_import_status = 'live' and coalesce(p_quality,0) >= 0.55));
$$;
revoke all on function private.is_discoverable(text,text,numeric,boolean) from public,anon,authenticated;
grant execute on function private.is_discoverable(text,text,numeric,boolean) to anon,authenticated;

-- Тринадцять функцій кличуть фільтр як is_discoverable(x.origin, x.import_status, x.quality): discover_index (обидві),
-- place_events, search_places, artist_events, search_artists, radar_events, popular_artists, send_winbacks,
-- notify_saved_companions, company_event_ok, events_in_view, search_events_in_view. Тіла не копіюємо: дописуємо
-- четвертий аргумент у їхні нинішні визначення. Кожна має змінитись; інакше — помилка, а не тихий витік.
do $$
declare f regprocedure; v_def text; v_new text; v_count integer := 0;
begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public','private') and p.prokind = 'f' and p.proname <> 'is_discoverable'
     and pg_get_functiondef(p.oid) like '%is_discoverable(%'
 loop
  v_def := pg_get_functiondef(f);
  v_new := regexp_replace(v_def, 'is_discoverable\((\w+)\.origin, ?\1\.import_status, ?\1\.quality\)',
                          'is_discoverable(\1.origin, \1.import_status, \1.quality, \1.link_only)', 'g');
  if v_new = v_def then raise exception 'link_only: % calls is_discoverable in an unexpected way', f; end if;
  execute v_new;
  v_count := v_count + 1;
 end loop;
 if v_count <> 13 then raise exception 'link_only: expected 13 callers of is_discoverable, got %', v_count; end if;
end $$;

-- «Ви стежите» й пуші підписникам: заклад і артист — через фільтр, гілка організатора — окремою умовою.
create or replace view private.followed_events as
 select f.user_id, f.target_kind, f.target_id, f.created_at as followed_at,
  e.id as event_id, e.title, e.created_at as event_created_at, e.starts_at, e.place_id
 from public.follows f
 join public.events e on e.place_id = f.target_id
 where f.target_kind = 'place' and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.is_discoverable(e.origin, e.import_status, e.quality, e.link_only)
  and (e.origin = 'import' and (e.category <> 'cinema' or private.cinema_shown(e.source_id))
   or e.origin = 'community' and e.companion_of is null
    and exists (select 1 from public.places p where p.id = e.place_id and p.owner_id = e.organizer_id)
    and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id)
    and not exists (select 1 from public.follows o where o.user_id = f.user_id and o.target_kind = 'organizer' and o.target_id = e.organizer_id))
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at as followed_at,
  e.id as event_id, e.title, e.created_at as event_created_at, e.starts_at, null::uuid as place_id
 from public.follows f
 join public.events e on e.organizer_id = f.target_id
 where f.target_kind = 'organizer' and e.origin = 'community' and e.companion_of is null and not e.link_only
  and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id)
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at as followed_at,
  e.id as event_id, e.title, e.created_at as event_created_at, e.starts_at, e.place_id
 from public.follows f
 join public.event_artists ea on ea.artist_id = f.target_id
 join public.events e on e.id = ea.event_id
 where f.target_kind = 'artist' and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.is_discoverable(e.origin, e.import_status, e.quality, e.link_only)
  and (e.origin = 'import'
   or e.origin = 'community' and e.companion_of is null
    and exists (select 1 from public.artists a where a.id = ea.artist_id and a.owner_id = e.organizer_id)
    and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id)
    and not exists (select 1 from public.follows o where o.user_id = f.user_id and o.target_kind = 'organizer' and o.target_id = e.organizer_id));

drop function private.is_discoverable(text, text, numeric);

-- ---- Точкові правки в нинішніх визначеннях: кожна заміна має знайти свій рядок.

create function pg_temp.rewrite(p_fn regprocedure, p_from text, p_to text) returns void language plpgsql as $$
declare v_def text := pg_get_functiondef(p_fn); v_new text := replace(v_def, p_from, p_to);
begin
 if v_new = v_def then raise exception 'link_only: % has no «%»', p_fn, p_from; end if;
 execute v_new;
end $$;

-- Пуш «Мої місця» людям у зоні.
select pg_temp.rewrite('private.notify_zone_devices()'::regprocedure,
 'where e.origin = ''community'' and e.status = ''published'' and e.starts_at > now()',
 'where e.origin = ''community'' and e.status = ''published'' and not e.link_only and e.starts_at > now()');

-- «Йдемо разом» до прихованої — теж прихована: її сторінка веде на батьківську («Разом на: …»).
select pg_temp.rewrite('private.insert_companion(uuid,public.events,timestamptz,text,integer)'::regprocedure,
 'capacity,min_age,approval_required,place_id,companion_of,meet_note)',
 'capacity,min_age,approval_required,place_id,companion_of,meet_note,link_only)');
select pg_temp.rewrite('private.insert_companion(uuid,public.events,timestamptz,text,integer)'::regprocedure,
 'p_capacity,18,true,p_parent.place_id,p_parent.id,p_note);',
 'p_capacity,18,true,p_parent.place_id,p_parent.id,p_note,p_parent.link_only);');

-- Деталі й «Мої події» кажуть організатору стан перемикача (і гостю — що подія за посиланням).
alter type public.event_result add attribute link_only boolean;
select pg_temp.rewrite('private.event_rows(uuid[])'::regprocedure,
 E' e.prepay or e.pay_online\n from public.events e',
 E' e.prepay or e.pay_online,\n e.link_only\n from public.events e');

-- ---- Пуш підписникам організатора про нову подію

drop trigger events_follow_push on public.events;
create trigger events_follow_push after insert on public.events for each row
 when (new.origin = 'community' and new.status = 'published' and new.companion_of is null and not new.link_only)
 execute function private.on_event_published();

-- ---- Читання таблиці напряму: приховані рядки — лише своїм

-- Свої: організатор, учасник чи заявка, черга, збережене. За id подію й далі відкриває has_event_access (event_rows).
create function private.event_insider(p_event_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and exists(select 1 from public.events e where e.id = p_event_id and (e.organizer_id = auth.uid()
  or exists(select 1 from public.event_members m where m.event_id = e.id and m.user_id = auth.uid())
  or exists(select 1 from public.event_waitlist w where w.event_id = e.id and w.user_id = auth.uid())
  or exists(select 1 from public.saved_events s where s.event_id = e.id and s.user_id = auth.uid())));
$$;
revoke all on function private.event_insider(uuid) from public, anon, authenticated;
grant execute on function private.event_insider(uuid) to anon, authenticated;

drop policy events_read on public.events;
create policy events_read on public.events for select to anon, authenticated
 using (private.has_event_access(id) and (not link_only or private.event_insider(id)));

-- ---- Створення й правка: новий параметр

drop function public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid);
drop function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid);
drop function public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text);
drop function private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text);

create function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text,
 p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text,
 p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null,
 p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_via text default 'app',
 p_price integer default null, p_pay_online boolean default null, p_refund_policy text default null, p_prepay boolean default null,
 p_entry text default null, p_ticket_url text default null, p_series uuid default null, p_link_only boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
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
 -- link_only — одним INSERT: тригер пушу підписникам бачить його вже в умові WHEN.
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required,contact_url,media,created_via,price_min,pay_online,refund_policy,prepay,entry,canonical_url,is_free,series_id,link_only)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,case when v_room then p_capacity end,
  case when p_media is null then p_image_url else private.media_cover(p_media,null) end,p_min_age,p_max_age,v_room and (p_approval_required or v_online),
  case when v_room then nullif(btrim(p_contact_url),'') end,v_media,p_via,v_price,v_online,case when v_online then p_refund_policy end,
  v_room and coalesce(p_prepay,false) and v_price is not null,
  v_entry, case when v_entry = 'tickets' then btrim(p_ticket_url) end, case when v_entry = 'open' then v_price is null end, p_series,
  coalesce(p_link_only,false));
 return p_id;
end $$;

create function public.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text,
 p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text,
 p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null,
 p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_via text default 'app',
 p_price integer default null, p_pay_online boolean default null, p_refund_policy text default null, p_prepay boolean default null,
 p_entry text default null, p_ticket_url text default null, p_series uuid default null, p_link_only boolean default false)
returns uuid language sql set search_path = '' as $$
 select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_via,p_price,p_pay_online,p_refund_policy,p_prepay,p_entry,p_ticket_url,p_series,p_link_only);
$$;

-- p_link_only null — «не міняти»: застосунки 1.4 і кабінет без нового поля не скидають вибір.
create function private.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text,
 p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text,
 p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null,
 p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null,
 p_price integer default null, p_pay_online boolean default null, p_refund_policy text default null, p_prepay boolean default null,
 p_entry text default null, p_ticket_url text default null, p_link_only boolean default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_existing public.events; v_price numeric; v_online boolean; v_entry text; v_room boolean; v_ticket text;
 v_link boolean;
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
 -- «Йдемо разом» не відкривається сама: її видимість — від батьківської події.
 v_link := case when v_existing.companion_of is not null then v_existing.link_only else coalesce(p_link_only, v_existing.link_only) end;
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=case when v_room then p_capacity end,
 entry=v_entry, canonical_url=case when v_entry = 'tickets' then v_ticket end, is_free=case when v_entry = 'open' then v_price is null end,
 image_url=case when p_media is null then p_image_url else private.media_cover(p_media,null) end,
 media=coalesce(p_media,media),
 price_min=v_price, pay_online=v_online, refund_policy=case when v_online then coalesce(p_refund_policy, v_existing.refund_policy) end,
 prepay=v_room and coalesce(p_prepay, v_existing.prepay) and v_price is not null,
 min_age=p_min_age,max_age=p_max_age,approval_required=v_room and (p_approval_required or v_online),contact_url=case when v_room then nullif(btrim(p_contact_url),'') end,
 link_only=v_link,updated_at=now() where id=p_id;
 update public.events set link_only=v_link where companion_of=p_id and link_only <> v_link;
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

create function public.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text,
 p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text,
 p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null,
 p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null,
 p_price integer default null, p_pay_online boolean default null, p_refund_policy text default null, p_prepay boolean default null,
 p_entry text default null, p_ticket_url text default null, p_link_only boolean default null)
returns uuid language sql set search_path = '' as $$
 select private.update_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_price,p_pay_online,p_refund_policy,p_prepay,p_entry,p_ticket_url,p_link_only);
$$;

revoke all on function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid,boolean) from public, anon, authenticated;
revoke all on function public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid,boolean) from public, anon, authenticated;
revoke all on function private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text,boolean) from public, anon, authenticated;
revoke all on function public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text,boolean) from public, anon, authenticated;
grant execute on function private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid,boolean) to authenticated;
grant execute on function public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text,boolean,text,text,uuid,boolean) to authenticated, service_role;
grant execute on function private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text,boolean) to authenticated;
grant execute on function public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text,boolean,text,text,boolean) to authenticated, service_role;

notify pgrst, 'reload schema';

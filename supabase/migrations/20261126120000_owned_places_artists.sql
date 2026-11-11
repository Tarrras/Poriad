-- Заклад і артист з власником (docs/creation-platform-plan-2026-11.md, етап 1, п. 1).
--
-- Кафе чи музикант створює подію в кабінеті як звичайний організатор. Досі така подія не потрапляла на заклад і
-- до артиста: «Ви стежите» й пуші брали для них лише афішу (`origin = 'import'`). Тепер:
--  * `places.owner_id`, `artists.owner_id` — акаунт, що веде заклад чи артиста. Ставить адміністратор
--    (`private.set_place_owner`, `private.set_artist_owner`): партнери приходять особисто, самообслуговування нема;
--  * подія власника в межах 150 м від його закладу сама отримує `place_id`, а кожна його подія — його артиста;
--  * такі події бачать ті, хто стежить за закладом чи артистом: у «Ви стежите», на головній і в пушах
--    (`notify_place_follows`, `notify_artist_follows` читають те саме зведення `private.followed_events`).
--
-- Чужа подія на тих самих координатах до підписників закладу не йде: інакше будь-хто писав би їм від імені закладу.
-- Хто стежить і за закладом, і за самим організатором, отримує подію раз — як подію організатора (пуш одразу).
-- Стеля: пуш радару гостя без акаунта (`notify_radar_devices`) лишився лише про афішу — розширимо, коли артисти
-- з власником з'являться не поодинці.

alter table public.places add column owner_id uuid references public.profiles(id) on delete set null;
alter table public.artists add column owner_id uuid references public.profiles(id) on delete set null;
create index places_owner_idx on public.places (owner_id) where owner_id is not null;
create index artists_owner_idx on public.artists (owner_id) where owner_id is not null;

-- Найближчий заклад власника в межах 150 м від точки: одна адреса — один заклад, подія деінде лишається без закладу.
create function private.owned_place(p_owner uuid, p_latitude double precision, p_longitude double precision) returns uuid
language sql stable security definer set search_path='' as $$
 select p.id from public.places p
 where p.owner_id = p_owner
  and gis.st_dwithin(p.location, gis.st_setsrid(gis.st_makepoint(p_longitude, p_latitude), 4326)::gis.geography, 150)
 order by gis.st_distance(p.location, gis.st_setsrid(gis.st_makepoint(p_longitude, p_latitude), 4326)::gis.geography), p.id
 limit 1;
$$;

-- Подія власника стає на його заклад; перенесли з закладу — знімається. Чужий `place_id` не чіпаємо.
create function private.attach_owned_place() returns trigger language plpgsql security definer set search_path='' as $$
declare v_place uuid := private.owned_place(new.organizer_id, new.latitude, new.longitude);
begin
 if v_place is not null then
  new.place_id := v_place;
 elsif new.place_id is not null
   and exists (select 1 from public.places p where p.id = new.place_id and p.owner_id = new.organizer_id) then
  new.place_id := null;
 end if;
 return new;
end $$;
create trigger events_owned_place before insert or update of latitude, longitude on public.events
 for each row when (new.origin = 'community' and new.companion_of is null and new.organizer_id is not null)
 execute function private.attach_owned_place();

-- Подія артиста-власника — з ним у складі.
create function private.attach_owned_artists() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.event_artists (event_id, artist_id, role, position, how, confidence)
 select new.id, a.id, 'headliner', 0, 'source', 1 from public.artists a where a.owner_id = new.organizer_id
 on conflict do nothing;
 return new;
end $$;
create trigger events_owned_artists after insert on public.events
 for each row when (new.origin = 'community' and new.companion_of is null and new.organizer_id is not null)
 execute function private.attach_owned_artists();

-- Адміністратор призначає власника (null — знімає) і підтягує його майбутні події. Повертає, скільки подій підтягнуто.
create function private.set_place_owner(p_place uuid, p_owner uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
 update public.places set owner_id = p_owner, updated_at = now() where id = p_place;
 if not found then raise exception 'PLACE_NOT_FOUND' using errcode='P0001'; end if;
 update public.events e set place_id = p_place
 where e.origin = 'community' and e.companion_of is null and e.organizer_id = p_owner and e.ends_at > now()
  and e.place_id is distinct from p_place
  and private.owned_place(p_owner, e.latitude, e.longitude) = p_place;
 get diagnostics v_count = row_count;
 return v_count;
end $$;

create function private.set_artist_owner(p_artist uuid, p_owner uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
 update public.artists set owner_id = p_owner, updated_at = now() where id = p_artist;
 if not found then raise exception 'ARTIST_NOT_FOUND' using errcode='P0001'; end if;
 insert into public.event_artists (event_id, artist_id, role, position, how, confidence)
 select e.id, p_artist, 'headliner', 0, 'source', 1 from public.events e
 where e.origin = 'community' and e.companion_of is null and e.organizer_id = p_owner and e.ends_at > now()
 on conflict do nothing;
 get diagnostics v_count = row_count;
 return v_count;
end $$;

revoke all on function private.owned_place(uuid,double precision,double precision), private.attach_owned_place(),
 private.attach_owned_artists(), private.set_place_owner(uuid,uuid), private.set_artist_owner(uuid,uuid)
 from public, anon, authenticated;

-- Тіло — з 20261115120000_cinema_switch; у гілках закладу й артиста додано події власника.
create or replace view private.followed_events as
 select f.user_id, f.target_kind, f.target_id, f.created_at as followed_at,
  e.id as event_id, e.title, e.created_at as event_created_at, e.starts_at, e.place_id
 from public.follows f
 join public.events e on e.place_id = f.target_id
 where f.target_kind = 'place' and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.is_discoverable(e.origin, e.import_status, e.quality)
  and (e.origin = 'import' and (e.category <> 'cinema' or private.cinema_shown(e.source_id))
   or e.origin = 'community' and e.companion_of is null
    and exists (select 1 from public.places p where p.id = e.place_id and p.owner_id = e.organizer_id)
    and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id)
    and not exists (select 1 from public.follows o
                    where o.user_id = f.user_id and o.target_kind = 'organizer' and o.target_id = e.organizer_id))
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at,
  e.id, e.title, e.created_at, e.starts_at, null::uuid
 from public.follows f
 join public.events e on e.organizer_id = f.target_id
 where f.target_kind = 'organizer' and e.origin = 'community' and e.companion_of is null
  and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id)
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at,
  e.id, e.title, e.created_at, e.starts_at, e.place_id
 from public.follows f
 join public.event_artists ea on ea.artist_id = f.target_id
 join public.events e on e.id = ea.event_id
 where f.target_kind = 'artist' and e.status = 'published' and private.is_listed(e.starts_at, e.ends_at, e.title)
  and private.is_discoverable(e.origin, e.import_status, e.quality)
  and (e.origin = 'import'
   or e.origin = 'community' and e.companion_of is null
    and exists (select 1 from public.artists a where a.id = ea.artist_id and a.owner_id = e.organizer_id)
    and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id)
    and not exists (select 1 from public.follows o
                    where o.user_id = f.user_id and o.target_kind = 'organizer' and o.target_id = e.organizer_id));

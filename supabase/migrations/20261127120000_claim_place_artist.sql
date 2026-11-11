-- «Мій заклад» і «Я артист» у кабінеті (docs/creation-platform-plan-2026-11.md, етап 1, п. 1; рішення власника 11.11:
-- організатор ставить їх сам, одразу, без підтвердження модератора). Над 20261126120000: там власника призначав
-- адміністратор, тут — сам організатор зі свого акаунта.
--
-- Запобіжники, бо перевірки нема:
--  * заклад чи артиста, в яких уже є власник, перехопити не можна (PLACE_TAKEN, ARTIST_TAKEN) — спір розв'язує
--    підтримка через private.set_place_owner / set_artist_owner;
--  * на акаунт — до трьох закладів і трьох артистів (TOO_MANY_CLAIMS);
--  * обмежений акаунт не може нічого назвати своїм; нова назва проходить той самий фільтр слів, що й назва події.
-- Стеля: першим назватися власником відомого закладу може будь-хто, і підписники закладу отримають його події.
-- Якщо таке станеться — повертаємо підтвердження модератором (заявка замість миттєвого призначення).

-- Ключ артиста — як `normalize_name` в імпорті (tools/ingest/normalize.py): регістр, лапки й пунктуація геть.
create function private.artist_key(p_name text) returns text language sql immutable set search_path='' as $$
 select btrim(regexp_replace(regexp_replace(lower(p_name), '[«»"''`ʼ’()\[\]{}.,:;!?/\\_—–-]', ' ', 'g'), '\s+', ' ', 'g'));
$$;

-- Хто питає й чи може: вхід, активний акаунт. Замок — щоб два запити поспіль не обійшли стелю.
create function private.claimer() returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('claim:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 return v_user;
end $$;

create function private.my_claims() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'places', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',p.id,'name',p.name,'city',p.city,'address',p.address,
    'latitude',p.latitude,'longitude',p.longitude)) order by p.name) from public.places p where p.owner_id = auth.uid()), '[]'::jsonb),
  'artists', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',a.id,'name',a.name,'kind',a.kind)) order by a.name)
    from public.artists a where a.owner_id = auth.uid()), '[]'::jsonb));
$$;

-- Пошук для вибору: усі заклади міста й усі артисти за назвою, а не лише ті, де є події. `taken` — уже чийсь.
create function private.find_places(p_text text, p_city text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text := nullif(btrim(p_text), '');
begin
 if q is null or length(q) < 2 then return '[]'::jsonb; end if;
 if length(q) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',t.id,'name',t.name,'city',t.city,'address',t.address,
   'taken', case when t.taken then true end)) order by t.rank, t.name)
  from (select p.id, p.name, p.city, p.address, p.owner_id is not null and p.owner_id <> auth.uid() as taken,
         case when lower(p.name) like lower(q) || '%' then 0 else 1 end as rank
        from public.places p
        where (p_city is null or p.city = p_city) and (p.name ilike '%' || q || '%' or p.name ilike '%' || private.search_translit(q) || '%')
        order by rank, p.name limit 8) t), '[]'::jsonb);
end $$;

create function private.find_artists(p_text text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text := nullif(btrim(p_text), '');
begin
 if q is null or length(q) < 2 then return '[]'::jsonb; end if;
 if length(q) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',t.id,'name',t.name,'kind',t.kind,
   'taken', case when t.taken then true end)) order by t.rank, t.name)
  from (select a.id, a.name, a.kind, a.owner_id is not null and a.owner_id <> auth.uid() as taken,
         case when lower(a.name) like lower(q) || '%' then 0 else 1 end as rank
        from public.artists a
        where a.name ilike '%' || q || '%' or a.name ilike '%' || private.search_translit(q) || '%'
        order by rank, a.name limit 8) t), '[]'::jsonb);
end $$;

create function private.claim_place(p_place uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer(); v_owner uuid;
begin
 select p.owner_id into v_owner from public.places p where p.id = p_place for update;
 if not found then raise exception 'PLACE_NOT_FOUND' using errcode='P0001'; end if;
 if v_owner is not null and v_owner <> v_user then raise exception 'PLACE_TAKEN' using errcode='P0001'; end if;
 if v_owner is null and (select count(*) from public.places p where p.owner_id = v_user) >= 3 then
  raise exception 'TOO_MANY_CLAIMS' using errcode='P0001';
 end if;
 perform private.set_place_owner(p_place, v_user);
 return private.my_claims();
end $$;

create function private.release_place(p_place uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer();
begin
 if exists (select 1 from public.places p where p.id = p_place and p.owner_id = v_user) then
  perform private.set_place_owner(p_place, null);
  -- Події більше не «заклад каже»: знімаємо їх із закладу, як зняв би переїзд.
  update public.events e set place_id = null
  where e.place_id = p_place and e.origin = 'community' and e.organizer_id = v_user and e.ends_at > now();
 end if;
 return private.my_claims();
end $$;

-- Закладу нема в списку: назва й точка (з підказок адрес кабінету). На тих самих координатах заклад уже є — беремо його.
create function private.add_my_place(p_name text, p_city text, p_address text, p_latitude double precision, p_longitude double precision)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer(); v_name text := btrim(coalesce(p_name,'')); v_place uuid;
begin
 if length(v_name) < 2 or length(v_name) > 120 then raise exception 'INVALID_PLACE_NAME' using errcode='22023'; end if;
 if p_latitude is null or p_longitude is null or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
   or nullif(btrim(coalesce(p_city,'')),'') is null then
  raise exception 'INVALID_PLACE' using errcode='22023';
 end if;
 perform private.assert_clean_text(v_name);
 select p.id into v_place from public.places p where p.latitude = p_latitude and p.longitude = p_longitude;
 if v_place is null then
  if (select count(*) from public.places p where p.owner_id = v_user) >= 3 then raise exception 'TOO_MANY_CLAIMS' using errcode='P0001'; end if;
  insert into public.places (name, city, address, latitude, longitude, source)
  values (v_name, btrim(p_city), nullif(btrim(coalesce(p_address,'')),''), p_latitude, p_longitude, 'manual')
  returning id into v_place;
 end if;
 return private.claim_place(v_place);
end $$;

create function private.claim_artist(p_artist uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer(); v_owner uuid;
begin
 select a.owner_id into v_owner from public.artists a where a.id = p_artist for update;
 if not found then raise exception 'ARTIST_NOT_FOUND' using errcode='P0001'; end if;
 if v_owner is not null and v_owner <> v_user then raise exception 'ARTIST_TAKEN' using errcode='P0001'; end if;
 if v_owner is null and (select count(*) from public.artists a where a.owner_id = v_user) >= 3 then
  raise exception 'TOO_MANY_CLAIMS' using errcode='P0001';
 end if;
 perform private.set_artist_owner(p_artist, v_user);
 return private.my_claims();
end $$;

create function private.release_artist(p_artist uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer();
begin
 if exists (select 1 from public.artists a where a.id = p_artist and a.owner_id = v_user) then
  perform private.set_artist_owner(p_artist, null);
  delete from public.event_artists ea using public.events e
  where ea.artist_id = p_artist and e.id = ea.event_id and e.origin = 'community' and e.organizer_id = v_user and e.ends_at > now();
 end if;
 return private.my_claims();
end $$;

-- Артиста нема в списку: ім'я й вид. З тим самим ключем артист уже є — беремо його.
create function private.add_my_artist(p_name text, p_kind text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer(); v_name text := btrim(regexp_replace(coalesce(p_name,''), '\s+', ' ', 'g'));
 v_key text := private.artist_key(v_name); v_artist uuid;
begin
 if length(v_name) < 2 or length(v_name) > 120 or v_key = '' then raise exception 'INVALID_ARTIST_NAME' using errcode='22023'; end if;
 if p_kind is not null and p_kind not in ('person','group') then raise exception 'INVALID_ARTIST_KIND' using errcode='22023'; end if;
 perform private.assert_clean_text(v_name);
 select a.id into v_artist from public.artists a where a.key = v_key;
 if v_artist is null then
  if (select count(*) from public.artists a where a.owner_id = v_user) >= 3 then raise exception 'TOO_MANY_CLAIMS' using errcode='P0001'; end if;
  insert into public.artists (name, key, kind, source) values (v_name, v_key, p_kind, 'manual') returning id into v_artist;
 end if;
 return private.claim_artist(v_artist);
end $$;

create function public.my_claims() returns jsonb language sql stable set search_path='' as $$ select private.my_claims(); $$;
create function public.find_places(p_text text, p_city text default null) returns jsonb language sql stable set search_path='' as $$ select private.find_places(p_text, p_city); $$;
create function public.find_artists(p_text text) returns jsonb language sql stable set search_path='' as $$ select private.find_artists(p_text); $$;
create function public.claim_place(p_place uuid) returns jsonb language sql set search_path='' as $$ select private.claim_place(p_place); $$;
create function public.release_place(p_place uuid) returns jsonb language sql set search_path='' as $$ select private.release_place(p_place); $$;
create function public.add_my_place(p_name text, p_city text, p_address text, p_latitude double precision, p_longitude double precision)
returns jsonb language sql set search_path='' as $$ select private.add_my_place(p_name, p_city, p_address, p_latitude, p_longitude); $$;
create function public.claim_artist(p_artist uuid) returns jsonb language sql set search_path='' as $$ select private.claim_artist(p_artist); $$;
create function public.release_artist(p_artist uuid) returns jsonb language sql set search_path='' as $$ select private.release_artist(p_artist); $$;
create function public.add_my_artist(p_name text, p_kind text default null) returns jsonb language sql set search_path='' as $$ select private.add_my_artist(p_name, p_kind); $$;

revoke all on function private.artist_key(text), private.claimer(), private.my_claims(), private.find_places(text,text), private.find_artists(text),
 private.claim_place(uuid), private.release_place(uuid), private.add_my_place(text,text,text,double precision,double precision),
 private.claim_artist(uuid), private.release_artist(uuid), private.add_my_artist(text,text),
 public.my_claims(), public.find_places(text,text), public.find_artists(text), public.claim_place(uuid), public.release_place(uuid),
 public.add_my_place(text,text,text,double precision,double precision), public.claim_artist(uuid), public.release_artist(uuid),
 public.add_my_artist(text,text) from public, anon, authenticated;
grant execute on function private.my_claims(), private.find_places(text,text), private.find_artists(text),
 private.claim_place(uuid), private.release_place(uuid), private.add_my_place(text,text,text,double precision,double precision),
 private.claim_artist(uuid), private.release_artist(uuid), private.add_my_artist(text,text),
 public.my_claims(), public.find_places(text,text), public.find_artists(text), public.claim_place(uuid), public.release_place(uuid),
 public.add_my_place(text,text,text,double precision,double precision), public.claim_artist(uuid), public.release_artist(uuid),
 public.add_my_artist(text,text) to authenticated;

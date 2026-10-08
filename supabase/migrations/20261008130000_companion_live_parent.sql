-- Супутник («Шукаю компанію») — лише до живої імпортованої події.
--
-- Було (аудит 2026-10-08): `create_companion` перевіряв `status`, але не `import_status`, тож сервер приймав
-- супутника до знятої з афіші події (скасованої, дубля, зниклої); бракувало лише перевірки `canOffer` у клієнті.
-- Права й обгортка `public.create_companion` не змінюються.

create or replace function private.create_companion(p_parent_id uuid, p_meet_at timestamptz, p_meet_note text default null, p_capacity integer default 4) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_parent public.events; v_note text := nullif(btrim(p_meet_note),''); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 -- Той самий замок, що в create_event: ліміт на добу рахується без гонки.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 select * into v_parent from public.events where id=p_parent_id;
 if not found or v_parent.origin <> 'import' or v_parent.status <> 'published' or v_parent.import_status is distinct from 'live'
    or v_parent.starts_at <= now() then
  raise exception 'COMPANION_UNAVAILABLE' using errcode='P0001'; end if;
 -- Повтор після непевної відповіді чи другий тап — той самий супутник, а не другий.
 select e.id into v_id from public.events e where e.companion_of=p_parent_id and e.organizer_id=v_user and e.status='published';
 if found then return v_id; end if;
 if p_meet_at is null or p_meet_at <= now() or p_meet_at > v_parent.starts_at or p_meet_at < v_parent.starts_at - interval '3 hours' then
  raise exception 'INVALID_MEET_TIME' using errcode='22023'; end if;
 if p_capacity is null or p_capacity not between 2 and 8 then raise exception 'INVALID_CAPACITY' using errcode='22023'; end if;
 if char_length(v_note) > 140 then raise exception 'INVALID_MEET_NOTE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_note);
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 v_id := pg_catalog.gen_random_uuid();
 -- Назву й опис складаємо тут: людина пише лише примітку. Місце, категорія й пояс — батьківські.
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
  capacity,min_age,approval_required,place_id,companion_of,meet_note)
 values(v_id,v_user,btrim(left('Йдемо разом: '||v_parent.title,120)),
  left('Йдемо разом на «'||v_parent.title||'».'||coalesce(' Збір: '||v_note,''),5000),
  v_parent.category,v_parent.city,v_parent.address,v_parent.latitude,v_parent.longitude,p_meet_at,v_parent.ends_at,v_parent.time_zone,
  p_capacity,18,true,v_parent.place_id,p_parent_id,v_note);
 return v_id;
end $$;

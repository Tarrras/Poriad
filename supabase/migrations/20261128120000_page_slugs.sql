-- Коротка адреса сторінки закладу й артиста: poriad.app/p/malevych замість id (docs/creation-platform-plan-2026-11.md,
-- етап 1, п. 2). Ставить власник у кабінеті; воркер шукає рядок за `slug`, якщо в адресі не UUID.
--  * 3–32 символи: латинка, цифри, дефіс усередині. UUID (36 символів) у ці межі не влазить, тож з id не сплутати.
--  * Унікальна серед закладів і окремо серед артистів: /p/ і /a/ — різні простори.
--  * Власника зняли (відмова, підтримка, видалений акаунт) — адреса звільняється: тригер, один на всі шляхи.
-- Стеля, як і з власником: гарну адресу бере той, хто перший. Спір розв'язує підтримка.

alter table public.places add column slug text unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$');
alter table public.artists add column slug text unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$');

create function private.drop_slug_without_owner() returns trigger language plpgsql set search_path='' as $$
begin
 if new.owner_id is null then new.slug := null; end if;
 return new;
end $$;
create trigger places_slug_owner before update of owner_id on public.places
 for each row execute function private.drop_slug_without_owner();
create trigger artists_slug_owner before update of owner_id on public.artists
 for each row execute function private.drop_slug_without_owner();

-- Свої заклади й артисти тепер з адресою сторінки.
create or replace function private.my_claims() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'places', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',p.id,'name',p.name,'city',p.city,'address',p.address,
    'latitude',p.latitude,'longitude',p.longitude,'slug',p.slug)) order by p.name) from public.places p where p.owner_id = auth.uid()), '[]'::jsonb),
  'artists', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',a.id,'name',a.name,'kind',a.kind,'slug',a.slug)) order by a.name)
    from public.artists a where a.owner_id = auth.uid()), '[]'::jsonb));
$$;

-- Порожній рядок прибирає адресу. Чужий заклад — «не знайдено», як і неіснуючий.
create function private.set_place_slug(p_place uuid, p_slug text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer(); v_slug text := nullif(lower(btrim(coalesce(p_slug,''))), '');
begin
 if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$' then raise exception 'INVALID_SLUG' using errcode='22023'; end if;
 begin
  update public.places set slug = v_slug, updated_at = now() where id = p_place and owner_id = v_user;
  if not found then raise exception 'PLACE_NOT_FOUND' using errcode='P0001'; end if;
 exception when unique_violation then raise exception 'SLUG_TAKEN' using errcode='P0001';
 end;
 return private.my_claims();
end $$;

create function private.set_artist_slug(p_artist uuid, p_slug text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer(); v_slug text := nullif(lower(btrim(coalesce(p_slug,''))), '');
begin
 if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$' then raise exception 'INVALID_SLUG' using errcode='22023'; end if;
 begin
  update public.artists set slug = v_slug, updated_at = now() where id = p_artist and owner_id = v_user;
  if not found then raise exception 'ARTIST_NOT_FOUND' using errcode='P0001'; end if;
 exception when unique_violation then raise exception 'SLUG_TAKEN' using errcode='P0001';
 end;
 return private.my_claims();
end $$;

create function public.set_place_slug(p_place uuid, p_slug text) returns jsonb language sql set search_path='' as $$ select private.set_place_slug(p_place, p_slug); $$;
create function public.set_artist_slug(p_artist uuid, p_slug text) returns jsonb language sql set search_path='' as $$ select private.set_artist_slug(p_artist, p_slug); $$;

revoke all on function private.drop_slug_without_owner(), private.set_place_slug(uuid,text), private.set_artist_slug(uuid,text),
 public.set_place_slug(uuid,text), public.set_artist_slug(uuid,text) from public, anon, authenticated;
grant execute on function private.set_place_slug(uuid,text), private.set_artist_slug(uuid,text),
 public.set_place_slug(uuid,text), public.set_artist_slug(uuid,text) to authenticated;

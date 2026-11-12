-- Інші написання артистів з tools/ingest/artists.json («Бродячого Стендапу», «COMEDY ШELTER») — у базі, для кабінету.
-- Імпорт зводить їх до канонічного імені ще до запису, тож досі база їх не знала: «Ви артист чи гурт» не знаходив
-- артиста за написанням з афіші, а «додати» створював дубль. Стовпець наповнює кожен дамп
-- (`emit.artist_aliases_sql`), за ключем канонічного імені.
alter table public.artists add column aliases text[] not null default '{}';

-- Пошук артиста — і за псевдонімами (ключ, як `normalize_name` в імпорті: без регістру й пунктуації).
create or replace function private.find_artists(p_text text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text := nullif(btrim(p_text), ''); k text; kt text;
begin
 if q is null or length(q) < 2 then return '[]'::jsonb; end if;
 if length(q) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 k := nullif(private.artist_key(q), ''); kt := nullif(private.artist_key(coalesce(private.search_translit(q), '')), '');
 return coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',t.id,'name',t.name,'kind',t.kind,
   'taken', case when t.taken then true end)) order by t.rank, t.name)
  from (select a.id, a.name, a.kind, a.owner_id is not null and a.owner_id <> auth.uid() as taken,
         case when lower(a.name) like lower(q) || '%' then 0 else 1 end as rank
        from public.artists a
        where a.name ilike '%' || q || '%' or a.name ilike '%' || private.search_translit(q) || '%'
          or exists (select 1 from unnest(a.aliases) x
                     where private.artist_key(x) like '%' || k || '%' or private.artist_key(x) like '%' || kt || '%')
        order by rank, a.name limit 8) t), '[]'::jsonb);
end $$;

-- «Немає в списку — додати» з написанням з афіші: беремо канонічного, а не заводимо дубль.
create or replace function private.add_my_artist(p_name text, p_kind text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer(); v_name text := btrim(regexp_replace(coalesce(p_name,''), '\s+', ' ', 'g'));
 v_key text := private.artist_key(v_name); v_artist uuid;
begin
 if length(v_name) < 2 or length(v_name) > 120 or v_key = '' then raise exception 'INVALID_ARTIST_NAME' using errcode='22023'; end if;
 if p_kind is not null and p_kind not in ('person','group') then raise exception 'INVALID_ARTIST_KIND' using errcode='22023'; end if;
 perform private.assert_clean_text(v_name);
 select a.id into v_artist from public.artists a
 where a.key = v_key or exists (select 1 from unnest(a.aliases) x where private.artist_key(x) = v_key)
 order by a.key = v_key desc limit 1;
 if v_artist is null then
  if (select count(*) from public.artists a where a.owner_id = v_user) >= 3 then raise exception 'TOO_MANY_CLAIMS' using errcode='P0001'; end if;
  insert into public.artists (name, key, kind, source) values (v_name, v_key, p_kind, 'manual') returning id into v_artist;
 end if;
 return private.claim_artist(v_artist);
end $$;

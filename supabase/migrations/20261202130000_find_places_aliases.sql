-- Пошук «Ваш заклад» у кабінеті знає й наші псевдоніми майданчиків (tools/ingest/aliases.json): «МЦКМ» чи «Жовтневий
-- палац» знаходять «Міжнародний центр культури і мистецтв». Окремої копії списку в базі нема: імпорт і так пише кожну
-- назву з афіші в кеш `public.venues` разом із точкою, а рядки з aliases.json там із `source = 'manual'`. Місце — у тій
-- самій точці (places унікальні за точкою). Беремо лише 'manual': назви з Photon у точці ТЦ — це ресторани й кіно в ньому,
-- і пошук ТЦ знову давав би їх. Ключ запиту — як `normalize_name` в імпорті (`private.artist_key`).
create or replace function private.find_places(p_text text, p_city text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text := nullif(btrim(p_text), ''); k text; kt text;
begin
 if q is null or length(q) < 2 then return '[]'::jsonb; end if;
 if length(q) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 k := nullif(private.artist_key(q), ''); kt := nullif(private.artist_key(coalesce(private.search_translit(q), '')), '');
 return coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',t.id,'name',t.name,'city',t.city,'address',t.address,
   'taken', case when t.taken then true end)) order by t.rank, t.name)
  from (select p.id, p.name, p.city, p.address, p.owner_id is not null and p.owner_id <> auth.uid() as taken,
         case when lower(p.name) like lower(q) || '%' then 0 else 1 end as rank
        from public.places p
        where (p_city is null or p.city = p_city)
          and (p.name ilike '%' || q || '%' or p.name ilike '%' || private.search_translit(q) || '%'
            or (p.latitude, p.longitude) in (select v.latitude, v.longitude from public.venues v
              where v.source = 'manual' and (v.norm_name like '%' || k || '%' or v.norm_name like '%' || kt || '%')))
        order by rank, p.name limit 8) t), '[]'::jsonb);
end $$;

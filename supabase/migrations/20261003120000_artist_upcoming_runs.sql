-- `upcoming` у пошуку артистів рахується виставами, як у «Підписках».
--
-- Було: `search_artists` рахував сеанси (МУР: 3 сеанси = «3 події»), а `my_follows` і `follow_events` —
-- прокат як одну подію (та сама назва без урахування регістру й крайніх пробілів: «1 подія»). Людина бачила
-- одного артиста з двома різними числами. Тепер обидва місця рахують виставами; правило те саме, що в
-- `private.followed_events` і в зведенні пуша (20260928160000, 20261002120000).
--
-- Лишається різниця, яка не помилка: `search_artists(p_city)` рахує лише місто пошуку, `my_follows` — усе;
-- `artist_events` віддає картки всіх сеансів (екран артиста показує дати, а не згорнутий прокат).

create or replace function public.search_artists(p_text text, p_city text default null, p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text := nullif(btrim(p_text), ''); v_limit integer;
begin
 if q is null then return '[]'::jsonb; end if;
 if length(q) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
 return coalesce((
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', t.id, 'name', t.name, 'kind', t.kind, 'upcoming', t.upcoming)) order by t.upcoming desc, t.name)
  from (
   select a.id, a.name, a.kind, u.upcoming
   from public.artists a
   cross join lateral (
    select count(distinct lower(btrim(e.title)))::integer as upcoming
    from public.event_artists ea join public.events e on e.id = ea.event_id
    where ea.artist_id = a.id and e.status='published' and e.ends_at > now()
      and (p_city is null or e.city = p_city)
      and private.is_discoverable(e.origin, e.import_status, e.quality)) u
   where (a.search @@ (websearch_to_tsquery('simple', q)::text || ':*')::tsquery
          or a.name ilike '%' || q || '%')
     and u.upcoming > 0
   order by u.upcoming desc, a.name
   limit v_limit) t), '[]'::jsonb);
end $$;

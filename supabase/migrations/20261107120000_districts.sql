-- Райони міст: «Київський» в Одесі звужує мапу, список і лічильники до району. Межі — адміністративні райони з
-- OpenStreetMap (ODbL), заливає `tools/districts.py` з `tools/districts.json`; файл повністю замінює таблицю.
-- Тут же місцевості (Аркадія, Великий Фонтан): в OSM це лише точки, тож межа — коло `radius_m` навколо точки.
-- Фільтрує клієнт: точка в полігоні над індексом видачі, як категорія. Так мапа, список і лічильники рахуються з одного
-- списку, вибір району не чекає мережі, а запит мапи без фільтрів і далі спільний з головною. Сервер лише віддає межі.

create table public.districts (
 -- Id відношення в OSM: перейменування його не змінює. Місцевість — id вузла OSM зі знаком мінус.
 id bigint primary key,
 city text not null,
 name text not null check (length(name) between 1 and 100),
 -- Назва до нещодавнього перейменування (Малиновський → Хаджибейський): пошук нагадує «раніше …». Null — не перейменовували.
 former_name text check (length(former_name) between 1 and 100),
 -- Лише для пошуку, не показуємо: назви до 2016 року і звичні («Оболонь»). Російських назв нема.
 aliases text[] not null default '{}',
 -- Місцевість: радіус кола навколо точки OSM. Null — адміністративний район з межею.
 radius_m integer check (radius_m between 100 and 10000),
 -- Спрощені межі (~10 м), без щілин між сусідами: спільний шлях OSM спрощується однаково.
 boundary gis.geometry(MultiPolygon,4326) not null check (gis.st_isvalid(boundary)),
 -- Назви повторюються між містами (Київський — і в Одесі, і в Харкові), у місті — ні.
 unique (city, name)
);
-- Лише через city_districts: сирі геометрії клієнтам не потрібні.
alter table public.districts enable row level security;
revoke all on public.districts from anon, authenticated;

-- Райони міста для пошуку й фільтра мапи. `rings` — усі кільця межі поспіль ([lon, lat], ~1 м), зовнішні й дірки разом:
-- клієнт рахує парність перетинів, тож порядок і напрям кілець не важать. Порожньо — для міста районів нема.
create or replace function public.city_districts(p_city text)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
   'id', d.id, 'name', d.name, 'former', d.former_name, 'aliases', to_jsonb(d.aliases), 'radius', d.radius_m,
   'rings', (select jsonb_agg(ring)
             from jsonb_array_elements(gis.st_asgeojson(d.boundary, 5)::jsonb -> 'coordinates') polygon,
                  jsonb_array_elements(polygon) ring)
  ) order by d.name), '[]'::jsonb)
 from public.districts d
 where d.city = p_city;
$$;
revoke all on function public.city_districts(text) from public, anon, authenticated;
grant execute on function public.city_districts(text) to anon, authenticated;

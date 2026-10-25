-- Запускати адміністратором бази після заливки `out/districts.sql` (`tools/districts.py`). Фікстури не зберігаються.
begin;
-- «Альфа» — квадрат із діркою, «Бета» — сусідній квадрат, перейменований, «Дельта» — місцевість-коло (тут квадрат).
insert into public.districts (id, city, name, former_name, aliases, boundary) values
 (-1, 'Ocean', 'Альфа район', null, '{}',
  gis.st_multi(gis.st_geomfromtext('POLYGON((0 0,1 0,1 1,0 1,0 0),(0.4 0.4,0.6 0.4,0.6 0.6,0.4 0.6,0.4 0.4))', 4326))),
 (-2, 'Ocean', 'Бета район', 'Гамма район', '{Бетка,Стара Бета}',
  gis.st_multi(gis.st_geomfromtext('POLYGON((1 0,2 0,2 1,1 1,1 0))', 4326)));
insert into public.districts (id, city, name, radius_m, boundary) values
 (-4, 'Ocean', 'Дельта', 1500, gis.st_multi(gis.st_geomfromtext('POLYGON((0.5 0.5,1.5 0.5,1.5 1.5,0.5 1.5,0.5 0.5))', 4326)));
do $$ begin
 insert into public.districts (id, city, name, boundary)
 values (-3, 'Ocean', 'Бантик', gis.st_multi(gis.st_geomfromtext('POLYGON((0 0,1 1,1 0,0 1,0 0))', 4326)));
 raise exception 'self-intersecting boundary accepted';
exception when check_violation then null; end $$;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ declare d jsonb := public.city_districts('Ocean'); begin
 assert jsonb_array_length(d) = 3, 'districts and the locality of the city';
 assert d->0->>'name' = 'Альфа район' and d->1->>'name' = 'Бета район' and d->2->>'name' = 'Дельта', 'by name';
 assert d->0->'radius' = 'null'::jsonb and d->2->'radius' = '1500'::jsonb, 'locality carries its radius';
 assert jsonb_array_length(d->0->'rings') = 2, 'outer ring and the hole';
 assert d->0->'former' = 'null'::jsonb and d->0->'aliases' = '[]'::jsonb, 'nothing to remind';
 assert d->1->>'former' = 'Гамма район' and d->1->'aliases' = '["Бетка","Стара Бета"]'::jsonb, 'former name and aliases';
 assert d->1->'rings'->0->0 = '[1, 0]'::jsonb, 'lon, lat';
 assert public.city_districts('Nowhere') = '[]'::jsonb, 'unknown city is empty';
 begin perform * from public.districts; raise exception 'anon reads districts'; exception when insufficient_privilege then null; end;
end $$;
reset role;
delete from public.districts where id in (-1, -2, -4);

-- Залиті дані: усі райони п'яти міст, відомі точки у своїх районах, сусіди не налазять один на одного; місцевості — кола.
do $$ declare
 missing text;
 overlap text;
begin
 select string_agg(c.city || ' ' || coalesce(n, 0) || '/' || c.expected, ', ') into missing
 from (values ('Київ', 10), ('Львів', 6), ('Одеса', 4), ('Дніпро', 8), ('Харків', 9)) c(city, expected)
 left join (select city, count(*)::int n from public.districts where radius_m is null group by city) d on d.city = c.city
 where coalesce(n, 0) <> c.expected;
 assert missing is null, 'districts per city (load out/districts.sql): ' || missing;
 assert (select name from public.districts where city = 'Одеса' and radius_m is null
         and gis.st_contains(boundary, gis.st_setsrid(gis.st_makepoint(30.7326, 46.4846), 4326))) = 'Приморський район', 'Дерибасівська';
 assert (select name from public.districts where city = 'Київ' and radius_m is null
         and gis.st_contains(boundary, gis.st_setsrid(gis.st_makepoint(30.5148, 50.4655), 4326))) = 'Подільський район', 'Контрактова площа';
 assert (select name from public.districts where city = 'Львів' and radius_m is null
         and gis.st_contains(boundary, gis.st_setsrid(gis.st_makepoint(24.0316, 49.8419), 4326))) = 'Галицький район', 'площа Ринок';
 assert (select name from public.districts where city = 'Харків' and radius_m is null
         and gis.st_contains(boundary, gis.st_setsrid(gis.st_makepoint(36.2310, 50.0050), 4326))) = 'Шевченківський район', 'майдан Свободи';
 select string_agg(a.name || ' × ' || b.name, ', ') into overlap
 from public.districts a join public.districts b on a.city = b.city and a.id < b.id and a.radius_m is null and b.radius_m is null
 where gis.st_area(gis.st_intersection(a.boundary, b.boundary)) > 1e-9;
 assert overlap is null, 'neighbours overlap: ' || overlap;
 assert (select count(*) from public.districts where city = 'Одеса' and radius_m is not null
         and gis.st_contains(boundary, gis.st_setsrid(gis.st_makepoint(30.7616, 46.4316), 4326)) and name = 'Аркадія') = 1, 'Аркадія — коло навколо точки';
end $$;
select 'PASS: city_districts by name with holes, former, aliases and locality radius, table closed, invalid boundary rejected; data: 37 districts, known points, no overlaps, Аркадія' as result;
rollback;

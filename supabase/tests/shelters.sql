-- Запускати адміністратором бази. Фікстури не зберігаються.
begin;
select set_config('test.host',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values(current_setting('test.host')::uuid,'poruch-shelter-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('birth_date','1990-01-01'));
insert into public.city_curfews(city, starts, ends) values ('Ocean', '23:30', '05:00');
-- Подія на -40.5,-30.5; укриття на ~110 м, ~220 м, ~330 м, ~440 м і ~2 км на північ.
insert into public.shelters(id, city, kind, address, latitude, longitude, accessible, hours, source)
select 'test:'||i, 'Ocean', case when i=1 then 'metro' else 'basement' end, 'Buoy, '||i,
       -40.5 + case when i=5 then 0.018 else i*0.001 end, -30.5, i=2, case when i=3 then '10:00–18:00' end, 'test'
from generate_series(1,5) i;
-- Не потрапляють у видачу, хоч ближчі за наступних: друга точка «Buoy, 2» (~280 м) і ще один вхід у метро (~180 м).
insert into public.shelters(id, city, kind, address, latitude, longitude, source) values
 ('test:6','Ocean','basement','BUOY, 2',-40.5025,-30.5,'test'),
 ('test:7','Ocean','metro','Other entrance',-40.5016,-30.5,'test');
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values (gen_random_uuid(),current_setting('test.host')::uuid,'Safety','Test description','social','Ocean','Buoy',-40.5,-30.5,now()+interval '1 day',now()+interval '1 day 2 hours','UTC',10);
select set_config('test.event',(select id::text from public.events where title='Safety' and city='Ocean'),true);
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ declare s jsonb; begin
 s := public.event_safety(current_setting('test.event')::uuid);
 assert jsonb_array_length(s->'shelters')=3, 'three nearest within 1 km';
 assert s->'shelters'->0->>'kind'='metro' and s->'shelters'->0->>'address'='Buoy, 1', 'nearest first';
 assert (s->'shelters'->0->>'distance_m')::int between 100 and 120, 'distance in metres';
 assert s->'shelters'->1->>'address'='Buoy, 2', 'one row per address, one metro';
 assert (s->'shelters'->1->>'accessible')::boolean and s->'shelters'->2->>'hours'='10:00–18:00', 'accessible and hours pass through';
 assert s->'curfew'->>'starts'='23:30' and s->'curfew'->>'ends'='05:00', 'curfew of the event city';
 assert public.event_safety(gen_random_uuid()) is null, 'unknown event is null';
 begin perform * from public.shelters; raise exception 'anon reads shelters'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.events set status='hidden' where id=current_setting('test.event')::uuid;
set local role anon;
do $$ begin assert public.event_safety(current_setting('test.event')::uuid) is null, 'hidden event is null'; end $$;
reset role;
select 'PASS: event_safety nearest distinct shelters within 1 km, curfew, hidden/unknown null, table closed' as result;
rollback;

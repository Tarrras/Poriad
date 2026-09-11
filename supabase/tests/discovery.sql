-- Run as database administrator. No fixtures persist.
begin;
select set_config('test.host',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values(current_setting('test.host')::uuid,'poruch-geo-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('birth_date','1990-01-01'));
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
select gen_random_uuid(),current_setting('test.host')::uuid,'Geo '||i,'','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',10 from generate_series(1,301) i;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
select gen_random_uuid(),current_setting('test.host')::uuid,'Dateline '||x,'','outdoors','Dateline','Coast',0,x,now()+interval '3 days',now()+interval '4 days','UTC',10 from unnest(array[-179.5,179.5]) x;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
-- Counts are scoped to this suite's own fixtures by title: the project holds real events in the
-- same city, and a test that counts everything inside Kyiv measures the seed data instead.
do $$ begin
 assert (select count(*)=300 from public.events_in_view(49,29,51,32,'social') where title like 'Geo %'),'300 limit';
 assert (select count(*)=2 from public.events_in_view(-1,179,1,-179,'outdoors') where title like 'Dateline %'),'antimeridian includes both hemispheres';
 assert (select count(*)=0 from public.events_in_view(-1,-179,1,179,'outdoors') where title like 'Dateline %'),'normal bounds exclude dateline';
 assert (select count(*)=0 from public.events_in_view(49,29,51,32,'music') where title like 'Geo %'),'category filter';
 assert (select count(*)=0 from public.events_in_view(49,29,51,32,null,now()+interval '2 days',null) where title like 'Geo %'),'from filter';
 assert (select count(*)=0 from public.events_in_view(-1,179,1,-179,null,null,now()+interval '2 days') where title like 'Dateline %'),'to filter';
 assert (select bool_and(not joined and attendee_count=0) from public.events_in_view(49,29,51,32) where title like 'Geo %'),'guest projection';
 begin perform public.events_in_view(91,0,92,1); raise exception 'invalid bounds accepted'; exception when sqlstate '22023' then assert sqlerrm='INVALID_BOUNDS'; end;
end $$;
reset role;
select 'PASS: spatial bounds, antimeridian, category/date filters, 300 bound, guest aggregation' as result;
rollback;

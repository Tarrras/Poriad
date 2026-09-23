-- Запускати адміністратором бази. Фікстури не зберігаються.
begin;
select set_config('test.host',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values(current_setting('test.host')::uuid,'poruch-geo-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('birth_date','1990-01-01'));
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
select gen_random_uuid(),current_setting('test.host')::uuid,'Geo '||i,'','social','Ocean','Buoy',-40.5,-30.5,now()+interval '1 day',now()+interval '2 days','UTC',10 from generate_series(1,301) i;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
select gen_random_uuid(),current_setting('test.host')::uuid,'Dateline '||x,'','outdoors','Dateline','Coast',0,x,now()+interval '3 days',now()+interval '4 days','UTC',10 from unnest(array[-179.5,179.5]) x;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
-- Фікстури — посеред Атлантики (-40.5,-30.5), де справжніх подій немає: ліміт 300 рахується до
-- фільтра, тож чужі події в рамці зламали б перевірку. Рахуємо ще й за організатором.
do $$ begin
 assert (select count(*)=300 from public.events_in_view(-41,-31,-40,-30,'social') where organizer_id=current_setting('test.host')::uuid),'300 limit';
 assert (select count(*)=2 from public.events_in_view(-1,179,1,-179,'outdoors') where organizer_id=current_setting('test.host')::uuid),'antimeridian includes both hemispheres';
 assert (select count(*)=0 from public.events_in_view(-1,-179,1,179,'outdoors') where organizer_id=current_setting('test.host')::uuid),'normal bounds exclude dateline';
 assert (select count(*)=0 from public.events_in_view(-41,-31,-40,-30,'music') where organizer_id=current_setting('test.host')::uuid),'category filter';
 assert (select count(*)=0 from public.events_in_view(-41,-31,-40,-30,null,now()+interval '2 days',null) where organizer_id=current_setting('test.host')::uuid),'from filter';
 assert (select count(*)=0 from public.events_in_view(-1,179,1,-179,null,null,now()+interval '2 days') where organizer_id=current_setting('test.host')::uuid),'to filter';
 assert (select bool_and(not joined and attendee_count=0) from public.events_in_view(-41,-31,-40,-30) where organizer_id=current_setting('test.host')::uuid),'guest projection';
 begin perform public.events_in_view(91,0,92,1); raise exception 'invalid bounds accepted'; exception when sqlstate '22023' then assert sqlerrm='INVALID_BOUNDS'; end;
end $$;
reset role;
select 'PASS: spatial bounds, antimeridian, category/date filters, 300 bound, guest aggregation' as result;
rollback;

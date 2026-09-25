-- Запускати адміністратором бази. Фікстури не зберігаються.
begin;
insert into public.places (name, city, address, latitude, longitude, source)
values ('Тестовий зал Ехо', 'Ocean', 'Buoy, 1', -40.5, -30.5, 'osm'),
       ('Порожній зал', 'Ocean', 'Buoy, 2', -40.6, -30.6, 'osm');
select set_config('test.host',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values(current_setting('test.host')::uuid,'poruch-place-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('birth_date','1990-01-01'));
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,place_id,starts_at,ends_at,time_zone,capacity)
select gen_random_uuid(),current_setting('test.host')::uuid,'Echo '||i,'Test description','social','Ocean','Buoy',-40.5,-30.5,
       (select id from public.places where name='Тестовий зал Ехо'),now()+(i||' day')::interval,now()+(i||' day')::interval+interval '2 hours','UTC',10
from generate_series(1,3) i;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ declare hit jsonb; cards jsonb; begin
 hit := public.search_places('ехо');
 assert jsonb_array_length(hit)=1 and hit->0->>'name'='Тестовий зал Ехо' and (hit->0->>'upcoming')::int=3, 'prefix search with upcoming count';
 assert jsonb_array_length(public.search_places('buoy, 1'))=1, 'address matches too';
 assert jsonb_array_length(public.search_places('порожн'))=0, 'place without upcoming events is hidden';
 assert jsonb_array_length(public.search_places('ехо','Ocean',-41,-31,-40,-30))=1, 'bbox keeps the place';
 assert jsonb_array_length(public.search_places('ехо','Ocean',0,0,1,1))=0, 'bbox excludes the place';
 assert public.search_places('   ')='[]'::jsonb, 'blank query is empty';
 cards := public.place_events((hit->0->>'id')::uuid);
 assert jsonb_array_length(cards)=3 and cards->0->>'title'='Echo 1' and cards->0->>'place_name'='Тестовий зал Ехо', 'place_events ordered with place_name';
 assert public.place_events(null)='[]'::jsonb, 'null place is empty';
 begin perform public.search_places(repeat('x',121)); raise exception 'long text accepted'; exception when sqlstate '22023' then assert sqlerrm='INVALID_SEARCH_TEXT'; end;
end $$;
reset role;
select 'PASS: places search by prefix/address/bbox, hidden without events, place_events with place_name' as result;
rollback;

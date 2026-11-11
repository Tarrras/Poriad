-- Запускати адміністратором бази. Усе відкочується. «Мій заклад» і «Я артист» (20261127120000): організатор сам
-- називає заклад чи артиста своїм; зайняте не перехопити, стеля — три, відмова знімає події. Чужих рядків не чіпає.
begin;

select set_config('test.u1',gen_random_uuid()::text,true),set_config('test.u2',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-claim-'||id||'@example.invalid',jsonb_build_object('display_name','C','birth_date','1990-01-01')
from unnest(array[current_setting('test.u1'),current_setting('test.u2')]) id;
insert into public.places(name,city,address,latitude,longitude,source) values ('Кафе Claim','Ocean','Buoy, 3',-43.1,-33.1,'osm');
insert into public.artists(name,key,kind) values ('Claim Solo','claim solo','person');
select set_config('test.place',(select id::text from public.places where name='Кафе Claim'),true),
 set_config('test.artist',(select id::text from public.artists where key='claim solo'),true),
 set_config('test.ev',gen_random_uuid()::text,true);
-- Майбутня подія u1 на координатах закладу: після «це мій заклад» має стати на нього й отримати артиста.
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values (current_setting('test.ev')::uuid,current_setting('test.u1')::uuid,'Вечір Claim','Test description','music','Ocean','Buoy, 3',-43.1,-33.1,
 now()+interval '1 day',now()+interval '1 day 2 hours','UTC',10);

-- Гість: жодної з функцій.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.my_claims(); raise exception 'anon read claims'; exception when insufficient_privilege then null; end;
 begin perform public.find_places('Claim','Ocean'); raise exception 'anon searched places'; exception when insufficient_privilege then null; end;
 begin perform public.claim_place(current_setting('test.place')::uuid); raise exception 'anon claimed'; exception when insufficient_privilege then null; end;
 begin perform public.add_my_artist('X Y'); raise exception 'anon added an artist'; exception when insufficient_privilege then null; end;
end $$;
reset role;

-- u1: знаходить заклад, називає своїм; подія підтягується.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$
declare v jsonb;
begin
 assert public.my_claims() = '{"places":[],"artists":[]}'::jsonb,'nothing yet';
 v := public.find_places('claim','Ocean');
 assert jsonb_array_length(v) = 1 and v->0->>'name' = 'Кафе Claim' and not (v->0 ? 'taken'),'found by a part of the name, free';
 assert public.find_places('c','Ocean') = '[]'::jsonb,'one letter is not a search';
 assert public.find_places('claim','Nowhere') = '[]'::jsonb,'another city';
 v := public.claim_place(current_setting('test.place')::uuid);
 assert jsonb_array_length(v->'places') = 1 and v->'places'->0->>'id' = current_setting('test.place'),'claimed';
 assert jsonb_array_length(public.claim_place(current_setting('test.place')::uuid)->'places') = 1,'a repeat is a no-op';
 begin perform public.claim_place(gen_random_uuid()); raise exception 'unknown place';
 exception when sqlstate 'P0001' then assert sqlerrm='PLACE_NOT_FOUND'; end;
end $$;
reset role;
do $$ begin
 assert (select place_id = current_setting('test.place')::uuid from public.events where id = current_setting('test.ev')::uuid),'the upcoming event moved to the place';
end $$;

-- u2: бачить, що зайнято, і перехопити не може — ні вибором, ні «новим» закладом на тих самих координатах.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u2'),true);
do $$ begin
 assert (public.find_places('claim','Ocean')->0->>'taken')::boolean,'taken for another account';
 begin perform public.claim_place(current_setting('test.place')::uuid); raise exception 'took over a place';
 exception when sqlstate 'P0001' then assert sqlerrm='PLACE_TAKEN'; end;
 begin perform public.add_my_place('Моє кафе','Ocean','Buoy, 3',-43.1,-33.1); raise exception 'took over by coordinates';
 exception when sqlstate 'P0001' then assert sqlerrm='PLACE_TAKEN'; end;
 assert public.release_place(current_setting('test.place')::uuid) = '{"places":[],"artists":[]}'::jsonb,'releasing someone else''s is a no-op';
end $$;
reset role;
do $$ begin
 assert (select owner_id = current_setting('test.u1')::uuid from public.places where id = current_setting('test.place')::uuid),'still the first owner';
end $$;

-- u1: нові заклади, перевірки назви й стеля три.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$
declare v jsonb;
begin
 begin perform public.add_my_place('К','Ocean','Buoy',-43.2,-33.2); raise exception 'short name';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PLACE_NAME'; end;
 begin perform public.add_my_place('Кафе Два','Ocean','Buoy',-143.2,-33.2); raise exception 'bad point';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PLACE'; end;
 begin perform public.add_my_place('Кафе Два','','Buoy',-43.2,-33.2); raise exception 'no city';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PLACE'; end;
 v := public.add_my_place('  Кафе Два Claim ','Ocean','Buoy, 4',-43.2,-33.2);
 assert jsonb_array_length(v->'places') = 2,'a new place is mine at once';
 assert jsonb_array_length(public.add_my_place('Кафе Три Claim','Ocean',null,-43.3,-33.3)->'places') = 3;
 begin perform public.add_my_place('Кафе Чотири Claim','Ocean',null,-43.4,-33.4); raise exception 'fourth place';
 exception when sqlstate 'P0001' then assert sqlerrm='TOO_MANY_CLAIMS'; end;
end $$;
reset role;
do $$ begin
 assert (select name = 'Кафе Два Claim' and source = 'manual' and address = 'Buoy, 4' from public.places where latitude = -43.2 and longitude = -33.2),'trimmed, manual';
 assert not exists (select 1 from public.places where latitude = -43.4 and longitude = -33.4),'the refused place was not created';
end $$;

-- Артисти: наявний, новий, той самий ключ з іншою пунктуацією, чужий, стеля.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$
declare v jsonb;
begin
 v := public.find_artists('claim so');
 assert jsonb_array_length(v) = 1 and v->0->>'id' = current_setting('test.artist'),'found';
 assert jsonb_array_length(public.claim_artist(current_setting('test.artist')::uuid)->'artists') = 1;
 v := public.add_my_artist('  Гурт  «Claim Band» ','group');
 assert jsonb_array_length(v->'artists') = 2,'a new artist is mine at once';
 assert jsonb_array_length(public.add_my_artist('гурт claim band','group')->'artists') = 2,'the same key: no duplicate';
 begin perform public.add_my_artist('X'); raise exception 'short name';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_ARTIST_NAME'; end;
 begin perform public.add_my_artist('Claim Third','show'); raise exception 'unknown kind';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_ARTIST_KIND'; end;
 assert jsonb_array_length(public.add_my_artist('Claim Third')->'artists') = 3;
 begin perform public.add_my_artist('Claim Fourth'); raise exception 'fourth artist';
 exception when sqlstate 'P0001' then assert sqlerrm='TOO_MANY_CLAIMS'; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.u2'),true);
do $$ begin
 assert (public.find_artists('claim solo')->0->>'taken')::boolean;
 begin perform public.claim_artist(current_setting('test.artist')::uuid); raise exception 'took over an artist';
 exception when sqlstate 'P0001' then assert sqlerrm='ARTIST_TAKEN'; end;
 begin perform public.add_my_artist('Гурт Claim Band'); raise exception 'took over by name';
 exception when sqlstate 'P0001' then assert sqlerrm='ARTIST_TAKEN'; end;
end $$;
reset role;
do $$ begin
 assert (select name = 'Гурт «Claim Band»' and key = 'гурт claim band' and kind = 'group' and source = 'manual' from public.artists where key = 'гурт claim band');
 assert (select count(*) = 3 from public.event_artists where event_id = current_setting('test.ev')::uuid),'the upcoming event carries all three';
end $$;

-- Відмова: заклад і артист вільні, подія знята з обох.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$ begin
 assert jsonb_array_length(public.release_place(current_setting('test.place')::uuid)->'places') = 2;
 assert jsonb_array_length(public.release_artist(current_setting('test.artist')::uuid)->'artists') = 2;
end $$;
reset role;
do $$ begin
 assert (select owner_id is null from public.places where id = current_setting('test.place')::uuid);
 assert (select place_id is null from public.events where id = current_setting('test.ev')::uuid),'the event left the place';
 assert not exists (select 1 from public.event_artists where event_id = current_setting('test.ev')::uuid and artist_id = current_setting('test.artist')::uuid);
end $$;
-- Тепер заклад може взяти інший.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u2'),true);
do $$ begin assert jsonb_array_length(public.claim_place(current_setting('test.place')::uuid)->'places') = 1,'free again'; end $$;
reset role;

rollback;

-- Запускати адміністратором бази. Усе відкочується. Аудит безпеки хвилі 1: ліміт файлів у теці події (фото 12, відео
-- 11; upsert того самого файлу й аватари не рахуються; копія в теку нової події — окремий ліміт), стеля анонсу 300 на
-- годину; назва з доменом у базі дозволена (посилання з листів прибирає функція push).
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.event',gen_random_uuid()::text,true),
 set_config('test.again',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
values (current_setting('test.host')::uuid,'poruch-sec1-'||current_setting('test.host')||'@example.invalid',
 jsonb_build_object('display_name','S','birth_date','1990-01-01'));
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
select current_setting('test.'||k)::uuid,current_setting('test.host')::uuid,'Run.Club у барі','Посилання в описі можна: https://t.me/mafia','games','Kyiv','Podil',
 50.46,30.52,now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10
from unnest(array['event','again']) k;

-- Файли — від імені організатора, як вантажить Storage з його токеном.
create function pg_temp.put(p_bucket text,p_event text,p_file text) returns text language plpgsql as $$
begin
 insert into storage.objects(bucket_id,name,owner_id)
 values (p_bucket,current_setting('test.host')||'/'||current_setting('test.'||p_event)||'/'||p_file,current_setting('test.host'));
 return 'ok';
exception when sqlstate 'P0001' then return sqlerrm;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
set local role authenticated;
do $$ begin
 for i in 1..12 loop assert pg_temp.put('event-images','event','p'||i||'.jpg')='ok','photo '||i||' of 12'; end loop;
 assert pg_temp.put('event-images','event','p13.jpg')='TOO_MANY_FILES','the 13th photo in the event folder is refused';
 -- 11 = 2×5+1: заміна всіх п'яти відео вантажить нові до видалення старих.
 for i in 1..11 loop assert pg_temp.put('event-videos','event','v'||i||'.mp4')='ok','video '||i||' of 11'; end loop;
 assert pg_temp.put('event-videos','event','v12.mp4')='TOO_MANY_FILES','the 12th video is refused';
 -- «Повторити»: копія п'яти медіа з постерами в теку нової події — свій ліміт.
 for i in 1..5 loop
  assert pg_temp.put('event-images','again','poster'||i||'.jpg')='ok' and pg_temp.put('event-videos','again','v'||i||'.mp4')='ok','repeat copies '||i;
 end loop;
 -- Аватари — без ліміту теки події.
 for i in 1..13 loop
  insert into storage.objects(bucket_id,name,owner_id) values ('event-images',current_setting('test.host')||'/avatar/a'||i||'.jpg',current_setting('test.host'));
 end loop;
end $$;
reset role;
-- Повтор того самого файлу (upsert, як x-upsert у Storage) не рахується як новий.
do $$ begin
 insert into storage.objects(bucket_id,name,owner_id) values ('event-images',current_setting('test.host')||'/'||current_setting('test.event')||'/p12.jpg',current_setting('test.host'))
 on conflict (bucket_id, name collate "C") where not is_versioned do update set updated_at=now();
 assert (select count(*)=12 from storage.objects where name like current_setting('test.host')||'/'||current_setting('test.event')||'/%' and bucket_id='event-images'),
  'an upsert of an existing file passes and adds nothing';
end $$;

-- Стеля анонсу: 300 на годину на всіх.
delete from private.announce_calls;
insert into private.announce_calls(ip) select ('10.0.' || (i / 256) || '.' || (i % 256))::inet from generate_series(1,299) i;
do $$ begin
 assert public.announce_call('198.51.100.1'),'the 300th call passes';
 assert not public.announce_call('198.51.100.2'),'the 301st is refused';
end $$;

rollback;

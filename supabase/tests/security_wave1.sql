-- Запускати адміністратором бази. Усе відкочується. Аудит безпеки хвилі 1: ліміт файлів у теці події (фото 12, відео
-- 6; upsert того самого файлу й аватари не рахуються; копія в теку нової події — окремий ліміт), стеля анонсу 300 на
-- годину, назва спільнотної події без посилань і доменів (опис — можна, супутник і стара назва — як були).
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.event',gen_random_uuid()::text,true),
 set_config('test.again',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
values (current_setting('test.host')::uuid,'poruch-sec1-'||current_setting('test.host')||'@example.invalid',
 jsonb_build_object('display_name','S','birth_date','1990-01-01'));
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
select current_setting('test.'||k)::uuid,current_setting('test.host')::uuid,'Мафія в барі','Посилання в описі можна: https://t.me/mafia','games','Kyiv','Podil',
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
 for i in 1..6 loop assert pg_temp.put('event-videos','event','v'||i||'.mp4')='ok','video '||i||' of 6'; end loop;
 assert pg_temp.put('event-videos','event','v7.mp4')='TOO_MANY_FILES','the 7th video is refused';
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

-- Назва без посилань і доменів.
create function pg_temp.title(p_title text,p_event text default 'event') returns text language plpgsql as $$
begin
 update public.events set title=p_title where id=current_setting('test.'||p_event)::uuid;
 return 'ok';
exception when sqlstate '22023' then return sqlerrm;
end $$;
do $$ begin
 assert pg_temp.title('Мафія в барі «Ст. Сковороди», 2.0')='ok','an ordinary title passes';
 assert pg_temp.title('Мафія evil.com')='INVALID_TITLE','a domain is refused';
 assert pg_temp.title('Мафія https://x.y')='INVALID_TITLE' and pg_temp.title('Мафія www.x')='INVALID_TITLE','links are refused';
 assert pg_temp.title('Збір у t.me')='INVALID_TITLE' and pg_temp.title('Вечір на Rock.UA')='INVALID_TITLE'
  and pg_temp.title('Квиз на сайт.укр')='INVALID_TITLE','short and Cyrillic domains, any case';
 assert pg_temp.title('Node.js мітап')='ok','not a listed domain';
end $$;
-- Стара назва з доменом лишається: подію можна редагувати, не чіпаючи назви. Супутник бере назву афіші як є (вставка
-- проходить).
alter table public.events disable trigger events_text_lengths;
update public.events set title='Вечірка з Booking.com' where id=current_setting('test.again')::uuid;
alter table public.events enable trigger events_text_lengths;
do $$ begin
 update public.events set description='Новий опис без посилань, довший за десять' where id=current_setting('test.again')::uuid;
 update public.events set title='Вечірка з Booking.com' where id=current_setting('test.again')::uuid;
 assert pg_temp.title('Вечірка з Booking.com','again')='ok','the same old title is not checked again';
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,companion_of)
 values (gen_random_uuid(),current_setting('test.host')::uuid,'Компанія на fest.ua','Збираємось разом перед входом','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 1 hour','Europe/Kyiv',4,current_setting('test.event')::uuid);
end $$;

rollback;

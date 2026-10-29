-- Запускати адміністратором бази. Усе відкочується. «Мої місця» (20261114120000, docs/my-places.md): перевірки
-- `set_zones`, ключ зони тримає `created_at`, «нове» від появи зони, лише події від людей у зоні, раз на добу, своя
-- подія й заблокований організатор мовчать, лічильник для організатора від трьох, забуття разом з пристроєм.
begin;

-- Ізоляція: справжні пристрої на базі обробило б зведення. Усе відкотиться.
delete from private.radar_devices;
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select 'https://example.invalid'::text, 'x'::text $$;

select set_config('test.host',gen_random_uuid()::text,true),set_config('test.me',gen_random_uuid()::text,true),
 set_config('test.district',(select id::text from public.districts where city='Київ' and name='Подільський район'),true),
 set_config('test.g',repeat('a',64),true),set_config('test.h',repeat('b',64),true),set_config('test.i',repeat('c',64),true),
 set_config('test.j',repeat('d',64),true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-zones-'||id||'@example.invalid',jsonb_build_object('display_name','Z','birth_date','1990-01-01')
from unnest(array[current_setting('test.host'),current_setting('test.me')]) id;

-- Подія від людей: Контрактова площа (Поділ) чи Троєщина; created_at відносно now().
create function pg_temp.meet(p_name text,p_lon float8,p_lat float8,p_created interval) returns void language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
  capacity,created_at)
 values (v_id,current_setting('test.host')::uuid,'Зона '||p_name,'Test description','games','Київ','Test',p_lat,p_lon,
  now()+interval '3 days',now()+interval '3 days 2 hours','Europe/Kyiv',8,now()+p_created);
 perform set_config('test.'||p_name,v_id::text,true);
end $$;

do $$
declare v_created timestamptz;
begin
 -- Клієнт: формат і права.
 assert has_function_privilege('anon','public.set_zones(text,text,text,bigint[],jsonb)','execute'),'guest sets zones';
 assert not has_function_privilege('anon','public.zone_audience(double precision,double precision)','execute'),'audience needs an account';
 assert not has_function_privilege('anon','private.notify_zone_devices()','execute'),'guest cannot push';
 begin
  perform public.set_zones(current_setting('test.g'),'ios','Київ',null,'[{"lat":50.45,"lon":30.52,"r":1500}]');
  assert false,'radius outside 1/2/3 km';
 exception when sqlstate '22023' then null; end;
 begin
  perform public.set_zones(current_setting('test.g'),'ios','Київ',null,'[{"lat":40.1,"lon":30.52,"r":1000}]');
  assert false,'circle outside Ukraine';
 exception when sqlstate '22023' then null; end;
 perform public.set_zones(repeat('e',160),'ios','Київ',null,'[]');
 assert exists (select 1 from private.radar_devices where token=repeat('e',160)),'a longer APNs token (iOS 26 simulator) is accepted';
 begin
  perform public.set_zones('not-a-token','ios','Київ',null,'[]');
  assert false,'token format';
 exception when sqlstate '22023' then null; end;

 -- Район і коло; невідомий район мовчки відкидається. Точка округлюється до ~100 м.
 perform public.set_zones(current_setting('test.g'),'ios','Київ',
  array[current_setting('test.district')::bigint, 999999999999],'[{"lat":50.51049,"lon":30.60012,"r":1000}]');
 assert (select count(*) from private.zone_areas where token=current_setting('test.g'))=2,'district and circle';
 assert exists (select 1 from private.zone_areas where token=current_setting('test.g') and key='c:50.510,30.600,1000'),'rounded key';
 assert exists (select 1 from private.radar_devices where token=current_setting('test.g') and city='Київ'),'device row shared with radar';

 -- Повторна синхронізація тримає `created_at`, прибрана зона зникає.
 update private.zone_areas set created_at=now()-interval '1 hour' where token=current_setting('test.g');
 perform public.set_zones(current_setting('test.g'),'ios','Київ',array[current_setting('test.district')::bigint],'[]');
 select created_at into v_created from private.zone_areas where token=current_setting('test.g');
 assert v_created=now()-interval '1 hour','kept zone keeps created_at';
 assert (select count(*) from private.zone_areas where token=current_setting('test.g'))=1,'removed circle is gone';
end $$;

-- Події: стара на Подолі (до зони), нова на Подолі, нова на Троєщині, нова афіша на Подолі.
select pg_temp.meet('old',30.5148,50.4655,interval '-2 hours');
select pg_temp.meet('podil',30.5148,50.4655,interval '0');
select pg_temp.meet('troieshchyna',30.6001,50.5105,interval '0');
insert into public.event_sources(slug,name,kind,base_url) values ('test_zones','Test','manual','https://example.invalid');
insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
 origin,source_id,source_uid,import_status,quality)
values (gen_random_uuid(),'Зона афіша','','music','Київ','Test',50.4656,30.5150,now()+interval '3 days',now()+interval '3 days 2 hours','Europe/Kyiv',
 'import',(select id from public.event_sources where slug='test_zones'),'zones-afisha','live',0.9);

do $$
declare v_p jsonb;
begin
 assert private.notify_zone_devices()=1,'one push for the device';
 select payload into v_p from pg_temp.sent where payload->>'type'='zone';
 assert v_p->>'token'=current_setting('test.g') and v_p->>'platform'='ios','to the device';
 assert v_p->>'event_id'=current_setting('test.podil'),'the new meetup in Podil';
 assert (v_p->>'total')::int=1,'old, other-district and afisha events are not counted';
 assert private.notify_zone_devices()=0,'daily limit';

 -- Через добу нове вже сказане: тиша. Нова подія — пуш.
 update private.zone_pushes set sent_at=now()-interval '25 hours';
 assert private.notify_zone_devices()=0,'nothing new after a day';
 perform pg_temp.meet('podil2',30.5149,50.4654,interval '0');
 assert private.notify_zone_devices()=1,'next new meetup next day';

 -- Своя подія мовчить: токен пристрою — в акаунті організатора.
 delete from pg_temp.sent;
 update private.zone_pushes set sent_at=now()-interval '25 hours';
 insert into public.push_tokens(token,user_id,platform) values (current_setting('test.g'),current_setting('test.host')::uuid,'ios');
 perform pg_temp.meet('podil3',30.5149,50.4654,interval '0');
 assert private.notify_zone_devices()=0,'own event is not news';
 delete from public.push_tokens where token=current_setting('test.g');

 -- Заблокований організатор мовчить.
 insert into public.push_tokens(token,user_id,platform) values (current_setting('test.g'),current_setting('test.me')::uuid,'ios');
 insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.me')::uuid,current_setting('test.host')::uuid);
 assert private.notify_zone_devices()=0,'blocked organizer';
 delete from public.user_blocks where user_id=current_setting('test.me')::uuid;
 assert private.notify_zone_devices()=1,'unblocked: podil3 goes';

 -- Лічильник: два пристрої — null, три — 3.
 perform public.set_zones(current_setting('test.h'),'ios','Київ',null,'[{"lat":50.4655,"lon":30.5148,"r":1000}]');
 assert public.zone_audience(50.4655,30.5148) is null,'two devices: hidden';
 perform public.set_zones(current_setting('test.i'),'ios','Київ',array[current_setting('test.district')::bigint],'[]');
 assert public.zone_audience(50.4655,30.5148)=3,'three devices nearby';
 assert public.zone_audience(50.5105,30.6001) is null,'nobody follows Troieshchyna';

 -- Забуття: пристрій зникає разом із зонами.
 perform public.forget_radar(current_setting('test.h'));
 assert not exists (select 1 from private.zone_areas where token=current_setting('test.h')),'forget removes zones';
 -- Порожній список — пристрій без зон, але з рядком (його тримає радар).
 perform public.set_zones(current_setting('test.i'),'ios','Київ','{}','[]');
 assert not exists (select 1 from private.zone_areas where token=current_setting('test.i')),'empty list clears zones';
end $$;

rollback;
select 'my_places: ok' as result;

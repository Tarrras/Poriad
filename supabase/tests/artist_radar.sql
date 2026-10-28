-- Запускати адміністратором бази. Усе відкочується. Радар артистів (20261113120000, docs/artist-radar.md): перевірки
-- `set_radar`, «нове» від появи артиста в списку пристрою, лише місто пристрою, раз на добу, пристрій з акаунтом мовчить,
-- пуш акаунту лише про його місто (і без фільтра, коли міста не знаємо), «Ваші артисти», «Кого слухаєте?», забуття й
-- чистка за 120 днів.
begin;

-- Ізоляція: справжні пристрої й підписки на базі обробило б зведення. Усе відкотиться.
delete from private.radar_devices;
delete from public.follows;
delete from private.follow_pushes;
delete from private.follow_announced;
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select 'https://example.invalid'::text, 'x'::text $$;

insert into public.event_sources(slug,name,kind,base_url) values ('test_radar','Test','manual','https://example.invalid');
insert into public.artists(name,key,kind,source) values ('Радар Ікс','радар ікс','group','manual'),('Радар Ігрек','радар ігрек',null,'auto'),
 ('Радар Зет','радар зет','person','auto');
select set_config('test.x',(select id::text from public.artists where key='радар ікс'),true),
 set_config('test.y',(select id::text from public.artists where key='радар ігрек'),true),
 set_config('test.z',(select id::text from public.artists where key='радар зет'),true);

create function pg_temp.ev(p_name text,p_artist text,p_city text,p_title text,p_start interval) returns void language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
 insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
  origin,source_id,source_uid,import_status,quality)
 values (v_id,p_title,'','music',p_city,'Buoy',-41.1,-31.1,now()+p_start,now()+p_start+interval '2 hours','Europe/Kyiv',
  'import',(select id from public.event_sources where slug='test_radar'),p_name,'live',0.9);
 insert into public.event_artists(event_id,artist_id,role,position,how,confidence)
 values (v_id,current_setting('test.'||p_artist)::uuid,'headliner',0,'rules',0.9);
 perform set_config('test.'||p_name,v_id::text,true);
end $$;
select pg_temp.ev('kyiv1','x','Київ','Ікс у Києві',interval '10 days');
select pg_temp.ev('kyiv2','x','Київ','Ікс у Києві',interval '11 days'); -- той самий прокат
select pg_temp.ev('lviv1','x','Львів','Ікс у Львові',interval '5 days');
select pg_temp.ev('odesa1','x','Одеса','Ікс в Одесі',interval '7 days');
select pg_temp.ev('ykyiv','y','Київ','Ігрек у Києві',interval '3 days');
-- Зет — найактивніший у Києві: 40 різних вечорів, щоб обійти справжню афішу бази в «Кого слухаєте?». За ним не стежать.
select pg_temp.ev('z'||n,'z','Київ','Зет, вечір '||n,(n||' days')::interval) from generate_series(1,40) n;

-- Токени у форматі APNs.
select set_config('test.g',md5('guest')||md5('guest2'),true), set_config('test.h',md5('nocity')||md5('nocity2'),true);

do $$
declare r jsonb;
begin
 -- Формат.
 begin perform public.set_radar(current_setting('test.g'),'web','Київ','{}'); raise exception 'platform accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PLATFORM'; end;
 begin perform public.set_radar('nope','ios','Київ','{}'); raise exception 'token accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_TOKEN'; end;
 begin perform public.set_radar(current_setting('test.g'),'ios','Ocean','{}'); raise exception 'city accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_CITY'; end;
 begin perform public.set_radar(current_setting('test.g'),'ios','Київ',array(select gen_random_uuid() from generate_series(1,201))); raise exception '201 accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_ARTISTS'; end;
 assert has_function_privilege('anon','public.set_radar(text,text,text,uuid[])','execute'),'guest can set radar';
 assert has_function_privilege('anon','public.artist_radar(uuid[],text)','execute'),'guest can read radar';
 assert not has_function_privilege('anon','private.notify_radar_devices()','execute'),'guest cannot push';

 -- Гість у Києві стежить за Іксом; невідомий id відкинуто.
 perform public.set_radar(current_setting('test.g'),'ios','Київ',array[current_setting('test.x')::uuid, gen_random_uuid()]);
 assert (select count(*) from private.radar_artists where token=current_setting('test.g'))=1,'unknown artist dropped';
 -- Події Ікса з'явились раніше за підписку: не нові.
 assert private.notify_radar_devices()=0,'events before the follow are not new';
 -- Підписка була годину тому — тепер усі події Ікса нові.
 update private.radar_artists set created_at=now()-interval '1 hour';
 assert private.notify_radar_devices()=1,'one push for the guest';
 r := (select payload from pg_temp.sent);
 assert r->>'type'='follow' and r->>'kind'='artist' and r->>'token'=current_setting('test.g') and r->>'platform'='ios','addressed to the device';
 assert r->>'total'='1' and r->'event_ids'=jsonb_build_array(current_setting('test.kyiv1')),'only Kyiv, one run: '||r::text;
 assert not exists (select 1 from private.radar_announced where event_id=current_setting('test.lviv1')::uuid),'Lviv stays unannounced';

 -- Раз на добу; і після доби вдруге про те саме не кажемо.
 assert private.notify_radar_devices()=0,'daily limit';
 update private.radar_pushes set sent_at=now()-interval '25 hours';
 assert private.notify_radar_devices()=0,'nothing new after a day';

 -- Новий список: Ікс зберігає свою дату, Ігрек — свіжий, тож про його старшу подію мовчимо.
 perform public.set_radar(current_setting('test.g'),'ios','Київ',array[current_setting('test.x')::uuid, current_setting('test.y')::uuid]);
 assert (select created_at from private.radar_artists where token=current_setting('test.g') and artist_id=current_setting('test.x')::uuid)
   < now()-interval '30 minutes','kept artist keeps its date';
 assert private.notify_radar_devices()=0,'new artist: older events are not new';

 -- Пристрій без міста — без фільтра.
 perform public.set_radar(current_setting('test.h'),'ios',null,array[current_setting('test.x')::uuid]);
 update private.radar_artists set created_at=now()-interval '1 hour' where token=current_setting('test.h');
 delete from pg_temp.sent;
 assert private.notify_radar_devices()=1,'device without a city';
 assert (select (payload->>'total')::int from pg_temp.sent)=3,'all cities, Kyiv run once: '||(select payload::text from pg_temp.sent);

 -- Далі людина ввійде з цього пристрою: забуваємо, що йому вже казали, щоб мовчання було саме через акаунт.
 delete from private.radar_pushes where token=current_setting('test.h');
 delete from private.radar_announced where token=current_setting('test.h');
end $$;

-- Акаунти: u (місто з радару — Львів), v (місто з каналу повернення — Одеса), w (міста не знаємо).
select set_config('test.u',gen_random_uuid()::text,true),set_config('test.v',gen_random_uuid()::text,true),
 set_config('test.w',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-radar-'||id||'@example.invalid',jsonb_build_object('display_name','R','birth_date','1990-01-01')
from unnest(array[current_setting('test.u'),current_setting('test.v'),current_setting('test.w')]) id;
insert into public.push_tokens(token,user_id,platform) values
 (current_setting('test.h'),current_setting('test.u')::uuid,'ios'),
 ('radar-test-v-0123456789',current_setting('test.v')::uuid,'android'),
 ('radar-test-w-0123456789',current_setting('test.w')::uuid,'android');
insert into private.devices(token,platform,city) values ('radar-test-v-0123456789','android','Одеса');
update private.radar_devices set city='Львів' where token=current_setting('test.h');
insert into public.follows(user_id,target_kind,target_id,created_at)
select id::uuid,'artist',current_setting('test.x')::uuid,now()-interval '1 hour'
from unnest(array[current_setting('test.u'),current_setting('test.v'),current_setting('test.w')]) id;

do $$
declare r jsonb;
begin
 delete from pg_temp.sent;
 assert private.notify_radar_devices()=0,'a signed-in device is left to the account';
 assert private.notify_artist_follows()=3,'three accounts';
 r := (select payload from pg_temp.sent where payload->>'user_id'=current_setting('test.u'));
 assert r->'event_ids'=jsonb_build_array(current_setting('test.lviv1')),'u: Lviv only: '||r::text;
 r := (select payload from pg_temp.sent where payload->>'user_id'=current_setting('test.v'));
 assert r->'event_ids'=jsonb_build_array(current_setting('test.odesa1')),'v: city from the winback device: '||r::text;
 r := (select payload from pg_temp.sent where payload->>'user_id'=current_setting('test.w'));
 assert (r->>'total')::int=3,'w: no city, no filter: '||r::text;

 -- «Ваші артисти».
 r := public.artist_radar(array[current_setting('test.x')::uuid, current_setting('test.y')::uuid],'Київ');
 assert jsonb_array_length(r)=2,'two artists';
 r := (select x from jsonb_array_elements(r) x where x->>'id'=current_setting('test.x'));
 assert r->'next'->>'id'=current_setting('test.kyiv1') and (r->>'in_city')::int=1,'next in Kyiv, one run: '||r::text;
 assert jsonb_array_length(r->'elsewhere')=2 and r->'elsewhere'->0->>'city'='Львів','elsewhere, nearest first: '||r::text;
 assert public.artist_radar('{}','Київ')='[]'::jsonb,'empty list';

 -- «Кого слухаєте?»: Зет — перший у Києві, і там рахуються вечори, а не сеанси; у Харкові його нема.
 r := public.popular_artists('Київ',60);
 assert r->0->>'id'=current_setting('test.z') and (r->0->>'upcoming')::int=40,'most active first: '||(r->0)::text;
 assert not exists (select 1 from jsonb_array_elements(public.popular_artists('Харків',60)) x
   where x->>'id'=current_setting('test.z')),'not in Kharkiv';
 assert public.popular_artists(null)='[]'::jsonb,'no city';

 -- Забуття й чистка.
 perform public.forget_radar(current_setting('test.g'));
 assert not exists (select 1 from private.radar_artists where token=current_setting('test.g')),'forget removes artists';
 update private.radar_devices set updated_at=now()-interval '121 days' where token=current_setting('test.h');
 perform private.notify_radar_devices();
 assert not exists (select 1 from private.radar_devices where token=current_setting('test.h')),'120 days cleanup';
end $$;

rollback;
select 'artist_radar: ok' as result;

-- Запускати адміністратором бази. Усе відкочується. «Шукаю компанію»: супутник імпортованої події,
-- вікно часу й місткість, один на людину, картки без імен, замок на час і місце, блокування.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.parent',gen_random_uuid()::text,true),set_config('test.past',gen_random_uuid()::text,true),
 set_config('test.room',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-companion-'||id||'@example.invalid',jsonb_build_object('display_name','Companion','birth_date','1990-01-01')
from unnest(array[current_setting('test.host'),current_setting('test.guest')]) id;
insert into public.event_sources(slug,name,kind,base_url) values ('test_companions','Test','manual','https://example.invalid');
insert into public.places(name,city,address,latitude,longitude,source) values ('Зал Супутник','Ocean','Buoy, 1',-40.5,-30.5,'osm');
insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,origin,source_id,source_uid,import_status,place_id) values
 (current_setting('test.parent')::uuid,'Концерт','','music','Ocean','Buoy, 1',-40.5,-30.5,date_trunc('minute',now())+interval '5 hours',date_trunc('minute',now())+interval '8 hours','Europe/Kyiv',
  'import',(select id from public.event_sources where slug='test_companions'),'c1','live',(select id from public.places where name='Зал Супутник')),
 (current_setting('test.past')::uuid,'Минулий','','music','Ocean','Buoy, 1',-40.5,-30.5,now()-interval '1 hour',now()+interval '2 hours','Europe/Kyiv',
  'import',(select id from public.event_sources where slug='test_companions'),'c2','live',null);
select set_config('test.start',(select starts_at::text from public.events where id=current_setting('test.parent')::uuid),true),
 set_config('test.end',(select ends_at::text from public.events where id=current_setting('test.parent')::uuid),true);
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity) values
 (current_setting('test.room')::uuid,current_setting('test.host')::uuid,'Room','Test description','social','Ocean','Buoy',-40.5,-30.5,now()+interval '1 day',now()+interval '1 day 2 hours','UTC',10);

-- Гість без акаунта створити не може: нема гранту.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.create_companion(current_setting('test.parent')::uuid,now()+interval '4 hours'); raise exception 'anon created';
 exception when insufficient_privilege then null; end;
 assert (select count(*) from public.companions(current_setting('test.parent')::uuid))=0, 'nobody yet';
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ declare v_id uuid; v_again uuid; v_start timestamptz := current_setting('test.start')::timestamptz; begin
 v_id := public.create_companion(current_setting('test.parent')::uuid, v_start-interval '30 minutes', '  Біля головного входу  ', 4);
 perform set_config('test.companion', v_id::text, true);
 v_again := public.create_companion(current_setting('test.parent')::uuid, v_start-interval '1 hour', null, 6);
 assert v_again=v_id, 'one live companion per person: retry returns it';
 assert (select r.companion_of=current_setting('test.parent')::uuid and r.companion_of_title='Концерт' from public.event_details(v_id) r), 'details carry the parent';
 begin perform public.create_companion(current_setting('test.past')::uuid, now()+interval '1 hour'); raise exception 'started parent accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='COMPANION_UNAVAILABLE'; end;
 begin perform public.create_companion(current_setting('test.room')::uuid, now()+interval '23 hours'); raise exception 'community parent accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='COMPANION_UNAVAILABLE'; end;
 -- Час, місце й місткість лишаються такими, як їх створили; посилання на чат — як завжди.
 begin perform public.update_event(v_id,'Йдемо разом: Концерт','Йдемо разом на «Концерт». Збір: Біля головного входу','music','Ocean','Buoy, 1',-40.5,-30.5,
   v_start-interval '1 hour',current_setting('test.end')::timestamptz,'Europe/Kyiv',4,null,18,null,true,null); raise exception 'companion moved';
 exception when sqlstate 'P0001' then assert sqlerrm='COMPANION_LOCKED'; end;
 perform public.update_event(v_id,'Йдемо разом: Концерт','Йдемо разом на «Концерт». Збір: Біля головного входу','music','Ocean','Buoy, 1',-40.5,-30.5,
   v_start-interval '30 minutes',current_setting('test.end')::timestamptz,'Europe/Kyiv',4,null,18,null,true,'https://t.me/test');
end $$;
reset role;
do $$ declare e public.events; p public.events; begin
 select * into p from public.events where id=current_setting('test.parent')::uuid;
 select * into e from public.events where id=current_setting('test.companion')::uuid;
 assert e.companion_of=p.id and e.origin='community' and e.organizer_id=current_setting('test.host')::uuid, 'community companion of the parent';
 assert e.title='Йдемо разом: Концерт' and e.description='Йдемо разом на «Концерт». Збір: Біля головного входу', 'title and description built by the server';
 assert e.meet_note='Біля головного входу' and e.capacity=4 and e.approval_required and e.min_age=18, 'note trimmed, capacity, by request, 18+';
 assert e.starts_at=p.starts_at-interval '30 minutes' and e.ends_at=p.ends_at, 'meets before the start, ends with the parent';
 assert (e.city,e.address,e.latitude,e.longitude,e.category,e.time_zone,e.place_id)=(p.city,p.address,p.latitude,p.longitude,p.category,p.time_zone,p.place_id), 'place inherited';
 assert (select count(*) from public.events where companion_of=p.id)=1, 'retry created nothing';
 assert e.contact_url='https://t.me/test', 'chat link still editable';
end $$;

-- Правила часу й місткості — на іншому акаунті: у господаря вже є супутник, і повтор повернув би його.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
do $$ declare p record; c record; begin
 select current_setting('test.parent')::uuid as id, current_setting('test.start')::timestamptz as starts_at into p;
 begin perform public.create_companion(p.id, p.starts_at+interval '1 minute'); raise exception 'meet after start';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_MEET_TIME'; end;
 begin perform public.create_companion(p.id, p.starts_at-interval '3 hours 1 minute'); raise exception 'meet too early';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_MEET_TIME'; end;
 begin perform public.create_companion(p.id, now()-interval '1 minute'); raise exception 'meet in the past';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_MEET_TIME'; end;
 begin perform public.create_companion(p.id, p.starts_at, null, 1); raise exception 'capacity 1';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_CAPACITY'; end;
 begin perform public.create_companion(p.id, p.starts_at, null, 9); raise exception 'capacity 9';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_CAPACITY'; end;
 begin perform public.create_companion(p.id, p.starts_at, repeat('x',141)); raise exception 'long note';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_MEET_NOTE'; end;
 -- Картка: без імен, запит не займає місця.
 select * into c from public.companions(p.id);
 assert c.membership='none' and not c.mine and c.capacity=4 and c.attendee_count=0 and c.meet_note='Біля головного входу', 'stranger sees a card';
 perform public.join_event(c.id);
 select * into c from public.companions(p.id);
 assert c.membership='requested' and c.attendee_count=0, 'join is a request';
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ declare c record; begin
 select * into c from public.companions(current_setting('test.parent')::uuid);
 assert c.mine, 'own companion is marked';
 perform public.approve_member(c.id,current_setting('test.guest')::uuid);
 select * into c from public.companions(current_setting('test.parent')::uuid);
 assert c.attendee_count=1, 'approved guest counts';
end $$;
reset role;

-- Блокування ховає супутник так само, як подію.
insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.guest')::uuid,current_setting('test.host')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
do $$ begin assert (select count(*) from public.companions(current_setting('test.parent')::uuid))=0, 'blocked organizer hidden'; end $$;
reset role;
delete from public.user_blocks where user_id=current_setting('test.guest')::uuid;

-- Скасований зникає з карток, і можна створити новий.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ declare v_old uuid; v_new uuid; begin
 select id into v_old from public.companions(current_setting('test.parent')::uuid);
 perform public.cancel_event(v_old);
 assert (select count(*) from public.companions(current_setting('test.parent')::uuid))=0, 'cancelled hidden';
 v_new := public.create_companion(current_setting('test.parent')::uuid,current_setting('test.start')::timestamptz);
 assert v_new<>v_old, 'new one after cancel';
 perform set_config('test.second', v_new::text, true);
end $$;
reset role;
do $$ begin
 assert (select capacity from public.events where id=current_setting('test.second')::uuid)=4, 'default capacity 4';
 assert (select count(*) from public.events where companion_of=current_setting('test.parent')::uuid)=2, 'refusals created nothing';
end $$;

-- Батько приховано — картки теж.
update public.events set status='hidden' where id=current_setting('test.parent')::uuid;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin assert (select count(*) from public.companions(current_setting('test.parent')::uuid))=0, 'hidden parent shows nothing'; end $$;
reset role;
select 'PASS: companion created from import, window/capacity/note rules, one per person, cards without names, locked, blocks, cancel' as result;
rollback;

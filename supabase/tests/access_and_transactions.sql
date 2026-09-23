-- Запускати адміністратором бази. Усе, включно з тестовими auth-користувачами, відкочується.
begin;
select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),set_config('test.c',gen_random_uuid()::text,true),set_config('test.event',gen_random_uuid()::text,true);
-- Фікстури мають дату народження: без віку приєднання відмовляє.
insert into auth.users(id,email,raw_user_meta_data) values
(current_setting('test.a')::uuid,'poruch-test-a-'||current_setting('test.a')||'@example.invalid',jsonb_build_object('display_name','Host','birth_date','1990-01-01')),
(current_setting('test.b')::uuid,'poruch-test-b-'||current_setting('test.b')||'@example.invalid',jsonb_build_object('display_name','Guest','birth_date','1990-01-01')),
(current_setting('test.c')::uuid,'poruch-test-c-'||current_setting('test.c')||'@example.invalid',jsonb_build_object('birth_date','1990-01-01'));
do $$ begin
 assert (select display_name='Host' from public.profiles where id=current_setting('test.a')::uuid),'profile trigger';
 assert (select count(*)=3 from public.user_preferences where user_id in (current_setting('test.a')::uuid,current_setting('test.b')::uuid,current_setting('test.c')::uuid)),'preferences trigger';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
select public.create_event(current_setting('test.event')::uuid,'Test event','Test description','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',1,null);
select public.create_event(current_setting('test.event')::uuid,'Retry does not duplicate','Test description','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',1,null);
do $$ begin
 assert (select count(*)=1 from public.events where id=current_setting('test.event')::uuid),'idempotent create';
 begin perform public.join_event(current_setting('test.event')::uuid); raise exception 'expected organizer exclusion'; exception when sqlstate 'P0001' then if sqlerrm <> 'ORGANIZER_CANNOT_JOIN' then raise; end if; end;
 begin perform public.create_event(gen_random_uuid(),'Past event','Test description','social','Kyiv','Park',50,30,now()-interval '1 day',now()+interval '1 day','Europe/Kyiv',1,null); raise exception 'expected past rejection'; exception when sqlstate '22023' then assert sqlerrm='START_MUST_BE_FUTURE'; end;
 begin perform public.create_event(gen_random_uuid(),'Bad coordinate','Test description','social','Kyiv','Park',91,30,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',1,null); raise exception 'expected coordinate rejection'; exception when check_violation then null; end;
 begin perform public.create_event(gen_random_uuid(),'Zero capacity','Test description','social','Kyiv','Park',50,30,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',0,null); raise exception 'expected capacity rejection'; exception when check_violation then null; end;
 begin perform public.create_event(gen_random_uuid(),'Short text','Ура','social','Kyiv','Park',50,30,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',1,null); raise exception 'expected description rejection'; exception when sqlstate '22023' then assert sqlerrm='INVALID_DESCRIPTION'; end;
 begin perform public.create_event(gen_random_uuid(),'Bad timezone','Test description','social','Kyiv','Park',50,30,now()+interval '1 day',now()+interval '2 days','Fake/Zone',1,null); raise exception 'expected timezone rejection'; exception when sqlstate '22023' then assert sqlerrm='INVALID_TIME_ZONE'; end;
 begin perform public.create_event(gen_random_uuid(),'Bad end','Test description','social','Kyiv','Park',50,30,now()+interval '2 days',now()+interval '1 day','Europe/Kyiv',1,null); raise exception 'expected end rejection'; exception when check_violation then null; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
insert into public.saved_events(user_id,event_id) values(auth.uid(),current_setting('test.event')::uuid);
select public.join_event(current_setting('test.event')::uuid);
select public.join_event(current_setting('test.event')::uuid);
do $$ begin
 assert (select attendee_count=1 and joined from public.event_details(current_setting('test.event')::uuid)),'duplicate join';
 assert (select count(*)=1 from public.event_members where event_id=current_setting('test.event')::uuid),'member roster';
 assert (select count(*)=1 from public.my_events() where id=current_setting('test.event')::uuid),'my joined/saved event';
 begin update public.events set title='Hacked' where id=current_setting('test.event')::uuid; raise exception 'direct update allowed'; exception when insufficient_privilege then null; end;
 begin insert into public.event_members(event_id,user_id) values(current_setting('test.event')::uuid,current_setting('test.c')::uuid); raise exception 'direct join allowed'; exception when insufficient_privilege then null; end;
 begin perform public.update_event(current_setting('test.event')::uuid,'Hacked','','social','Kyiv','Park',50,30,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',2,null); raise exception 'unauthorized edit'; exception when insufficient_privilege then assert sqlerrm='NOT_ORGANIZER'; end;
 begin perform public.cancel_event(current_setting('test.event')::uuid); raise exception 'unauthorized cancel'; exception when insufficient_privilege then assert sqlerrm='NOT_ORGANIZER'; end;
 update public.profiles set display_name='Changed other user' where id=current_setting('test.a')::uuid;
 assert (select display_name='Host' from public.profiles where id=current_setting('test.a')::uuid),'profile ownership';
 assert not private.owns_image_path(current_setting('test.a')||'/'||current_setting('test.event')||'/x.jpg'),'storage ownership';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.c'),true);
do $$ begin
 assert (select count(*)=0 from public.saved_events),'private saved events';
 assert (select count(*)=1 from public.user_preferences),'private preferences';
 assert (select count(*)=0 from public.event_members),'nonmember roster hidden';
 assert (select attendee_count=1 and not joined from public.event_details(current_setting('test.event')::uuid)),'aggregate visible';
 begin insert into public.saved_events(user_id,event_id) values(current_setting('test.b')::uuid,current_setting('test.event')::uuid); raise exception 'foreign save allowed'; exception when insufficient_privilege then null; end;
 begin perform public.join_event(current_setting('test.event')::uuid); raise exception 'over capacity'; exception when sqlstate 'P0001' then if sqlerrm <> 'EVENT_FULL' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
do $$ begin
 begin perform public.update_event(current_setting('test.event')::uuid,'Test event','','social','Kyiv','Park',50,30,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',0,null); raise exception 'capacity reduced below attendance'; exception when sqlstate 'P0001' then if sqlerrm <> 'CAPACITY_BELOW_ATTENDANCE' then raise; end if; end;
 assert private.owns_image_path(current_setting('test.a')||'/'||current_setting('test.event')||'/x.jpg'),'storage host path';
end $$;
select public.cancel_event(current_setting('test.event')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
do $$ begin
 assert (select status='cancelled' from public.my_events() where id=current_setting('test.event')::uuid),'cancelled history retained';
 begin perform public.join_event(current_setting('test.event')::uuid); raise exception 'cancelled join allowed'; exception when sqlstate 'P0001' then if sqlerrm <> 'EVENT_CANCELLED' then raise; end if; end;
end $$;
select public.leave_event(current_setting('test.event')::uuid);
select public.leave_event(current_setting('test.event')::uuid);
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 assert (select count(*)=0 from public.event_details(current_setting('test.event')::uuid)),'cancelled hidden from guest';
 assert (select count(*)=0 from public.events_in_view(49,29,51,32) where id=current_setting('test.event')::uuid),'cancelled excluded discovery';
 begin perform public.join_event(current_setting('test.event')::uuid); raise exception 'guest join allowed'; exception when insufficient_privilege then null; end;
 begin select * from public.saved_events; raise exception 'guest private reads allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: auth trigger, idempotency, access isolation, immutable organizer, capacity, cancellation, storage ownership, validation' as result;
rollback;

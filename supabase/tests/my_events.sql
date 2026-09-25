-- Запускати адміністратором бази. Фікстури не зберігаються.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.c',gen_random_uuid()::text,true),set_config('test.event',gen_random_uuid()::text,true),
 set_config('test.past',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select u.id::uuid,'poruch-mine-'||u.id||'@example.invalid',jsonb_build_object('display_name','User','birth_date','1990-01-01')
from unnest(array[current_setting('test.host'),current_setting('test.b'),current_setting('test.c')]) u(id);
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values(current_setting('test.event')::uuid,current_setting('test.host')::uuid,'Mine test','Queue in my events','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',1),
 (current_setting('test.past')::uuid,current_setting('test.host')::uuid,'Mine past','Rated later','social','Kyiv','Podil',50.46,30.52,
 now()-interval '1 day',now()-interval '20 hours','Europe/Kyiv',5);
insert into public.event_members(event_id,user_id,status) values(current_setting('test.past')::uuid,current_setting('test.b')::uuid,'approved');

set local role authenticated;
do $$ begin
 -- b займає єдине місце, c стає в чергу — і бачить подію серед своїх.
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true);
 perform public.join_event(current_setting('test.event')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.c'),true);
 perform public.join_waitlist(current_setting('test.event')::uuid);
 assert (select count(*)=1 from public.my_events() r where r.id=current_setting('test.event')::uuid),'queued event is in my events';
 assert (select count(*)=0 from public.my_events() r where r.id=current_setting('test.past')::uuid),'unrelated event is not';

 -- Бал видно лише автору.
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true);
 assert (select count(*)=0 from public.my_ratings()),'no ratings yet';
 perform public.rate_event(current_setting('test.past')::uuid,4);
 assert (select score=4 from public.my_ratings() where event_id=current_setting('test.past')::uuid),'own score is returned';
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert (select count(*)=0 from public.my_ratings()),'organizer sees no one else''s scores here';
end $$;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.my_ratings(); raise exception 'guest read ratings';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: queued events in my_events, my_ratings private to the author, guests refused' as result;
rollback;

-- Run as database administrator. No fixtures persist.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.c',gen_random_uuid()::text,true),set_config('test.d',gen_random_uuid()::text,true),
 set_config('test.e',gen_random_uuid()::text,true),set_config('test.event',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select u.id::uuid,'poruch-wait-'||u.id||'@example.invalid',jsonb_build_object('display_name','User')
from unnest(array[current_setting('test.host'),current_setting('test.b'),current_setting('test.c'),
 current_setting('test.d'),current_setting('test.e')]) u(id);
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values(current_setting('test.event')::uuid,current_setting('test.host')::uuid,'Waitlist test','Queue behaviour','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',2);

set local role authenticated;
-- Two people fill the only two places.
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
select public.join_event(current_setting('test.event')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.c'),true);
select public.join_event(current_setting('test.event')::uuid);

do $$ begin
 -- A full event refuses an outright join but accepts a queue position.
 perform set_config('request.jwt.claim.sub',current_setting('test.d'),true);
 begin perform public.join_event(current_setting('test.event')::uuid); raise exception 'full event accepted a join';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_FULL','join refusal is EVENT_FULL'; end;
 perform public.join_waitlist(current_setting('test.event')::uuid);
 perform public.join_waitlist(current_setting('test.event')::uuid);
 assert (select count(*)=1 from public.event_waitlist where event_id=current_setting('test.event')::uuid),'queueing twice is idempotent';

 -- Members and the organizer have no business in the queue.
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true);
 begin perform public.join_waitlist(current_setting('test.event')::uuid); raise exception 'member queued';
 exception when sqlstate 'P0001' then assert sqlerrm='ALREADY_MEMBER','member refusal is ALREADY_MEMBER'; end;
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 begin perform public.join_waitlist(current_setting('test.event')::uuid); raise exception 'organizer queued';
 exception when sqlstate 'P0001' then assert sqlerrm='ORGANIZER_CANNOT_JOIN','organizer refusal is ORGANIZER_CANNOT_JOIN'; end;

 -- A second person joins the queue behind the first.
 perform set_config('request.jwt.claim.sub',current_setting('test.e'),true);
 perform public.join_waitlist(current_setting('test.event')::uuid);
end $$;

reset role;
-- now() is the transaction timestamp, so both queue rows share created_at. Separate them so the
-- promotion order the queue promises is genuinely exercised.
update public.event_waitlist set created_at = now() - interval '1 hour'
 where event_id=current_setting('test.event')::uuid and user_id=current_setting('test.d')::uuid;
set local role authenticated;

do $$ begin
 -- The queue is private: each person reads only their own position.
 perform set_config('request.jwt.claim.sub',current_setting('test.d'),true);
 assert (select count(*)=1 from public.my_waitlist()),'own queue position is visible';
 assert (select count(*)=1 from public.event_waitlist),'own row only';
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true);
 assert (select count(*)=0 from public.my_waitlist()),'a member holds no position';
 assert (select count(*)=0 from public.event_waitlist),'other queue rows stay hidden';

 -- Leaving frees a place and the head of the queue takes it.
 perform public.leave_event(current_setting('test.event')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.d'),true);
 assert (select joined from public.event_details(current_setting('test.event')::uuid)),'first in queue was promoted';
 assert (select count(*)=0 from public.my_waitlist()),'promotion clears the position';
 assert (select attendee_count=2 from public.event_details(current_setting('test.event')::uuid)),'capacity still respected';
 perform set_config('request.jwt.claim.sub',current_setting('test.e'),true);
 assert (select count(*)=1 from public.my_waitlist()),'second in queue still waits';
end $$;

-- Raising capacity is the other way a place appears.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.update_event(current_setting('test.event')::uuid,'Waitlist test','Queue behaviour','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',3,null);

do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.e'),true);
 assert (select joined from public.event_details(current_setting('test.event')::uuid)),'raising capacity promotes the queue';
 assert (select count(*)=0 from public.my_waitlist()),'promotion clears the position';
 assert (select attendee_count=3 from public.event_details(current_setting('test.event')::uuid)),'all three places are taken';
end $$;

-- With room to spare there is nothing to queue for.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.update_event(current_setting('test.event')::uuid,'Waitlist test','Queue behaviour','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',5,null);

do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true);
 begin perform public.join_waitlist(current_setting('test.event')::uuid); raise exception 'queued an event with space';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_HAS_SPACE','refusal is EVENT_HAS_SPACE'; end;
 -- Leaving a queue you are not in is a no-op rather than an error.
 perform public.leave_waitlist(current_setting('test.event')::uuid);
end $$;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.join_waitlist(current_setting('test.event')::uuid); raise exception 'guest queued';
 exception when insufficient_privilege then null; end;
 begin perform public.my_waitlist(); raise exception 'guest read the queue';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: full events queue, promotion on leave and on capacity growth, private positions, guests refused' as result;
rollback;

-- Run as database administrator. No fixtures persist.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.member',gen_random_uuid()::text,true),
 set_config('test.other',gen_random_uuid()::text,true),set_config('test.stranger',gen_random_uuid()::text,true),
 set_config('test.event',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-host-'||current_setting('test.host')||'@example.invalid','{"display_name":"Host"}'::jsonb),
 (current_setting('test.member')::uuid,'poruch-member-'||current_setting('test.member')||'@example.invalid','{"display_name":"Member"}'::jsonb),
 (current_setting('test.other')::uuid,'poruch-other-'||current_setting('test.other')||'@example.invalid','{"display_name":"Other"}'::jsonb),
 (current_setting('test.stranger')::uuid,'poruch-stranger-'||current_setting('test.stranger')||'@example.invalid','{"display_name":"Stranger"}'::jsonb);
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values(current_setting('test.event')::uuid,current_setting('test.host')::uuid,'Roster test','Attendee roster','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
select public.join_event(current_setting('test.event')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.other'),true);
select public.join_event(current_setting('test.event')::uuid);
reset role;
-- now() is the transaction timestamp, so both joins carry an identical joined_at. Separate them so
-- the ordering the function promises is actually exercised rather than decided by the uuid tiebreak.
update public.event_members set joined_at = now() - interval '1 hour'
 where event_id=current_setting('test.event')::uuid and user_id=current_setting('test.member')::uuid;
set local role authenticated;

do $$ begin
 -- A member reads the whole roster and its display names.
 perform set_config('request.jwt.claim.sub',current_setting('test.member'),true);
 assert (select count(*)=2 from public.event_attendees(current_setting('test.event')::uuid)),'member reads roster';
 assert (select bool_and(display_name is not null) from public.event_attendees(current_setting('test.event')::uuid)),'roster carries names';
 assert (select user_id from public.event_attendees(current_setting('test.event')::uuid) limit 1)=current_setting('test.member')::uuid,'ordered by join time';

 -- The organizer reads it too, even without being a member.
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert (select count(*)=2 from public.event_attendees(current_setting('test.event')::uuid)),'organizer reads roster';

 -- A signed-in stranger sees nobody: the member policy still governs identities.
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
 assert (select count(*)=0 from public.event_attendees(current_setting('test.event')::uuid)),'stranger sees no identities';
 assert (select attendee_count=2 from public.event_details(current_setting('test.event')::uuid)),'stranger still sees the count';

 -- Bounds are clamped rather than trusted.
 perform set_config('request.jwt.claim.sub',current_setting('test.member'),true);
 assert (select count(*)=1 from public.event_attendees(current_setting('test.event')::uuid,1)),'limit honoured';
 assert (select count(*)=1 from public.event_attendees(current_setting('test.event')::uuid,0)),'limit clamped up to one';
 assert (select count(*)=2 from public.event_attendees(current_setting('test.event')::uuid,10000)),'limit clamped down to the roster';
 assert (select count(*)=2 from public.event_attendees(current_setting('test.event')::uuid,null)),'null limit falls back to the default';
end $$;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin
  perform public.event_attendees(current_setting('test.event')::uuid);
  raise exception 'guest reached the roster';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
select 'PASS: roster visible to organizer and members, hidden from strangers and guests, limits clamped' as result;
rollback;

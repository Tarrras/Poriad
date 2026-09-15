-- Запускати адміністратором бази. Фікстури не зберігаються.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.c',gen_random_uuid()::text,true),set_config('test.d',gen_random_uuid()::text,true),
 set_config('test.e',gen_random_uuid()::text,true),set_config('test.event',gen_random_uuid()::text,true);
-- Фікстури мають дату народження: без віку приєднання відмовляє.
insert into auth.users(id,email,raw_user_meta_data)
select u.id::uuid,'poruch-wait-'||u.id||'@example.invalid',jsonb_build_object('display_name','User','birth_date','1990-01-01')
from unnest(array[current_setting('test.host'),current_setting('test.b'),current_setting('test.c'),
 current_setting('test.d'),current_setting('test.e')]) u(id);
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values(current_setting('test.event')::uuid,current_setting('test.host')::uuid,'Waitlist test','Queue behaviour','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',2);

set local role authenticated;
-- Двоє займають обидва місця.
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
select public.join_event(current_setting('test.event')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.c'),true);
select public.join_event(current_setting('test.event')::uuid);

do $$ begin
 -- Повна подія відмовляє в приєднанні, але приймає в чергу.
 perform set_config('request.jwt.claim.sub',current_setting('test.d'),true);
 begin perform public.join_event(current_setting('test.event')::uuid); raise exception 'full event accepted a join';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_FULL','join refusal is EVENT_FULL'; end;
 perform public.join_waitlist(current_setting('test.event')::uuid);
 perform public.join_waitlist(current_setting('test.event')::uuid);
 assert (select count(*)=1 from public.event_waitlist where event_id=current_setting('test.event')::uuid),'queueing twice is idempotent';

 -- Учасникам і організатору в черзі нема чого робити.
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true);
 begin perform public.join_waitlist(current_setting('test.event')::uuid); raise exception 'member queued';
 exception when sqlstate 'P0001' then assert sqlerrm='ALREADY_MEMBER','member refusal is ALREADY_MEMBER'; end;
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 begin perform public.join_waitlist(current_setting('test.event')::uuid); raise exception 'organizer queued';
 exception when sqlstate 'P0001' then assert sqlerrm='ORGANIZER_CANNOT_JOIN','organizer refusal is ORGANIZER_CANNOT_JOIN'; end;

 -- Другий стає в чергу за першим.
 perform set_config('request.jwt.claim.sub',current_setting('test.e'),true);
 perform public.join_waitlist(current_setting('test.event')::uuid);
end $$;

reset role;
-- now() однаковий у транзакції, тож розводимо created_at, щоб перевірити порядок просування.
update public.event_waitlist set created_at = now() - interval '1 hour'
 where event_id=current_setting('test.event')::uuid and user_id=current_setting('test.d')::uuid;
set local role authenticated;

do $$ begin
 -- Черга приватна: кожен бачить лише свою позицію.
 perform set_config('request.jwt.claim.sub',current_setting('test.d'),true);
 assert (select count(*)=1 from public.my_waitlist()),'own queue position is visible';
 assert (select count(*)=1 from public.event_waitlist),'own row only';
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true);
 assert (select count(*)=0 from public.my_waitlist()),'a member holds no position';
 assert (select count(*)=0 from public.event_waitlist),'other queue rows stay hidden';

 -- Вихід звільняє місце, його займає голова черги.
 perform public.leave_event(current_setting('test.event')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.d'),true);
 assert (select joined from public.event_details(current_setting('test.event')::uuid)),'first in queue was promoted';
 assert (select count(*)=0 from public.my_waitlist()),'promotion clears the position';
 assert (select attendee_count=2 from public.event_details(current_setting('test.event')::uuid)),'capacity still respected';
 perform set_config('request.jwt.claim.sub',current_setting('test.e'),true);
 assert (select count(*)=1 from public.my_waitlist()),'second in queue still waits';
end $$;

-- Збільшення місткості теж звільняє місце.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.update_event(current_setting('test.event')::uuid,'Waitlist test','Queue behaviour','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',3,null);

do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.e'),true);
 assert (select joined from public.event_details(current_setting('test.event')::uuid)),'raising capacity promotes the queue';
 assert (select count(*)=0 from public.my_waitlist()),'promotion clears the position';
 assert (select attendee_count=3 from public.event_details(current_setting('test.event')::uuid)),'all three places are taken';
end $$;

-- З вільними місцями в чергу не стають.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.update_event(current_setting('test.event')::uuid,'Waitlist test','Queue behaviour','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',5,null);

do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true);
 begin perform public.join_waitlist(current_setting('test.event')::uuid); raise exception 'queued an event with space';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_HAS_SPACE','refusal is EVENT_HAS_SPACE'; end;
 -- Вийти з черги, в якій не стоїш, — не помилка.
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

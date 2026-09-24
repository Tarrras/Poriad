-- Запускати адміністратором бази. Фікстури не зберігаються.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.member',gen_random_uuid()::text,true),
 set_config('test.asker',gen_random_uuid()::text,true),set_config('test.stranger',gen_random_uuid()::text,true),
 set_config('test.event',gen_random_uuid()::text,true),set_config('test.past',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','birth_date','1990-01-01')),
 (current_setting('test.member')::uuid,'poruch-member-'||current_setting('test.member')||'@example.invalid',jsonb_build_object('display_name','Member','birth_date','1990-01-01')),
 (current_setting('test.asker')::uuid,'poruch-asker-'||current_setting('test.asker')||'@example.invalid',jsonb_build_object('display_name','Asker','birth_date','1990-01-01')),
 (current_setting('test.stranger')::uuid,'poruch-stranger-'||current_setting('test.stranger')||'@example.invalid',jsonb_build_object('display_name','Stranger','birth_date','1990-01-01'));
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,approval_required)
values(current_setting('test.event')::uuid,current_setting('test.host')::uuid,'Profile test','Profile card visibility','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,true);
-- Минула подія з підтвердженим учасником: лічильник «відвідав».
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values(current_setting('test.past')::uuid,current_setting('test.host')::uuid,'Past profile test','Past event for counters','social','Kyiv','Podil',50.46,30.52,
 now()-interval '2 days',now()-interval '2 days'+interval '3 hours','Europe/Kyiv',10);
insert into public.event_members(event_id,user_id,status) values
 (current_setting('test.past')::uuid,current_setting('test.member')::uuid,'approved'),
 (current_setting('test.event')::uuid,current_setting('test.member')::uuid,'approved'),
 (current_setting('test.event')::uuid,current_setting('test.asker')::uuid,'requested');

do $$ begin
 -- Наявні акаунти отримали дату з auth.users (у фікстур її нема: там NULL).
 assert not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where u.created_at<>p.created_at),'created_at from auth';
end $$;

set local role authenticated;
do $$ begin
 -- Свій профіль: з поштою з JWT.
 perform set_config('request.jwt.claim.sub',current_setting('test.member'),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.member'),'email','me@example.invalid')::text,true);
 assert (select email='me@example.invalid' and attended=1 and organized=0 from public.profile_card(current_setting('test.member')::uuid)),'own card with email and counters';
 -- Учасник бачить організатора, але не його пошту.
 assert (select email is null and organized=2 from public.profile_card(current_setting('test.host')::uuid)),'member sees organizer without email';
 -- Той, хто проситься, не підтверджений: інших учасників не бачить, організатора — так.
 perform set_config('request.jwt.claims','{}',true);
 perform set_config('request.jwt.claim.sub',current_setting('test.asker'),true);
 assert (select count(*)=0 from public.profile_card(current_setting('test.member')::uuid)),'asker does not see members';
 assert (select count(*)=1 from public.profile_card(current_setting('test.host')::uuid)),'asker sees organizer';
 -- Організатор бачить того, хто проситься.
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert (select count(*)=1 from public.profile_card(current_setting('test.asker')::uuid)),'organizer sees asker';
 -- Сторонній: організатора опублікованої події — так, учасника — ні.
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
 assert (select count(*)=1 from public.profile_card(current_setting('test.host')::uuid)),'stranger sees public organizer';
 assert (select count(*)=0 from public.profile_card(current_setting('test.member')::uuid)),'stranger does not see member';

 -- Редагування: bio, стоп-словник, довжина.
 perform set_config('request.jwt.claim.sub',current_setting('test.member'),true);
 update public.profiles set display_name='Member Renamed', bio='Люблю настолки' where id=current_setting('test.member')::uuid;
 assert (select display_name='Member Renamed' and bio='Люблю настолки' from public.profiles where id=current_setting('test.member')::uuid),'own profile edit';
 begin update public.profiles set bio=repeat('x',301) where id=current_setting('test.member')::uuid; raise exception 'expected bio length';
 exception when check_violation then null; end;
 -- Фото: лише з теки avatar свого uid.
 begin update public.profiles set avatar_url='https://abc.supabase.co/storage/v1/object/public/event-images/'||current_setting('test.member')||'/'||current_setting('test.event')||'/a.jpg'
  where id=current_setting('test.member')::uuid; raise exception 'expected avatar path check';
 exception when sqlstate '22023' then null; end;
 update public.profiles set avatar_url='https://abc.supabase.co/storage/v1/object/public/event-images/'||current_setting('test.member')||'/avatar/a.jpg'
  where id=current_setting('test.member')::uuid;
 -- Storage: свій аватар так, чужий і вкладений — ні.
 assert private.owns_image_path(current_setting('test.member')||'/avatar/b.jpg'),'own avatar path';
 assert not private.owns_image_path(current_setting('test.host')||'/avatar/b.jpg'),'foreign avatar path';
 assert not private.owns_image_path(current_setting('test.member')||'/avatar/x/b.jpg'),'nested avatar path';
 assert not private.owns_image_path(current_setting('test.member')||'/'||current_setting('test.event')||'/b.jpg'),'foreign event path';
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert private.owns_image_path(current_setting('test.host')||'/'||current_setting('test.event')||'/b.jpg'),'own event path still works';

 -- Блокування ховає картку в обидва боки.
 insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.host')::uuid,current_setting('test.stranger')::uuid);
 assert (select count(*)=0 from public.profile_card(current_setting('test.stranger')::uuid)),'blocker does not see card';
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
 assert (select count(*)=0 from public.profile_card(current_setting('test.host')::uuid)),'blocked does not see card';
end $$;

-- Модерація: не модератор — відмова.
do $$ begin
 begin perform public.moderate_profile(current_setting('test.member')::uuid,'clear_bio'); raise exception 'expected moderator check';
 exception when others then if sqlerrm='expected moderator check' then raise; end if; end;
end $$;
reset role;
insert into private.moderators(user_id) values (current_setting('test.host')::uuid);
set local role authenticated;
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.moderate_profile(current_setting('test.member')::uuid,'clear_avatar');
 perform public.moderate_profile(current_setting('test.member')::uuid,'clear_bio');
 perform public.moderate_profile(current_setting('test.member')::uuid,'reset_name');
end $$;
reset role;
do $$ begin
 assert (select avatar_url is null and bio is null and display_name='Учасник' from public.profiles where id=current_setting('test.member')::uuid),'moderation cleared profile';
end $$;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.profile_card(current_setting('test.host')::uuid); raise exception 'guest reached a card';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: profile card visibility, own email, counters, edit checks, avatar paths, blocks, moderation' as result;
rollback;

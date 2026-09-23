-- Запускати адміністратором бази. Усе відкочується. Оцінки як UGC (С1), автоприховування лише
-- активними акаунтами старше трьох днів (С2), блокування на користувача в лімітах (С3),
-- видимість профілів, вигнання заблокованого, перевірка імені й аватара.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.member',gen_random_uuid()::text,true),
 set_config('test.critic',gen_random_uuid()::text,true),set_config('test.stranger',gen_random_uuid()::text,true),
 set_config('test.mod',gen_random_uuid()::text,true),
 set_config('test.past',gen_random_uuid()::text,true),set_config('test.future',gen_random_uuid()::text,true),
 set_config('test.target',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data,created_at)
select (current_setting('test.'||k))::uuid,'poruch-test-'||k||'-'||current_setting('test.'||k)||'@example.invalid',
 jsonb_build_object('display_name',initcap(k),'birth_date',to_char(current_date - interval '30 years','YYYY-MM-DD')),now()-interval '10 days'
from unnest(array['host','member','critic','stranger','mod']) k;
insert into private.moderators(user_id) values (current_setting('test.mod')::uuid);
-- Реєстрація з лайкою в імені не падає, ім'я стає нейтральним.
select set_config('test.rude',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values (current_setting('test.rude')::uuid,'poruch-test-rude-'||current_setting('test.rude')||'@example.invalid',
 jsonb_build_object('display_name','сука','birth_date','1990-01-01'));
do $$ begin
 assert (select display_name='Учасник' from public.profiles where id=current_setting('test.rude')::uuid),'objectionable signup name replaced';
end $$;

-- Завершена подія (напряму: create_event не приймає минуле) і майбутня.
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values (current_setting('test.past')::uuid,current_setting('test.host')::uuid,'Past night','','games','Kyiv','Park',50.45,30.52,now()-interval '2 days',now()-interval '1 day','Europe/Kyiv',10),
 (current_setting('test.future')::uuid,current_setting('test.host')::uuid,'Future night','','games','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',10),
 (current_setting('test.target')::uuid,current_setting('test.host')::uuid,'Target night','','games','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',10);
insert into public.event_members(event_id,user_id,status) values
 (current_setting('test.past')::uuid,current_setting('test.member')::uuid,'approved'),
 (current_setting('test.past')::uuid,current_setting('test.critic')::uuid,'approved'),
 (current_setting('test.future')::uuid,current_setting('test.member')::uuid,'approved'),
 (current_setting('test.future')::uuid,current_setting('test.critic')::uuid,'approved');

set local role authenticated;

-- С1. Стоп-словник і блокування в оцінках.
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
do $$ begin
 begin perform public.rate_event(current_setting('test.past')::uuid,1,'організатор сука'); raise exception 'expected objectionable rejection';
 exception when sqlstate '22023' then assert sqlerrm='OBJECTIONABLE_CONTENT'; end;
end $$;
select public.rate_event(current_setting('test.past')::uuid,2,'Нудно й холодно');
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
insert into public.user_blocks(user_id,blocked_id) values (auth.uid(),current_setting('test.critic')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.critic'),true);
do $$ begin
 begin perform public.rate_event(current_setting('test.past')::uuid,1,'Жах'); raise exception 'expected block rejection';
 exception when sqlstate '42501' then assert sqlerrm='BLOCKED'; end;
end $$;

-- Блокування виганяє з майбутньої події організатора (і з чату), минула лишається як була.
reset role;
do $$ begin
 assert not exists(select 1 from public.event_members where event_id=current_setting('test.future')::uuid and user_id=current_setting('test.critic')::uuid),'blocked member evicted from a future event';
 assert exists(select 1 from public.event_members where event_id=current_setting('test.past')::uuid and user_id=current_setting('test.critic')::uuid),'finished event untouched';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.critic'),true);
do $$ begin
 begin perform public.send_message(current_setting('test.future')::uuid,'Я ще тут?'); raise exception 'expected chat closed for the blocked';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;

-- Скарга організатора на коментар і модерація.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select set_config('test.rating_at',(select created_at::text from public.event_ratings(current_setting('test.past')::uuid) limit 1),true);
select set_config('test.rating_report',public.report_rating(current_setting('test.past')::uuid,current_setting('test.rating_at')::timestamptz,'harassment')::text,true);
select set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
do $$ begin
 begin perform public.report_rating(current_setting('test.past')::uuid,current_setting('test.rating_at')::timestamptz,'spam'); raise exception 'expected only the organizer';
 exception when sqlstate 'P0002' then assert sqlerrm='RATING_NOT_FOUND'; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.mod'),true);
do $$ begin
 assert (select subject_type='rating' and message_body='Нудно й холодно' and not message_hidden
  from public.moderation_queue() where report_id=current_setting('test.rating_report')::uuid),'rating report in the queue with its comment';
end $$;
select public.moderate_rating(current_setting('test.past')::uuid,current_setting('test.member')::uuid,'hide');
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 assert (select comment is null and score=2 from public.event_ratings(current_setting('test.past')::uuid)),'hidden comment not shown to the organizer, score stays';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
do $$ begin
 assert (select comment='Нудно й холодно' from public.event_ratings(current_setting('test.past')::uuid)),'the author still sees their own comment';
end $$;

-- Профілі: сторонній не бачить нікого, учасник — організатора й інших учасників, організатор — заблокованого.
select set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
do $$ begin
 assert (select count(*)=1 from public.profiles where id in (current_setting('test.host')::uuid,current_setting('test.member')::uuid,current_setting('test.stranger')::uuid)),'a stranger sees only themself';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
do $$ begin
 assert exists(select 1 from public.profiles where id=current_setting('test.host')::uuid),'member sees the organizer';
 assert exists(select 1 from public.profiles where id=current_setting('test.critic')::uuid),'member sees a co-member';
 assert not exists(select 1 from public.profiles where id=current_setting('test.stranger')::uuid),'member does not see a stranger';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 assert exists(select 1 from public.profiles where id=current_setting('test.critic')::uuid),'organizer sees whom they blocked';
end $$;

-- Ім'я через стоп-словник, аватар — лише файл власника у своєму проєкті (проєкт з iss токена).
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.member'),'role','authenticated',
 'iss','https://ojadoyxeahepycpmjuvf.supabase.co/auth/v1')::text,true);
do $$ begin
 begin update public.profiles set display_name='москаль' where id=auth.uid(); raise exception 'expected name rejection';
 exception when sqlstate '22023' then assert sqlerrm='OBJECTIONABLE_CONTENT'; end;
 begin update public.profiles set avatar_url='https://tracker.example/pixel.png' where id=auth.uid(); raise exception 'expected foreign avatar rejection';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_IMAGE_URL'; end;
 begin update public.profiles set avatar_url='https://evilref.supabase.co/storage/v1/object/public/event-images/'||auth.uid()||'/a.jpg' where id=auth.uid();
  raise exception 'expected other project rejection';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_IMAGE_URL'; end;
 update public.profiles set avatar_url='https://ojadoyxeahepycpmjuvf.supabase.co/storage/v1/object/public/event-images/'||auth.uid()||'/a.jpg' where id=auth.uid();
 assert (select avatar_url like 'https://ojadoyxeahepycpmjuvf.supabase.co/%' from public.profiles where id=auth.uid()),'own storage avatar accepted';
 begin perform public.create_event(gen_random_uuid(),'Street night','Description','games','Kyiv','Гашиш-бар',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5);
  raise exception 'expected address rejection';
 exception when sqlstate '22023' then assert sqlerrm='OBJECTIONABLE_CONTENT'; end;
end $$;
select set_config('request.jwt.claims','',true);

-- С3. Ліміти беруть блокування на користувача: паралельний запит того ж акаунта чекає.
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
select public.send_message(current_setting('test.future')::uuid,'Привіт');
do $$ declare k bigint := hashtextextended('rl:'||auth.uid()::text,0); begin
 assert exists(select 1 from pg_locks where locktype='advisory' and pid=pg_backend_pid()
  and classid::bigint=((k>>32) & 4294967295) and objid::bigint=(k & 4294967295)),'send_message holds the per-user rate-limit lock';
end $$;

-- С2. Три скарги від свіжих акаунтів подію не ховають; від старших за три дні активних — ховають;
-- обмежений акаунт скаржитись не може.
reset role;
select set_config('test.f'||i,gen_random_uuid()::text,true) from generate_series(1,3) i;
select set_config('test.o'||i,gen_random_uuid()::text,true) from generate_series(1,4) i;
insert into auth.users(id,email,raw_user_meta_data,created_at)
select current_setting('test.'||k)::uuid,'poruch-test-'||k||'-'||current_setting('test.'||k)||'@example.invalid',
 jsonb_build_object('birth_date','1990-01-01'), case when k like 'f%' then now() else now()-interval '4 days' end
from unnest(array['f1','f2','f3','o1','o2','o3','o4']) k;
update public.account_facts set status='limited' where user_id=current_setting('test.o3')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.f1'),true);
select public.report_event(current_setting('test.target')::uuid,'spam',null);
select set_config('request.jwt.claim.sub',current_setting('test.f2'),true);
select public.report_event(current_setting('test.target')::uuid,'spam',null);
select set_config('request.jwt.claim.sub',current_setting('test.f3'),true);
select public.report_event(current_setting('test.target')::uuid,'spam',null);
reset role;
do $$ begin
 assert (select status='published' from public.events where id=current_setting('test.target')::uuid),'fresh accounts do not hide an event';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.o3'),true);
do $$ begin
 begin perform public.report_event(current_setting('test.target')::uuid,'spam',null); raise exception 'expected restricted rejection';
 exception when sqlstate '42501' then assert sqlerrm='ACCOUNT_RESTRICTED'; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.o1'),true);
select public.report_event(current_setting('test.target')::uuid,'spam',null);
select set_config('request.jwt.claim.sub',current_setting('test.o2'),true);
select public.report_event(current_setting('test.target')::uuid,'spam',null);
reset role;
do $$ begin
 assert (select status='published' from public.events where id=current_setting('test.target')::uuid),'two established reporters are not enough';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.o4'),true);
select public.report_event(current_setting('test.target')::uuid,'spam',null);
reset role;
do $$ begin
 assert (select status='hidden' from public.events where id=current_setting('test.target')::uuid),'three established reporters hide the event';
end $$;
rollback;

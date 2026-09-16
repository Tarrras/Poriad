-- Запускати адміністратором бази. Усе відкочується. Чат події: пишуть свої, читають свої,
-- сторонній і запит без відповіді — ні; ліміти, видалення, скарга, блокування.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.member',gen_random_uuid()::text,true),
 set_config('test.stranger',gen_random_uuid()::text,true),set_config('test.asking',gen_random_uuid()::text,true),
 set_config('test.event',gen_random_uuid()::text,true);

insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-test-host-'||current_setting('test.host')||'@example.invalid',
  jsonb_build_object('display_name','Host','birth_date',to_char(current_date - interval '30 years','YYYY-MM-DD'))),
 (current_setting('test.member')::uuid,'poruch-test-member-'||current_setting('test.member')||'@example.invalid',
  jsonb_build_object('display_name','Member','birth_date',to_char(current_date - interval '24 years','YYYY-MM-DD'))),
 (current_setting('test.stranger')::uuid,'poruch-test-stranger-'||current_setting('test.stranger')||'@example.invalid',
  jsonb_build_object('display_name','Stranger','birth_date',to_char(current_date - interval '26 years','YYYY-MM-DD'))),
 (current_setting('test.asking')::uuid,'poruch-test-asking-'||current_setting('test.asking')||'@example.invalid',
  jsonb_build_object('display_name','Asking','birth_date',to_char(current_date - interval '27 years','YYYY-MM-DD')));

set local role authenticated;

-- Подія з підтвердженням: учасник прийнятий, ще один лише проситься.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.create_event(current_setting('test.event')::uuid,'Chat night','Description here','games','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,true);
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
select public.join_event(current_setting('test.event')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.asking'),true);
select public.join_event(current_setting('test.event')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.approve_member(current_setting('test.event')::uuid,current_setting('test.member')::uuid);

-- Організатор і учасник пишуть; порожнє й задовге не проходить.
select set_config('test.m1',public.send_message(current_setting('test.event')::uuid,'Привіт усім!')::text,true);
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
select set_config('test.m2',public.send_message(current_setting('test.event')::uuid,'  Буду о сьомій  ')::text,true);
-- В одній транзакції обидва мають один `now()`: розсуваємо, щоб порядок справді перевірявся.
reset role;
update public.event_messages set created_at=created_at-interval '1 minute' where id=current_setting('test.m1')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
do $$ begin
 begin perform public.send_message(current_setting('test.event')::uuid,'   '); raise exception 'expected empty rejection';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_MESSAGE'; end;
 begin perform public.send_message(current_setting('test.event')::uuid,repeat('a',2001)); raise exception 'expected length rejection';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_MESSAGE'; end;
 assert (select count(*)=2 from public.event_messages(current_setting('test.event')::uuid)),'member reads both';
 assert (select body='Буду о сьомій' and author_name='Member' from public.event_messages(current_setting('test.event')::uuid) offset 1 limit 1),'trimmed, oldest first, with a name';
end $$;

-- Дозавантаження: лише пізніше за відоме.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 assert (select count(*)=1 from public.event_messages(current_setting('test.event')::uuid,
  (select created_at from public.event_messages where id=current_setting('test.m1')::uuid))),'after returns only the newer one';
 assert (select count(*)=1 from public.event_messages(current_setting('test.event')::uuid,null,1)),'limit keeps the latest';
 assert (select id=current_setting('test.m2')::uuid from public.event_messages(current_setting('test.event')::uuid,null,1)),'the latest is the newest';
end $$;

-- Сторонній не читає й не пише; запит без відповіді читає ростер, але не чат.
select set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
do $$ begin
 assert (select count(*)=0 from public.event_messages(current_setting('test.event')::uuid)),'a stranger reads nothing';
 begin perform public.send_message(current_setting('test.event')::uuid,'Hi'); raise exception 'expected member check';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.asking'),true);
do $$ begin
 begin perform public.send_message(current_setting('test.event')::uuid,'Hi'); raise exception 'expected member check';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;

-- Скарга на повідомлення йде на автора з подією і текстом; своє повідомлення — ні.
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
select set_config('test.report',public.report_message(current_setting('test.m1')::uuid,'harassment','Образи')::text,true);
do $$ begin
 assert (select subject_type='user' and subject_user_id=current_setting('test.host')::uuid and event_id=current_setting('test.event')::uuid
  and message_id=current_setting('test.m1')::uuid and details like 'Образи%Привіт усім!%' from public.reports where id=current_setting('test.report')::uuid),'report carries author, event and text';
 begin perform public.report_message(current_setting('test.m2')::uuid,'spam',null); raise exception 'expected self-report rejection';
 exception when sqlstate 'P0001' then assert sqlerrm='CANNOT_REPORT_SELF'; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
do $$ begin
 begin perform public.report_message(current_setting('test.m1')::uuid,'spam',null); raise exception 'expected invisibility';
 exception when sqlstate 'P0002' then assert sqlerrm='MESSAGE_NOT_FOUND'; end;
end $$;

-- Видалення: автор своє, організатор будь-яке, учасник чуже — ні.
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
select public.delete_message(current_setting('test.m1')::uuid);
do $$ begin
 assert (select count(*)=2 from public.event_messages(current_setting('test.event')::uuid)),'a member cannot delete the host''s message';
end $$;
select public.delete_message(current_setting('test.m2')::uuid);
do $$ begin
 assert (select count(*)=1 from public.event_messages(current_setting('test.event')::uuid)),'the author deletes their own';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.delete_message(current_setting('test.m1')::uuid);
do $$ begin
 assert (select count(*)=0 from public.event_messages(current_setting('test.event')::uuid)),'the organizer deletes anything';
end $$;

-- Ліміт двадцять на хвилину.
do $$ begin
 for i in 1..20 loop perform public.send_message(current_setting('test.event')::uuid,'msg '||i); end loop;
 begin perform public.send_message(current_setting('test.event')::uuid,'one more'); raise exception 'expected rate limit';
 exception when sqlstate 'P0001' then assert sqlerrm='TOO_MANY_MESSAGES'; end;
end $$;

-- Блокування ховає повідомлення в обидва боки.
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.member')::uuid,current_setting('test.host')::uuid);
do $$ begin
 assert (select count(*)=0 from public.event_messages(current_setting('test.event')::uuid)),'blocking hides the host''s messages';
end $$;
delete from public.user_blocks where user_id=current_setting('test.member')::uuid;

-- Скасована подія закриває чат на запис, читання лишається.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.cancel_event(current_setting('test.event')::uuid);
do $$ begin
 begin perform public.send_message(current_setting('test.event')::uuid,'late'); raise exception 'expected closed chat';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_CANCELLED'; end;
 assert (select count(*)=20 from public.event_messages(current_setting('test.event')::uuid)),'history stays readable';
end $$;

-- Гість без акаунта не має гранту.
reset role;
set local role anon;
do $$ begin
 begin perform public.event_messages(current_setting('test.event')::uuid); raise exception 'expected missing grant';
 exception when insufficient_privilege then null; end;
end $$;

rollback;

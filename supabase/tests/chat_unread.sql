-- Запускати адміністратором бази. Усе відкочується. Непрочитане в чатах: свої повідомлення не
-- рахуються, позначка «прочитано» обнуляє, нове після неї знову рахується, сторонній нічого не бачить.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.member',gen_random_uuid()::text,true),
 set_config('test.stranger',gen_random_uuid()::text,true),set_config('test.event',gen_random_uuid()::text,true);

insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-test-host-'||current_setting('test.host')||'@example.invalid',
  jsonb_build_object('display_name','Host','birth_date',to_char(current_date - interval '30 years','YYYY-MM-DD'))),
 (current_setting('test.member')::uuid,'poruch-test-member-'||current_setting('test.member')||'@example.invalid',
  jsonb_build_object('display_name','Member','birth_date',to_char(current_date - interval '24 years','YYYY-MM-DD'))),
 (current_setting('test.stranger')::uuid,'poruch-test-stranger-'||current_setting('test.stranger')||'@example.invalid',
  jsonb_build_object('display_name','Stranger','birth_date',to_char(current_date - interval '26 years','YYYY-MM-DD')));

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.create_event(current_setting('test.event')::uuid,'Unread night','Description here','games','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null);
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
select public.join_event(current_setting('test.event')::uuid);

-- Порожній чат — нічого непрочитаного.
do $$ begin
 assert (select count(*)=0 from public.my_chat_unread()),'nothing unread in an empty chat';
end $$;

-- Організатор пише двічі: учасник бачить 2, організатор — 0 (своє не рахується).
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select set_config('test.m1',public.send_message(current_setting('test.event')::uuid,'Перше')::text,true);
select set_config('test.m2',public.send_message(current_setting('test.event')::uuid,'Друге')::text,true);
reset role;
update public.event_messages set created_at=created_at-interval '1 minute' where id=current_setting('test.m1')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 assert (select count(*)=0 from public.my_chat_unread()),'own messages are not unread';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
do $$ begin
 assert (select count(*)=1 from public.my_chat_unread()),'one event with unread';
 assert (select unread=2 and event_title='Unread night' and last_message_id=current_setting('test.m2')::uuid
  and last_author_name='Host' and last_body='Друге' from public.my_chat_unread()),'count and preview of the newest';
end $$;

-- Прочитано: обнуляється; нове після позначки знову рахується.
select public.mark_chat_read(current_setting('test.event')::uuid);
do $$ begin
 assert (select count(*)=0 from public.my_chat_unread()),'read marks clear the count';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select set_config('test.m3',public.send_message(current_setting('test.event')::uuid,'Третє')::text,true);
reset role;
-- Той самий now() у транзакції: позначка й нове повідомлення збігаються; зсуваємо нове вперед.
update public.event_messages set created_at=created_at+interval '1 minute' where id=current_setting('test.m3')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
do $$ begin
 assert (select unread=1 and last_message_id=current_setting('test.m3')::uuid from public.my_chat_unread()),'a newer message counts again';
 assert (select count(*)=1 from public.chat_reads),'a member reads only their own mark';
end $$;

-- Сторонній: ні зведення, ні позначки.
select set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
do $$ begin
 assert (select count(*)=0 from public.my_chat_unread()),'a stranger has nothing';
 begin perform public.mark_chat_read(current_setting('test.event')::uuid); raise exception 'expected member check';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;

-- Скасована подія випадає зі зведення.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.cancel_event(current_setting('test.event')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
do $$ begin
 assert (select count(*)=0 from public.my_chat_unread()),'a cancelled event drops out';
end $$;

-- Гість без акаунта не має гранту.
reset role;
set local role anon;
do $$ begin
 begin perform public.my_chat_unread(); raise exception 'expected missing grant';
 exception when insufficient_privilege then null; end;
end $$;

rollback;

-- Запускати адміністратором бази. Усе відкочується. «Запитати організатора» (20261116120000): розмова на двох —
-- питає сторонній, бачать лише він і організатор; організатор першим не пише; загальний чат і його бейдж питань не
-- бачать; афіша без організатора й блокування — ні; непрочитане, профіль організатора для того, хто питав, пуш.
begin;

-- Пуші ловимо в таблицю замість pg_net.
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;

select set_config('test.host',gen_random_uuid()::text,true),set_config('test.member',gen_random_uuid()::text,true),
 set_config('test.asker',gen_random_uuid()::text,true),set_config('test.other',gen_random_uuid()::text,true),
 set_config('test.event',gen_random_uuid()::text,true),set_config('test.listing',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select current_setting('test.'||k)::uuid,'poruch-questions-'||k||'-'||current_setting('test.'||k)||'@example.invalid',
 jsonb_build_object('display_name',initcap(k),'birth_date',to_char(current_date - interval '30 years','YYYY-MM-DD'))
from unnest(array['host','member','asker','other']) k;

-- Афіша без організатора в застосунку.
insert into public.event_sources(slug,name,kind,base_url,enabled) values ('test_questions','Test','manual','https://example.invalid',true);
insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,origin,source_id,source_uid,import_status,quality)
values (current_setting('test.listing')::uuid,'Концерт','','music','Kyiv','Hall',50.45,30.52,now()+interval '1 day',now()+interval '1 day 2 hours',
 'Europe/Kyiv','import',(select id from public.event_sources where slug='test_questions'),'q1','live',0.9);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.create_event(current_setting('test.event')::uuid,'Настолки','Description here','games','Kyiv','Park',50.45,30.52,
 now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,false);
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
select public.join_event(current_setting('test.event')::uuid);
select set_config('test.general',public.send_message(current_setting('test.event')::uuid,'Привіт усім')::text,true);

-- Організатор першим не пише: розмови з asker ще нема.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 begin perform public.send_message(current_setting('test.event')::uuid,'Йдете?',current_setting('test.asker')::uuid);
  raise exception 'expected organizer cold message rejection';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
 begin perform public.send_message(current_setting('test.event')::uuid,'Сам собі',current_setting('test.host')::uuid);
  raise exception 'expected self question rejection';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;

-- Сторонній питає; у загальний чат його й далі не пускає.
select set_config('request.jwt.claim.sub',current_setting('test.asker'),true);
select set_config('test.q1',public.send_message(current_setting('test.event')::uuid,'  Треба мати свої ігри?  ',current_setting('test.asker')::uuid)::text,true);
-- В одній транзакції в усіх один `now()`: розсуваємо, щоб «останнє» й непрочитане справді перевірялись.
reset role;
update public.event_messages set created_at=created_at-interval '10 minutes'
 where id in (current_setting('test.q1')::uuid,current_setting('test.general')::uuid);
set local role authenticated;
do $$ begin
 assert (select count(*)=1 from public.event_messages(current_setting('test.event')::uuid,null,100,current_setting('test.asker')::uuid)),'asker reads own thread';
 assert (select body='Треба мати свої ігри?' from public.event_messages(current_setting('test.event')::uuid,null,100,current_setting('test.asker')::uuid)),'trimmed';
 assert (select count(*)=0 from public.event_messages(current_setting('test.event')::uuid)),'asker still outside the general chat';
 begin perform public.send_message(current_setting('test.event')::uuid,'А можна в чат?'); raise exception 'expected general chat rejection';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
 assert (select count(*)=1 and bool_and(thread_user_id=current_setting('test.asker')::uuid) and bool_and(last_mine)
  from public.event_questions(current_setting('test.event')::uuid)),'asker sees own thread, last message is theirs';
 begin perform public.send_message(current_setting('test.listing')::uuid,'Є парковка?',current_setting('test.asker')::uuid);
  raise exception 'expected listing rejection';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;

-- Учасник не бачить чужої розмови ні в стрічці, ні в таблиці, ні в списку; у загальному — лише загальне.
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
do $$ begin
 assert (select count(*)=0 from public.event_messages(current_setting('test.event')::uuid,null,100,current_setting('test.asker')::uuid)),'member does not read the thread';
 assert (select count(*)=0 from public.event_messages where thread_user_id is not null),'nor through the table';
 assert (select count(*)=1 from public.event_messages(current_setting('test.event')::uuid)),'general chat has only the general message';
 assert (select count(*)=0 from public.event_questions(current_setting('test.event')::uuid)),'member sees no threads';
 assert not exists(select 1 from public.profiles where id=current_setting('test.asker')::uuid),'member does not see the asker profile';
 begin perform public.send_message(current_setting('test.event')::uuid,'Влізу',current_setting('test.asker')::uuid);
  raise exception 'expected third party rejection';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;

-- Організатор бачить питання з непрочитаним, відповідає; бейдж загального чату про питання не знає.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 assert (select count(*)=1 and min(unread)=1 and bool_and(asker_name='Asker') from public.event_questions(current_setting('test.event')::uuid)),'host sees one unread question';
 assert (select unread=1 from public.my_chat_unread() where event_id=current_setting('test.event')::uuid),'general badge counts only the general message';
 assert (select last_message_id=current_setting('test.general')::uuid from public.my_chat_unread() where event_id=current_setting('test.event')::uuid),'general preview is not the question';
end $$;
select public.mark_chat_read(current_setting('test.event')::uuid,current_setting('test.asker')::uuid);
select set_config('test.a1',public.send_message(current_setting('test.event')::uuid,'Ні, усе є на місці',current_setting('test.asker')::uuid)::text,true);
do $$ begin
 assert (select min(unread)=0 and bool_and(last_mine) from public.event_questions(current_setting('test.event')::uuid)),'read and answered';
end $$;

-- Той, хто питав, бачить відповідь з іменем організатора й непрочитане; після прочитання — нуль.
select set_config('request.jwt.claim.sub',current_setting('test.asker'),true);
do $$ begin
 assert (select count(*)=2 from public.event_messages(current_setting('test.event')::uuid,null,100,current_setting('test.asker')::uuid)),'both messages';
 assert (select author_name='Host' from public.event_messages(current_setting('test.event')::uuid,null,100,current_setting('test.asker')::uuid) offset 1 limit 1),'organizer reply keeps the name';
 assert (select unread=1 and not last_mine from public.event_questions(current_setting('test.event')::uuid)),'one unread reply';
end $$;
select public.mark_chat_read(current_setting('test.event')::uuid,current_setting('test.asker')::uuid);
do $$ begin
 assert (select unread=0 from public.event_questions(current_setting('test.event')::uuid)),'read';
 begin perform public.mark_chat_read(current_setting('test.event')::uuid,current_setting('test.member')::uuid); raise exception 'expected foreign read rejection';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;

-- Інший сторонній відкриває свою розмову, а потім організатор його блокує: далі ні він, ні організатор не пишуть.
select set_config('request.jwt.claim.sub',current_setting('test.other'),true);
select public.send_message(current_setting('test.event')::uuid,'А з собакою можна?',current_setting('test.other')::uuid);
reset role;
insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.host')::uuid,current_setting('test.other')::uuid);
set local role authenticated;
do $$ begin
 begin perform public.send_message(current_setting('test.event')::uuid,'Ще раз?',current_setting('test.other')::uuid); raise exception 'expected blocked asker rejection';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 begin perform public.send_message(current_setting('test.event')::uuid,'Ні',current_setting('test.other')::uuid); raise exception 'expected blocked reply rejection';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER'; end;
end $$;

-- Кожне повідомлення розмови кличе пуш тим самим типом `message`: адресатів вибирає функція push за thread_user_id.
reset role;
do $$ begin
 assert (select count(*)=4 from pg_temp.sent where payload->>'type'='message'),'every message rings: general, question, answer, other';
 assert exists(select 1 from pg_temp.sent where payload->>'message_id'=current_setting('test.a1')),'the answer rings';
end $$;

rollback;

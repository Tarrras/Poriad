-- Запускати адміністратором бази. Усе відкочується. Лист організатору про питання: один на розмову на годину, інша
-- розмова — окремо, рядки йдуть разом з подією, клієнтам функція недоступна.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.a',gen_random_uuid()::text,true),
 set_config('test.b',gen_random_uuid()::text,true),set_config('test.event',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select current_setting('test.'||k)::uuid,'poruch-qmail-'||k||'-'||current_setting('test.'||k)||'@example.invalid',
 jsonb_build_object('display_name','Q','birth_date','1990-01-01')
from unnest(array['host','a','b']) k;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values (current_setting('test.event')::uuid,current_setting('test.host')::uuid,'Питання','Опис для перевірки листів','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',5);

do $$
declare e uuid := current_setting('test.event')::uuid; a uuid := current_setting('test.a')::uuid; b uuid := current_setting('test.b')::uuid;
begin
 assert public.question_mail_due(e, a), 'the first question mails';
 assert not public.question_mail_due(e, a), 'the next one within the hour does not';
 assert public.question_mail_due(e, b), 'another conversation is separate';
 update private.question_mails set sent_at = now() - interval '61 minutes' where thread_user_id = a;
 assert public.question_mail_due(e, a), 'an hour later it mails again';
 assert not public.question_mail_due(e, a), 'and the hour starts over';
 delete from public.events where id = e;
 assert not exists(select 1 from private.question_mails where event_id = e), 'rows go with the event';
 assert not has_function_privilege('anon', 'public.question_mail_due(uuid,uuid,boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.question_mail_due(uuid,uuid,boolean)', 'execute')
  and has_function_privilege('service_role', 'public.question_mail_due(uuid,uuid,boolean)', 'execute'), 'only the function key calls it';
end $$;

rollback;

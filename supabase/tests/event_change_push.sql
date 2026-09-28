-- Запускати адміністратором бази. Усе відкочується. Пуш учасникам: скасування й перенесення
-- майбутньої події — так; інші правки, минулі події й імпорт — ні.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.past',gen_random_uuid()::text,true),set_config('test.later',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-change-'||id||'@example.invalid',jsonb_build_object('display_name','C','birth_date','1990-01-01')
from unnest(array[current_setting('test.host'),current_setting('test.guest')]) id;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity) values
 (current_setting('test.past')::uuid,current_setting('test.host')::uuid,'Past','Test description','social','Kyiv','Podil',50.46,30.52,now()-interval '3 hours',now()-interval '1 hour','Europe/Kyiv',10),
 (current_setting('test.later')::uuid,current_setting('test.host')::uuid,'Later','Test description','social','Kyiv','Podil',50.46,30.52,now()+interval '1 day',now()+interval '1 day 2 hours','Europe/Kyiv',10);
insert into public.event_members(event_id,user_id,status) values (current_setting('test.later')::uuid,current_setting('test.guest')::uuid,'approved');

-- Пуші ловимо в таблицю замість pg_net: заміна функції відкотиться разом з рештою.
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
-- Нова назва без нового часу — не перенесення.
select public.update_event(current_setting('test.later')::uuid,'Later!','Test description','social','Kyiv','Podil',50.46,30.52,
 (select starts_at from public.events where id=current_setting('test.later')::uuid),now()+interval '1 day 2 hours','Europe/Kyiv',10);
reset role;
do $$ begin assert (select count(*)=0 from pg_temp.sent),'edit without a new start pushes nothing'; end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.update_event(current_setting('test.later')::uuid,'Later!','Test description','social','Kyiv','Podil',50.46,30.52,
 now()+interval '2 days',now()+interval '2 days 2 hours','Europe/Kyiv',10);
select public.cancel_event(current_setting('test.later')::uuid);
reset role;
do $$ begin
 assert (select array_agg(payload order by payload->>'kind')=array[
  jsonb_build_object('type','event','kind','cancelled','event_id',current_setting('test.later')),
  jsonb_build_object('type','event','kind','moved','event_id',current_setting('test.later'))] from pg_temp.sent),'moved, then cancelled, once each';
end $$;

-- Минула подія: скасування (напр. модерацією) і зсув часу мовчать.
delete from pg_temp.sent;
update public.events set starts_at=starts_at+interval '10 minutes' where id=current_setting('test.past')::uuid;
update public.events set status='cancelled' where id=current_setting('test.past')::uuid;
-- Імпорт без організатора: конвеєр рухає час, пушів нема.
update public.events set starts_at=starts_at+interval '1 hour'
 where id=(select id from public.events where organizer_id is null and starts_at>now() limit 1);
do $$ begin assert (select count(*)=0 from pg_temp.sent),'past and imported events never push'; end $$;

rollback;

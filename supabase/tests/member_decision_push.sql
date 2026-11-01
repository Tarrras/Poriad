-- Запускати адміністратором бази. Усе відкочується. Пуші учаснику про рішення: прийняв, не прийняв, місце з черги.
-- Не рішення: людина сама скасувала запит, звичайний запис, організатор заблокував того, хто просився, видалення події
-- чи акаунта організатора; тригерні функції клієнтам не видно.
begin;

-- Пуші ловимо в таблицю замість pg_net.
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
-- Перевірки йдуть під роллю клієнта.
grant select, delete on pg_temp.sent to authenticated;

select set_config('test.host',gen_random_uuid()::text,true),set_config('test.a',gen_random_uuid()::text,true),
 set_config('test.b',gen_random_uuid()::text,true),set_config('test.c',gen_random_uuid()::text,true),
 set_config('test.d',gen_random_uuid()::text,true),set_config('test.w',gen_random_uuid()::text,true),
 set_config('test.gated',gen_random_uuid()::text,true),set_config('test.open',gen_random_uuid()::text,true),
 set_config('test.host2',gen_random_uuid()::text,true),set_config('test.gated2',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select current_setting('test.'||k)::uuid,'poruch-decision-'||k||'-'||current_setting('test.'||k)||'@example.invalid',
 jsonb_build_object('display_name','D','birth_date','1990-01-01')
from unnest(array['host','a','b','c','d','w','host2']) k;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,approval_required)
values (current_setting('test.gated')::uuid,current_setting('test.host')::uuid,'За підтвердженням','Опис для перевірки рішень','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',5,true),
 (current_setting('test.open')::uuid,current_setting('test.host')::uuid,'Одне місце','Опис для перевірки рішень','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',1,false),
 (current_setting('test.gated2')::uuid,current_setting('test.host2')::uuid,'Друга за підтвердженням','Опис для перевірки рішень','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',5,true);

create function pg_temp.decisions() returns setof jsonb language sql as $$
 select payload from pg_temp.sent where payload->>'type'='decision' order by payload->>'kind';
$$;
create function pg_temp.decision(p_kind text,p_event text,p_user text) returns jsonb language sql as $$
 select jsonb_build_object('type','decision','kind',p_kind,'event_id',current_setting('test.'||p_event),'user_id',current_setting('test.'||p_user));
$$;

set local role authenticated;
-- a, b і c просять на подію з підтвердженням: це запити, не рішення.
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.a'),true); perform public.join_event(current_setting('test.gated')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true); perform public.join_event(current_setting('test.gated')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.c'),true); perform public.join_event(current_setting('test.gated')::uuid);
 assert not exists(select 1 from pg_temp.decisions()),'a request is not a decision';
end $$;

-- Організатор приймає a й не приймає b; c сама скасовує запит.
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.approve_member(current_setting('test.gated')::uuid,current_setting('test.a')::uuid);
 perform public.decline_member(current_setting('test.gated')::uuid,current_setting('test.b')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.c'),true);
 perform public.leave_event(current_setting('test.gated')::uuid);
 assert array(select pg_temp.decisions()) = array[pg_temp.decision('approved','gated','a'),pg_temp.decision('declined','gated','b')],
  'approved a, declined b, nothing for c who left on her own';
 -- Повторне рішення нічого не шле: рядка `requested` уже нема.
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.approve_member(current_setting('test.gated')::uuid,current_setting('test.a')::uuid);
 perform public.decline_member(current_setting('test.gated')::uuid,current_setting('test.b')::uuid);
 assert (select count(*)=2 from pg_temp.decisions()),'a repeated decision is silent';
end $$;
delete from pg_temp.sent;

-- Одне місце: d записується сам (не рішення), w стає в чергу; d виходить — w підтягується з черги.
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.d'),true); perform public.join_event(current_setting('test.open')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.w'),true); perform public.join_waitlist(current_setting('test.open')::uuid);
 assert not exists(select 1 from pg_temp.decisions()),'own join and queueing are not decisions';
 perform set_config('request.jwt.claim.sub',current_setting('test.d'),true); perform public.leave_event(current_setting('test.open')::uuid);
 assert array(select pg_temp.decisions()) = array[pg_temp.decision('promoted','open','w')],'w gets the freed place';
 assert exists(select 1 from pg_temp.sent where payload->>'type'='joined' and payload->>'user_id'=current_setting('test.w')),
  'the organizer still hears about the join';
end $$;
delete from pg_temp.sent;

-- Вийти з черги без місця — не рішення.
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.d'),true); perform public.join_waitlist(current_setting('test.open')::uuid);
 perform public.leave_waitlist(current_setting('test.open')::uuid);
 assert not exists(select 1 from pg_temp.decisions()),'leaving the queue is not a decision';
end $$;

-- Організатор заблокував того, хто просився: запит зникає, але це не «не прийняв», і заблокованому ми не пишемо.
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.b'),true); perform public.join_event(current_setting('test.gated')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.host')::uuid,current_setting('test.b')::uuid);
 assert not exists(select 1 from public.event_members where event_id=current_setting('test.gated')::uuid and user_id=current_setting('test.b')::uuid),
  'the block removed the request';
 assert not exists(select 1 from pg_temp.decisions()),'a block is not a decline';
end $$;

-- Подію видалено разом із запитами: це не відмова.
reset role;
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.c'),true);
 set local role authenticated;
 perform public.join_event(current_setting('test.gated')::uuid);
 reset role;
 perform set_config('request.jwt.claim.sub','',true);
 delete from public.events where id=current_setting('test.gated')::uuid;
 assert not exists(select 1 from pg_temp.decisions()),'a deleted event declines nobody';
 assert not has_function_privilege('authenticated','private.on_member_decided()','execute')
  and not has_function_privilege('anon','private.on_waitlist_left()','execute'),'trigger functions are not callable by clients';
end $$;

-- Організатор видаляє акаунт (delete-account, з його ж токеном): події й запити йдуть каскадом — це не відмова.
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.c'),true);
 set local role authenticated;
 perform public.join_event(current_setting('test.gated2')::uuid);
 reset role;
 perform set_config('request.jwt.claim.sub',current_setting('test.host2'),true);
 delete from auth.users where id=current_setting('test.host2')::uuid;
 assert not exists(select 1 from public.events where id=current_setting('test.gated2')::uuid),'the event went with the account';
 assert not exists(select 1 from pg_temp.decisions()),'an organizer deleting the account declines nobody';
end $$;

rollback;

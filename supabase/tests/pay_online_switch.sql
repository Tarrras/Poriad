-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Вимикач оплати онлайн — 20261125160000_pay_online_switch: без прапорця подія — «на місці» для всіх, онлайн-подію не
-- створити, реквізитів і скріншотів не прийняти; увімкнули знову — подія знову онлайн.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.online',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-switch-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','adult_confirmed',true)),
 (current_setting('test.guest')::uuid,'poruch-switch-guest-'||current_setting('test.guest')||'@example.invalid',jsonb_build_object('display_name','Guest','adult_confirmed',true));

-- Увімкнено: онлайн-подія, заявка, реквізити в розмові.
update private.flags set enabled = true where name = 'pay_online';
set local role authenticated;
do $$
declare v record;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert public.pay_online_enabled(),'switch on';
 perform public.create_event(current_setting('test.online')::uuid,'Online paid games','Pay online before we meet','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',300,true);
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 perform public.join_event(current_setting('test.online')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.send_message(current_setting('test.online')::uuid,'Картка 4111 1111 1111 1111, 300 грн',current_setting('test.guest')::uuid);
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert v.pay_online,'online while on';
end $$;
reset role;

-- Вимкнено: «на місці» для всіх, нова онлайн-подія — PAY_ONLINE_OFF, реквізити — PAYMENT_DETAILS.
update private.flags set enabled = false where name = 'pay_online';
set local role authenticated;
do $$
declare v record;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert not public.pay_online_enabled(),'switch off';
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert not v.pay_online and v.approval_required,'organizer sees onsite, approval stays';
 begin perform public.create_event(gen_random_uuid(),'Another online','Pay online','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',300,true);
  raise exception 'online event created while off';
 exception when sqlstate 'P0001' then assert sqlerrm='PAY_ONLINE_OFF','no new online events'; end;
 begin perform public.send_message(current_setting('test.online')::uuid,'Ще раз: 4111 1111 1111 1111',current_setting('test.guest')::uuid);
  raise exception 'details accepted while off';
 exception when sqlstate '22023' then assert sqlerrm='PAYMENT_DETAILS','no details while off'; end;
 -- Звичайна розмова працює; правка зі старого клієнта (без p_pay_online) події не ламає.
 perform public.send_message(current_setting('test.online')::uuid,'Оплата на місці, до зустрічі',current_setting('test.guest')::uuid);
 perform public.update_event(current_setting('test.online')::uuid,'Online paid games','Pay at the door','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false);
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert not v.pay_online,'guest sees onsite too';
end $$;
reset role;
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 assert not private.can_upload_proof(current_setting('test.guest')||'/'||current_setting('test.online')||'/'||gen_random_uuid()||'.jpg'),'no proof uploads while off';
end $$;

-- Увімкнули знову — подія знову онлайн: колонку вимикач не чіпав.
update private.flags set enabled = true where name = 'pay_online';
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 assert private.can_upload_proof(current_setting('test.guest')||'/'||current_setting('test.online')||'/'||gen_random_uuid()||'.jpg'),'proof uploads again';
end $$;
set local role authenticated;
do $$
declare v record;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert v.pay_online,'back online after switching on';
end $$;
reset role;
rollback;

-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Безпека оплати онлайн — 20261125170000_pay_online_safety: рівні допуску, згоди, правила повернення, вимикач для
-- організатора за скаргами платників, розмова після скасування, видалення акаунта й докази.
begin;
update private.flags set enabled = true where name = 'pay_online';
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.guest2',gen_random_uuid()::text,true),set_config('test.online',gen_random_uuid()::text,true),
 set_config('test.past',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-safe-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','adult_confirmed',true)),
 (current_setting('test.guest')::uuid,'poruch-safe-guest-'||current_setting('test.guest')||'@example.invalid',jsonb_build_object('display_name','Guest','adult_confirmed',true)),
 (current_setting('test.guest2')::uuid,'poruch-safe-guest2-'||current_setting('test.guest2')||'@example.invalid',jsonb_build_object('display_name','Guest2','adult_confirmed',true));

set local role authenticated;
do $$
declare v record; l jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 -- Без згоди організатора — ні.
 begin perform public.create_event(current_setting('test.online')::uuid,'Online paid games','Pay online before we meet','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',300,true,'before_48h');
  raise exception 'online without organizer terms';
 exception when sqlstate 'P0001' then assert sqlerrm='PAY_TERMS_REQUIRED','organizer terms first'; end;
 perform public.accept_pay_terms('organizer');
 -- Без правил повернення — ні.
 begin perform public.create_event(current_setting('test.online')::uuid,'Online paid games','Pay online before we meet','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',300,true);
  raise exception 'online without refund policy';
 exception when sqlstate '22023' then assert sqlerrm='REFUND_POLICY_REQUIRED','refund policy required'; end;
 -- Новачок: до 500 ₴ і 10 місць.
 begin perform public.create_event(gen_random_uuid(),'Online paid games','Pay online before we meet','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',600,true,'before_48h');
  raise exception 'over the price limit';
 exception when sqlstate 'P0001' then assert sqlerrm='PAY_ONLINE_LIMIT','new organizer price limit'; end;
 begin perform public.create_event(gen_random_uuid(),'Online paid games','Pay online before we meet','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',11,null,18,null,false,null,null,'web',300,true,'before_48h');
  raise exception 'over the capacity limit';
 exception when sqlstate 'P0001' then assert sqlerrm='PAY_ONLINE_LIMIT','new organizer capacity limit'; end;
 -- На місці — без меж.
 perform public.create_event(gen_random_uuid(),'Onsite paid games','Pay at the door when you come','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',200,null,18,null,false,null,null,'web',3000,false);
 perform public.create_event(current_setting('test.online')::uuid,'Online paid games','Pay online before we meet','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',500,true,'before_48h');
 l := public.my_pay_online_limits();
 assert (l->>'level')::int=0 and (l->>'max_price')::int=500 and (l->>'terms')::boolean and (l->'next'->>'held')::int=1,'limits: '||l::text;

 -- Платник — лише зі згодою на цю подію; бачить правила повернення.
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 begin perform public.join_event(current_setting('test.online')::uuid);
  raise exception 'request without payer terms';
 exception when sqlstate 'P0001' then assert sqlerrm='PAY_TERMS_REQUIRED','payer terms first'; end;
 perform public.accept_pay_terms('payer',current_setting('test.online')::uuid);
 perform public.join_event(current_setting('test.online')::uuid);
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert v.membership='requested' and v.refund_policy='before_48h','request with refund policy';
 perform set_config('request.jwt.claim.sub',current_setting('test.guest2'),true);
 perform public.accept_pay_terms('payer',current_setting('test.online')::uuid);
 perform public.join_event(current_setting('test.online')::uuid);

 -- Організатор надсилає реквізити обом.
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.send_message(current_setting('test.online')::uuid,'Картка 4111 1111 1111 1111',current_setting('test.guest')::uuid);
 perform public.send_message(current_setting('test.online')::uuid,'Картка 4111 1111 1111 1111',current_setting('test.guest2')::uuid);
end $$;
reset role;

-- Видалення акаунта з майбутньою онлайн-подією, на яку записались, — спершу скасувати.
do $$ begin
 begin perform private.prepare_account_deletion(current_setting('test.host')::uuid);
  raise exception 'deleted with paid participants';
 exception when sqlstate 'P0001' then assert sqlerrm='PAID_EVENTS_ACTIVE','cancel first'; end;
end $$;

-- Рівень 1: проведена подія з учасником і 30 днів — більші межі.
update auth.users set created_at = now() - interval '40 days' where id = current_setting('test.host')::uuid;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,status)
values (current_setting('test.past')::uuid,current_setting('test.host')::uuid,'Past games meetup','Board games evening that already happened','games','Kyiv','Podil',50.46,30.52,
 now()-interval '3 days',now()-interval '3 days'+interval '2 hours','Europe/Kyiv',10,'published');
insert into public.event_members(event_id,user_id,status) values (current_setting('test.past')::uuid,current_setting('test.guest')::uuid,'approved');
set local role authenticated;
do $$
declare l jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 l := public.my_pay_online_limits();
 assert (l->>'level')::int=1 and (l->>'max_price')::int=1500,'level 1: '||l::text;
end $$;
reset role;

-- Двоє платників скаржаться на шахрайство в розмові — оплату онлайн цьому організатору вимкнено.
set local role authenticated;
do $$
declare v record; m uuid;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 select id into m from public.event_messages(current_setting('test.online')::uuid,null,100,current_setting('test.guest')::uuid) limit 1;
 perform public.report_message(m,'scam',null);
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert (public.my_pay_online_limits()->>'enabled')::boolean,'one report — still allowed';
 perform set_config('request.jwt.claim.sub',current_setting('test.guest2'),true);
 select id into m from public.event_messages(current_setting('test.online')::uuid,null,100,current_setting('test.guest2')::uuid) limit 1;
 perform public.report_message(m,'scam',null);
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert not v.pay_online and v.refund_policy is null,'blocked organizer — onsite for everyone';
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert not (public.my_pay_online_limits()->>'enabled')::boolean,'two payers — blocked';
 begin perform public.send_message(current_setting('test.online')::uuid,'Нова картка 4111 1111 1111 1111',current_setting('test.guest')::uuid);
  raise exception 'details from a blocked organizer';
 exception when sqlstate '22023' then assert sqlerrm='PAYMENT_DETAILS','no details while blocked'; end;
end $$;
reset role;
delete from private.pay_online_blocks where user_id = current_setting('test.host')::uuid;

-- Скасування: розмова про повернення лишається, реквізитів — ні.
set local role authenticated;
do $$
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.cancel_event(current_setting('test.online')::uuid);
 perform public.send_message(current_setting('test.online')::uuid,'Подію скасовано, повертаю гроші',current_setting('test.guest')::uuid);
 begin perform public.send_message(current_setting('test.online')::uuid,'Картка 4111 1111 1111 1111',current_setting('test.guest')::uuid);
  raise exception 'details after cancellation';
 exception when sqlstate '22023' then assert sqlerrm='PAYMENT_DETAILS','no details after cancellation'; end;
 begin perform public.send_message(current_setting('test.online')::uuid,'А в загальному чаті?',null);
  raise exception 'group chat after cancellation';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_CANCELLED','group chat closes'; end;
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 perform public.send_message(current_setting('test.online')::uuid,'Чекаю на повернення',current_setting('test.guest')::uuid);
end $$;
reset role;

-- Тепер видалити можна, а розмови з реквізитами й згоди лишаються доказом на 180 днів.
do $$
declare s jsonb;
begin
 perform private.prepare_account_deletion(current_setting('test.host')::uuid);
 assert (select count(*) from private.payment_evidence where deleted_user_id=current_setting('test.host')::uuid)=2,'two payment threads archived';
 select snapshot into s from private.payment_evidence where deleted_user_id=current_setting('test.host')::uuid limit 1;
 assert s->'organizer'->>'name'='Host' and jsonb_array_length(s->'messages')>=1 and jsonb_array_length(s->'consents')>=2,'evidence: '||s::text;
 assert (select purge_after > now() + interval '179 days' from private.payment_evidence where deleted_user_id=current_setting('test.host')::uuid limit 1),'kept 180 days';
end $$;
rollback;

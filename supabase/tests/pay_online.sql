-- Запускати адміністратором бази. Фікстури не зберігаються.
-- «Оплата онлайн» — 20261125120000_pay_online: спосіб оплати, реквізити лише в розмові онлайн-події, організатор пише
-- першим тим, хто записався, і лист тому, хто питав, не частіше разу на годину.
begin;
-- Оплата онлайн за вимикачем (20261125160000_pay_online_switch) — тут увімкнено; транзакція відкочується.
update private.flags set enabled = true where name = 'pay_online';
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.stranger',gen_random_uuid()::text,true),set_config('test.online',gen_random_uuid()::text,true),
 set_config('test.onsite',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-pay-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','adult_confirmed',true)),
 (current_setting('test.guest')::uuid,'poruch-pay-guest-'||current_setting('test.guest')||'@example.invalid',jsonb_build_object('display_name','Guest','adult_confirmed',true)),
 (current_setting('test.stranger')::uuid,'poruch-pay-stranger-'||current_setting('test.stranger')||'@example.invalid',jsonb_build_object('display_name','Stranger','adult_confirmed',true));

-- Реквізити в тексті.
do $$ begin
 assert private.has_payment_details('Картка 4111 1111 1111 1111'),'card with Luhn';
 assert private.has_payment_details('4111-1111-1111-1111'),'card with dashes';
 assert private.has_payment_details('IBAN UA21 3223 1300 0002 6007 2335 6600 1'),'IBAN UA';
 assert private.has_payment_details('банка: https://send.monobank.ua/jar/AbCd'),'monobank jar';
 assert not private.has_payment_details('4111 1111 1111 1112'),'Luhn fails — not a card';
 assert not private.has_payment_details('Телефон +380 50 123 45 67, чат https://t.me/club'),'phone and chat are fine';
 assert not private.has_payment_details('0000 0000 0000 0000'),'zeros are not a card';
 assert not private.has_payment_details('20.11.2026 о 19:00, 300 ₴'),'date and price are fine';
 assert not private.has_payment_details(null),'null';
end $$;

set local role authenticated;
do $$
declare v record;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 -- Онлайн з ціною — онлайн і за підтвердженням, хоч клієнт підтвердження й не просив.
 perform public.create_event(current_setting('test.online')::uuid,'Online paid games','Pay online before we meet','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',300,true);
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert v.pay_online and v.approval_required,'online implies approval';
 -- Онлайн без ціни — на місці.
 perform public.create_event(current_setting('test.onsite')::uuid,'Onsite games','Pay at the door if any','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'app',0,true);
 select * into v from public.event_details(current_setting('test.onsite')::uuid);
 assert not v.pay_online and not v.approval_required,'online without a price is onsite';
 -- Реквізити в описі — ні.
 begin perform public.create_event(gen_random_uuid(),'Bad','Prepay to 4111 1111 1111 1111','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'app',300,true);
  raise exception 'card in the description accepted';
 exception when sqlstate '22023' then assert sqlerrm='PAYMENT_DETAILS','no card in the description'; end;
 begin perform public.update_event(current_setting('test.online')::uuid,'Online paid games','Банка send.monobank.ua/jar/x','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,300);
  raise exception 'jar in the description accepted';
 exception when sqlstate '22023' then assert sqlerrm='PAYMENT_DETAILS','no jar link on update'; end;

 -- Старий клієнт (без p_pay_online і з approval false) спосіб оплати не чіпає й підтвердження не знімає.
 perform public.update_event(current_setting('test.online')::uuid,'Online paid games','Pay online before we meet','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false);
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert v.pay_online and v.approval_required and v.price_min=300,'old client keeps online';

 -- Гість записується (заявка), організатор пише першим і надсилає реквізити; гість бачить позначку.
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 perform public.join_event(current_setting('test.online')::uuid);
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert v.membership='requested','online join is a request';
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.send_message(current_setting('test.online')::uuid,'Оплата на картку 4111 1111 1111 1111, 300 грн',current_setting('test.guest')::uuid);
 begin perform public.send_message(current_setting('test.online')::uuid,'Привіт',current_setting('test.stranger')::uuid);
  raise exception 'organizer wrote first to a stranger';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER','only to people who joined'; end;
 begin perform public.send_message(current_setting('test.online')::uuid,'Картка 4111 1111 1111 1111',null);
  raise exception 'card in the group chat accepted';
 exception when sqlstate '22023' then assert sqlerrm='PAYMENT_DETAILS','no card in the group chat'; end;

 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 perform public.send_message(current_setting('test.online')::uuid,'Оплатила, дякую!',current_setting('test.guest')::uuid);
 -- now() у транзакції один, тож повідомлення беремо за текстом, а не «останнє».
 select * into v from public.event_messages(current_setting('test.online')::uuid,null,100,current_setting('test.guest')::uuid) m where m.body like 'Оплата на картку%';
 assert v.payment_details,'message with details is marked';
 select * into v from public.event_messages(current_setting('test.online')::uuid,null,100,current_setting('test.guest')::uuid) m where m.body like 'Оплатила%';
 assert not v.payment_details,'plain message is not marked';

 -- Подія «на місці»: реквізити й у розмові — ні.
 perform public.send_message(current_setting('test.onsite')::uuid,'Можна прийти з другом?',current_setting('test.guest')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 begin perform public.send_message(current_setting('test.onsite')::uuid,'Передоплата на 4111 1111 1111 1111',current_setting('test.guest')::uuid);
  raise exception 'card in an onsite thread accepted';
 exception when sqlstate '22023' then assert sqlerrm='PAYMENT_DETAILS','onsite means no prepayment'; end;

 -- «Оплату отримано» — це схвалення заявки.
 perform public.approve_member(current_setting('test.online')::uuid,current_setting('test.guest')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 select * into v from public.event_details(current_setting('test.online')::uuid);
 assert v.membership='approved','paid and approved';
end $$;
reset role;

-- Лист тому, хто питав: перший — так, другий за годину — ні; лічильник окремий від листів організатору.
do $$ begin
 assert public.question_mail_due(current_setting('test.online')::uuid,current_setting('test.guest')::uuid,true),'first answer mail';
 assert not public.question_mail_due(current_setting('test.online')::uuid,current_setting('test.guest')::uuid,true),'one per hour';
 assert public.question_mail_due(current_setting('test.online')::uuid,current_setting('test.guest')::uuid),'organizer mails counted apart';
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_event'),'one create_event for PostgREST';
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='update_event'),'one update_event for PostgREST';
end $$;
rollback;

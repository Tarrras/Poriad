-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Скріншот оплати в розмові — 20261125130000_payment_proofs: приватний бакет, лише людина в розмові онлайн-події,
-- бачать двоє.
begin;
-- Оплата онлайн за вимикачем (20261125160000_pay_online_switch) — тут увімкнено; транзакція відкочується.
update private.flags set enabled = true where name = 'pay_online';
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.stranger',gen_random_uuid()::text,true),set_config('test.online',gen_random_uuid()::text,true),
 set_config('test.onsite',gen_random_uuid()::text,true),set_config('test.file',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-proof-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','adult_confirmed',true)),
 (current_setting('test.guest')::uuid,'poruch-proof-guest-'||current_setting('test.guest')||'@example.invalid',jsonb_build_object('display_name','Guest','adult_confirmed',true)),
 (current_setting('test.stranger')::uuid,'poruch-proof-stranger-'||current_setting('test.stranger')||'@example.invalid',jsonb_build_object('display_name','Stranger','adult_confirmed',true));

set local role authenticated;
do $$
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 -- Згода організатора на «Правила оплати онлайн» (20261125170000_pay_online_safety).
 perform public.accept_pay_terms('organizer');
 perform public.create_event(current_setting('test.online')::uuid,'Online paid games','Pay online before we meet','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',300,true,'cancel_only');
 perform public.create_event(current_setting('test.onsite')::uuid,'Onsite paid games','Pay at the door','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'web',300,false);
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 perform public.accept_pay_terms('payer',current_setting('test.online')::uuid); -- бачив правила повернення
 perform public.join_event(current_setting('test.online')::uuid);
 perform public.join_event(current_setting('test.onsite')::uuid);
end $$;

-- Хто може вивантажити й хто бачить.
do $$
declare v_own text := current_setting('test.guest')||'/'||current_setting('test.online')||'/'||current_setting('test.file')||'.jpg';
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 assert private.can_upload_proof(v_own),'guest uploads into own folder of an online event';
 assert not private.can_upload_proof(current_setting('test.guest')||'/'||current_setting('test.onsite')||'/'||current_setting('test.file')||'.jpg'),'not for onsite';
 assert not private.can_upload_proof(current_setting('test.host')||'/'||current_setting('test.online')||'/'||current_setting('test.file')||'.jpg'),'not into a foreign folder';
 assert not private.can_upload_proof(current_setting('test.guest')||'/'||current_setting('test.online')||'/x.png'),'only uuid.jpg';
 perform set_config('request.jwt.claim.sub',current_setting('test.stranger'),true);
 assert not private.can_upload_proof(current_setting('test.stranger')||'/'||current_setting('test.online')||'/'||current_setting('test.file')||'.jpg'),'stranger did not sign up';
 assert not private.can_read_proof(v_own),'stranger does not see it';
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert private.can_read_proof(v_own),'organizer sees it';
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 assert private.can_read_proof(v_own),'uploader sees it';
end $$;
reset role;

-- Файл «вивантажено» (як Storage після перевірки політики).
insert into storage.objects(bucket_id,name) values ('payment-proofs',
 current_setting('test.guest')||'/'||current_setting('test.online')||'/'||current_setting('test.file')||'.jpg');

set local role authenticated;
do $$
declare v record; v_own text := current_setting('test.guest')||'/'||current_setting('test.online')||'/'||current_setting('test.file')||'.jpg';
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 perform public.send_message(current_setting('test.online')::uuid,'Скріншот оплати',current_setting('test.guest')::uuid,v_own);
 select * into v from public.event_messages(current_setting('test.online')::uuid,null,100,current_setting('test.guest')::uuid) m where m.image is not null;
 assert v.image=v_own and v.body='Скріншот оплати','message carries the screenshot';
 -- Чужий шлях, неіснуючий файл, загальний чат — ні.
 begin perform public.send_message(current_setting('test.online')::uuid,'x',current_setting('test.guest')::uuid,
   current_setting('test.guest')||'/'||current_setting('test.online')||'/'||gen_random_uuid()||'.jpg');
  raise exception 'missing file accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_IMAGE','file must exist'; end;
 begin perform public.send_message(current_setting('test.online')::uuid,'x',null,v_own);
  raise exception 'image in the group chat accepted';
 exception when sqlstate '42501' then assert sqlerrm='NOT_MEMBER','requester is not in the group chat';
  when sqlstate '22023' then assert sqlerrm='INVALID_IMAGE','no image in the group chat'; end;
 -- Організатор картинок не надсилає: реквізити картинкою обійшли б перевірку.
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 begin perform public.send_message(current_setting('test.online')::uuid,'QR',current_setting('test.guest')::uuid,v_own);
  raise exception 'organizer sent an image';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_IMAGE','only the attendee sends screenshots'; end;
 -- Старий клієнт (три параметри) пише, як і раніше.
 perform public.send_message(current_setting('test.online')::uuid,'Отримала, дякую',current_setting('test.guest')::uuid);
end $$;
reset role;

-- Ліміт — 20 файлів на добу в теці людини; чужі теки не рахуються (діапазон імені, не весь бакет).
insert into storage.objects(bucket_id,name) select 'payment-proofs',
 current_setting('test.host')||'/'||current_setting('test.online')||'/'||gen_random_uuid()||'.jpg' from generate_series(1,25);
set local role authenticated;
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 assert private.can_upload_proof(current_setting('test.guest')||'/'||current_setting('test.online')||'/'||gen_random_uuid()||'.jpg'),'foreign files do not count';
end $$;
reset role;
insert into storage.objects(bucket_id,name) select 'payment-proofs',
 current_setting('test.guest')||'/'||current_setting('test.online')||'/'||gen_random_uuid()||'.jpg' from generate_series(1,19);
set local role authenticated;
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 assert not private.can_upload_proof(current_setting('test.guest')||'/'||current_setting('test.online')||'/'||gen_random_uuid()||'.jpg'),'20 a day';
end $$;
reset role;

do $$ begin
 assert (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='send_message'),'one send_message for PostgREST';
 assert (select not public from storage.buckets where id='payment-proofs'),'bucket is private';
end $$;
rollback;

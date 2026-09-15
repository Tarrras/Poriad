-- Запускати адміністратором бази. Усе відкочується. Посилання на чат і стрічка запитів:
-- чат бачать лише свої, погане посилання не проходить, організатор отримує запити одним списком.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.other',gen_random_uuid()::text,true),
 set_config('test.gated',gen_random_uuid()::text,true),set_config('test.open',gen_random_uuid()::text,true);

insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-test-host-'||current_setting('test.host')||'@example.invalid',
  jsonb_build_object('display_name','Host','birth_date',to_char(current_date - interval '30 years','YYYY-MM-DD'))),
 (current_setting('test.guest')::uuid,'poruch-test-guest-'||current_setting('test.guest')||'@example.invalid',
  jsonb_build_object('display_name','Guest','birth_date',to_char(current_date - interval '24 years','YYYY-MM-DD'))),
 (current_setting('test.other')::uuid,'poruch-test-other-'||current_setting('test.other')||'@example.invalid',
  jsonb_build_object('display_name','Other','birth_date',to_char(current_date - interval '26 years','YYYY-MM-DD')));

set local role authenticated;

-- Організатор публікує подію з чатом і одну з підтвердженням без чату.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.create_event(current_setting('test.open')::uuid,'With a chat','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,false,'https://t.me/poruch_test');
select public.create_event(current_setting('test.gated')::uuid,'By approval','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,true,null);
do $$ begin
 assert (select contact_url='https://t.me/poruch_test' from public.event_details(current_setting('test.open')::uuid)),'organizer reads the chat link';
 assert (select contact_url is null from public.event_details(current_setting('test.gated')::uuid)),'no link is null';
 begin perform public.create_event(gen_random_uuid(),'Bad link','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,false,'http://t.me/plain');
  raise exception 'expected scheme rejection';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_CONTACT_URL'; end;
 begin perform public.create_event(gen_random_uuid(),'Bad link','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,false,'javascript:alert(1)');
  raise exception 'expected scheme rejection';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_CONTACT_URL'; end;
 begin perform public.create_event(gen_random_uuid(),'Bad link','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,false,'https://'||repeat('a',600));
  raise exception 'expected length rejection';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_CONTACT_URL'; end;
end $$;

-- Порожній рядок з редактора — це «без чату», а не посилання.
select public.update_event(current_setting('test.gated')::uuid,'By approval','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,true,'  ');
do $$ begin
 assert (select contact_url is null from public.events where id=current_setting('test.gated')::uuid),'blank link is stored as null';
end $$;

-- Сторонній не бачить чату; гість без акаунта — теж.
select set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
do $$ begin
 assert (select count(*)=1 from public.event_details(current_setting('test.open')::uuid)),'the event itself is public';
 assert (select contact_url is null from public.event_details(current_setting('test.open')::uuid)),'a stranger does not see the chat';
end $$;
reset role;
set local role anon;
do $$ begin
 assert (select contact_url is null from public.event_details(current_setting('test.open')::uuid)),'guests do not see the chat';
end $$;
reset role;
set local role authenticated;

-- Приєднання відкриває чат; запит без відповіді — ні.
select set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
select public.join_event(current_setting('test.open')::uuid);
select public.join_event(current_setting('test.gated')::uuid);
do $$ begin
 assert (select contact_url='https://t.me/poruch_test' from public.event_details(current_setting('test.open')::uuid)),'a member reads the chat link';
 assert (select count(*)=0 from public.my_join_requests()),'a guest has no request feed';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.other'),true);
select public.join_event(current_setting('test.gated')::uuid);
-- В одній транзакції обидва запити мають один `now()`: розсуваємо їх, щоб порядок справді перевірявся.
reset role;
update public.event_members set joined_at=joined_at-interval '1 minute'
 where event_id=current_setting('test.gated')::uuid and user_id=current_setting('test.guest')::uuid;
set local role authenticated;

-- Стрічка організатора: обидва запити, свіжіший першим, з іменами.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 assert (select count(*)=2 from public.my_join_requests()),'both requests are in the feed';
 assert (select event_id=current_setting('test.gated')::uuid and display_name='Other' from public.my_join_requests() limit 1),'newest first with a name';
 assert (select count(*)=1 from public.my_join_requests(1)),'limit is honoured';
 assert (select count(*)=1 from public.my_join_requests(0)),'limit is clamped up from 0';
end $$;
select public.approve_member(current_setting('test.gated')::uuid,current_setting('test.guest')::uuid);
select public.decline_member(current_setting('test.gated')::uuid,current_setting('test.other')::uuid);
do $$ begin
 assert (select count(*)=0 from public.my_join_requests()),'answered requests leave the feed';
end $$;

-- Скасована подія не тримає запитів у стрічці.
select set_config('request.jwt.claim.sub',current_setting('test.other'),true);
select public.join_event(current_setting('test.gated')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 assert (select count(*)=1 from public.my_join_requests()),'a fresh request is back';
end $$;
select public.cancel_event(current_setting('test.gated')::uuid);
do $$ begin
 assert (select count(*)=0 from public.my_join_requests()),'a cancelled event drops out of the feed';
end $$;

-- Гість без акаунта не має гранту на стрічку.
reset role;
set local role anon;
do $$ begin
 begin perform public.my_join_requests(); raise exception 'expected missing grant';
 exception when insufficient_privilege then null; end;
end $$;

rollback;

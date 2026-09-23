-- Запускати адміністратором бази. Усе відкочується. Пуш-токени: реєстрація під акаунтом,
-- перехід токена до іншого акаунта, зняття лише свого, тригери без адреси функції мовчать.
begin;
select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.event',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.a')::uuid,'poruch-test-a-'||current_setting('test.a')||'@example.invalid',
  jsonb_build_object('display_name','A','birth_date',to_char(current_date - interval '30 years','YYYY-MM-DD'))),
 (current_setting('test.b')::uuid,'poruch-test-b-'||current_setting('test.b')||'@example.invalid',
  jsonb_build_object('display_name','B','birth_date',to_char(current_date - interval '24 years','YYYY-MM-DD')));

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
select public.register_push_token('token-android-0123456789abcdef','android');
select public.register_push_token('token-ios-0123456789abcdef','ios');
do $$ begin
 begin perform public.register_push_token('short','android'); raise exception 'expected token validation';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_TOKEN'; end;
 begin perform public.register_push_token('token-web-0123456789abcdef','web'); raise exception 'expected platform validation';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PLATFORM'; end;
 begin perform count(*) from public.push_tokens; raise exception 'expected no table access';
 exception when insufficient_privilege then null; end;
end $$;

-- Той самий телефон, інший акаунт: токен переходить.
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
select public.register_push_token('token-android-0123456789abcdef','android');
reset role;
do $$ begin
 assert (select user_id=current_setting('test.b')::uuid from public.push_tokens where token='token-android-0123456789abcdef'),'token moves to the new account';
 assert (select count(*)=2 from public.push_tokens where user_id in (current_setting('test.a')::uuid,current_setting('test.b')::uuid)),'two tokens in total';
end $$;

-- Зняти можна лише своє.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
select public.unregister_push_token('token-ios-0123456789abcdef');
select public.unregister_push_token('token-android-0123456789abcdef');
reset role;
do $$ begin
 assert (select count(*)=1 from public.push_tokens where user_id in (current_setting('test.a')::uuid,current_setting('test.b')::uuid)),'only the own token is removed';
 assert (select platform='ios' from public.push_tokens where user_id in (current_setting('test.a')::uuid,current_setting('test.b')::uuid)),'the other account''s token stays';
end $$;

-- Тригери є, але без адреси у Vault не роблять запитів і не ламають запис.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
select public.create_event(current_setting('test.event')::uuid,'Push night','Description here','games','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,true);
select public.send_message(current_setting('test.event')::uuid,'Привіт');
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
select public.join_event(current_setting('test.event')::uuid);
reset role;
do $$ begin
 assert (select count(*)=1 from public.event_messages where event_id=current_setting('test.event')::uuid),'message written with the trigger in place';
 assert (select count(*)=1 from public.event_members where event_id=current_setting('test.event')::uuid and status='requested'),'request written with the trigger in place';
 assert (select tgenabled<>'D' from pg_trigger where tgname='event_messages_push'),'message trigger enabled';
 assert (select tgenabled<>'D' from pg_trigger where tgname='event_members_push'),'request trigger enabled';
end $$;

rollback;

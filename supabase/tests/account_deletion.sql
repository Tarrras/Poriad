-- Запускати адміністратором бази. Усе відкочується. Видалення акаунта (Б1/Б2): RPC-запасний шлях
-- проходить крізь storage.protect_delete; скарги на видаленого користувача й на подію видаленого
-- організатора лишаються з subject_type і null-посиланням; каскад прибирає все інше. Плюс export і
-- стирання тексту видаленого повідомлення.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.member',gen_random_uuid()::text,true),
 set_config('test.witness',gen_random_uuid()::text,true),set_config('test.event',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-test-host-'||current_setting('test.host')||'@example.invalid',
  jsonb_build_object('display_name','Host','birth_date',to_char(current_date - interval '30 years','YYYY-MM-DD'))),
 (current_setting('test.member')::uuid,'poruch-test-member-'||current_setting('test.member')||'@example.invalid',
  jsonb_build_object('display_name','Member','birth_date',to_char(current_date - interval '24 years','YYYY-MM-DD'))),
 (current_setting('test.witness')::uuid,'poruch-test-witness-'||current_setting('test.witness')||'@example.invalid',
  jsonb_build_object('display_name','Witness','birth_date',to_char(current_date - interval '28 years','YYYY-MM-DD')));
-- Фото організатора: рядок у storage.objects, як після завантаження.
insert into storage.objects(bucket_id,name) values ('event-images',current_setting('test.host')||'/'||current_setting('test.event')||'/cover.jpg');

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.create_event(current_setting('test.event')::uuid,'Delete night','Description here','games','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5);
select public.register_push_token('token-ios-delete-0123456789abcdef','ios');
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
select public.join_event(current_setting('test.event')::uuid);
select public.send_message(current_setting('test.event')::uuid,'Буду');
select set_config('test.gone',public.send_message(current_setting('test.event')::uuid,'Передумав, видаляю')::text,true);
select public.delete_message(current_setting('test.gone')::uuid);
select public.mark_chat_read(current_setting('test.event')::uuid);
select public.report_event(current_setting('test.event')::uuid,'spam',null);
select public.report_user(current_setting('test.host')::uuid,'harassment',null);
select set_config('request.jwt.claim.sub',current_setting('test.witness'),true);
select public.join_event(current_setting('test.event')::uuid);
select set_config('test.on_event',public.report_event(current_setting('test.event')::uuid,'scam',null)::text,true);
select set_config('test.on_member',public.report_user(current_setting('test.member')::uuid,'harassment',null)::text,true);
do $$ begin
 begin perform public.report_event(null,'spam',null); raise exception 'expected subject validation';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_SUBJECT'; end;
end $$;

-- Видалене повідомлення: текст стерто, факт лишився.
reset role;
do $$ begin
 assert (select body is null and deleted_at is not null from public.event_messages where id=current_setting('test.gone')::uuid),'deleted message loses its text';
end $$;

-- Копія даних: нові розділи на місці, токена в копії немає.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ declare d jsonb := public.export_my_data(); begin
 assert d->>'email' like 'poruch-test-host-%','email exported';
 assert jsonb_array_length(d->'push_devices')=1 and d->'push_devices'->0->>'platform'='ios','push device exported';
 assert not (d::text like '%token-ios-delete%'),'the token itself is not exported';
 assert d ? 'ratings' and d ? 'chat_reads','ratings and chat reads present';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.member'),true);
do $$ declare d jsonb := public.export_my_data(); begin
 assert jsonb_array_length(d->'chat_reads')=1,'chat read exported';
 assert jsonb_array_length(d->'messages')=2,'messages exported';
end $$;

-- Учасник, на якого скаржились, видаляє себе.
select public.delete_my_account();
reset role;
do $$ begin
 assert not exists(select 1 from auth.users where id=current_setting('test.member')::uuid),'member deleted';
 assert not exists(select 1 from public.profiles where id=current_setting('test.member')::uuid),'profile gone';
 assert not exists(select 1 from public.event_messages where author_id=current_setting('test.member')::uuid),'messages gone';
 assert not exists(select 1 from public.event_members where user_id=current_setting('test.member')::uuid),'membership gone';
 assert not exists(select 1 from public.chat_reads where user_id=current_setting('test.member')::uuid),'chat reads gone';
 assert not exists(select 1 from public.reports where reporter_id=current_setting('test.member')::uuid),'own reports gone';
 assert (select subject_type='user' and subject_user_id is null from public.reports where id=current_setting('test.on_member')::uuid),'report on the member stays with a null subject';
end $$;

-- Організатор з фото, подією, токеном і скаргою на подію видаляє себе.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.delete_my_account();
reset role;
do $$ begin
 assert not exists(select 1 from auth.users where id=current_setting('test.host')::uuid),'host deleted';
 assert not exists(select 1 from public.events where id=current_setting('test.event')::uuid),'own event gone';
 assert not exists(select 1 from public.event_members where event_id=current_setting('test.event')::uuid),'its members gone';
 assert not exists(select 1 from public.push_tokens where user_id=current_setting('test.host')::uuid),'push tokens gone';
 assert not exists(select 1 from storage.objects where name like current_setting('test.host')||'/%'),'photos gone';
 assert (select subject_type='event' and event_id is null from public.reports where id=current_setting('test.on_event')::uuid),'report on the event stays with a null event';
end $$;

-- Гість не видаляє нікого.
set local role anon;
do $$ begin
 begin perform public.delete_my_account(); raise exception 'expected no grant for anon';
 exception when insufficient_privilege then null; end;
end $$;
rollback;

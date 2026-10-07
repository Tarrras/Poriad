-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Імʼя нового акаунта: своя форма (`display_name`) → Google (`full_name`, `name`) → «Учасник» (Apple).
begin;
select set_config('test.form',gen_random_uuid()::text,true),set_config('test.google',gen_random_uuid()::text,true),
 set_config('test.short',gen_random_uuid()::text,true),set_config('test.apple',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.form')::uuid,'poruch-form-'||current_setting('test.form')||'@example.invalid',jsonb_build_object('display_name','Форма','full_name','Google','birth_date','1990-01-01')),
 (current_setting('test.google')::uuid,'poruch-google-'||current_setting('test.google')||'@example.invalid',jsonb_build_object('full_name','  Олена Коваль ','name','Олена')),
 (current_setting('test.short')::uuid,'poruch-short-'||current_setting('test.short')||'@example.invalid',jsonb_build_object('full_name','','name','Олена')),
 (current_setting('test.apple')::uuid,'poruch-apple-'||current_setting('test.apple')||'@example.invalid','{}'::jsonb);
do $$ begin
 assert (select display_name from public.profiles where id=current_setting('test.form')::uuid)='Форма','own form wins';
 assert (select display_name from public.profiles where id=current_setting('test.google')::uuid)='Олена Коваль','google full_name, trimmed';
 assert (select display_name from public.profiles where id=current_setting('test.short')::uuid)='Олена','google name when full_name is empty';
 assert (select display_name from public.profiles where id=current_setting('test.apple')::uuid)='Учасник','apple: client renames later';
 -- Без дати з форми вік не задекларовано: клієнт питає його одразу після входу.
 assert (select birth_date from public.account_facts where user_id=current_setting('test.google')::uuid) is null,'no age from a provider';
end $$;
rollback;

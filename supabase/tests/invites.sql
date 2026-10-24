-- Запускати адміністратором бази. Усе відкочується. «Покликати з собою»: токен на людину й подію, ліміт, хто кличе —
-- лише ім'я й фото, лише для своєї події, без прихованих, скасованих, минулих і заблокованих.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.friend',gen_random_uuid()::text,true),
 set_config('test.room',gen_random_uuid()::text,true),set_config('test.other',gen_random_uuid()::text,true),
 set_config('test.past',gen_random_uuid()::text,true),set_config('test.copy',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-invite-'||id||'@example.invalid',jsonb_build_object('display_name',name,'birth_date','1990-01-01')
from (values (current_setting('test.host'),'  Тарас Вовченко'),(current_setting('test.friend'),'Оля')) u(id,name);
update public.profiles set avatar_url='https://x.supabase.co/storage/v1/object/public/event-images/'||id||'/avatar/a.jpg'
 where id=current_setting('test.host')::uuid;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity) values
 (current_setting('test.room')::uuid,current_setting('test.friend')::uuid,'Настолки','Test description','games','Ocean','Buoy',-40.5,-30.5,now()+interval '1 day',now()+interval '1 day 2 hours','UTC',10),
 (current_setting('test.other')::uuid,current_setting('test.friend')::uuid,'Біг','Test description','sport','Ocean','Buoy',-40.5,-30.5,now()+interval '2 days',now()+interval '2 days 2 hours','UTC',10),
 (current_setting('test.past')::uuid,current_setting('test.friend')::uuid,'Минуле','Test description','sport','Ocean','Buoy',-40.5,-30.5,now()-interval '3 hours',now()-interval '1 hour','UTC',10);

-- Без входу кликати не можна: нема гранту.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.create_invite(current_setting('test.room')::uuid); raise exception 'anon invited';
 exception when insufficient_privilege then null; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ declare v_token text; begin
 v_token := public.create_invite(current_setting('test.room')::uuid);
 assert v_token ~ '^[A-Za-z0-9_-]{22}$', 'token is 22 url-safe chars (128 bits)';
 assert public.create_invite(current_setting('test.room')::uuid)=v_token, 'same person and event — same link';
 assert public.create_invite(current_setting('test.other')::uuid)<>v_token, 'another event — another token';
 perform set_config('test.token', v_token, true);
 begin perform public.create_invite(current_setting('test.past')::uuid); raise exception 'past event invited';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_NOT_FOUND'; end;
 begin perform public.create_invite(gen_random_uuid()); raise exception 'unknown event invited';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_NOT_FOUND'; end;
 -- Себе не кличуть: власне посилання показує звичайну подію.
 assert not exists(select 1 from public.invite_inviter(v_token, current_setting('test.room')::uuid)), 'own link shows no inviter';
end $$;
reset role;

-- Друг без входу (сторінка, гість): перше слово імені й фото, і лише для тієї події, на яку кликали.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ declare r record; v_token text := current_setting('test.token'); begin
 select * into r from public.invite_inviter(v_token, current_setting('test.room')::uuid);
 assert r.name='Тарас' and r.avatar_url like '%/avatar/a.jpg', 'first name and photo, nothing else';
 assert not exists(select 1 from public.invite_inviter(v_token, current_setting('test.other')::uuid)), 'token of another event';
 assert not exists(select 1 from public.invite_inviter(upper(v_token), current_setting('test.room')::uuid)), 'token is exact';
 assert not exists(select 1 from public.invite_inviter('nope', current_setting('test.room')::uuid)), 'garbage token';
 assert not exists(select 1 from public.invite_inviter(null, current_setting('test.room')::uuid)), 'no token';
end $$;
reset role;

-- Друг з акаунтом бачить те саме, доки ніхто нікого не заблокував.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.friend'),true);
do $$ begin
 assert (select name from public.invite_inviter(current_setting('test.token'), current_setting('test.room')::uuid))='Тарас', 'signed-in friend';
end $$;
reset role;
insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.host')::uuid,current_setting('test.friend')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.friend'),true);
do $$ begin
 assert not exists(select 1 from public.invite_inviter(current_setting('test.token'), current_setting('test.room')::uuid)), 'blocked: no inviter';
end $$;
reset role;
delete from public.user_blocks where user_id=current_setting('test.host')::uuid;

-- Злиту подію відкривають за старим id: запрошення тримається за живу.
insert into public.event_sources(slug,name,kind,base_url) values ('test_invites','Test','manual','https://example.invalid');
insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,origin,source_id,source_uid,import_status) values
 (current_setting('test.copy')::uuid,'Настолки','','games','Ocean','Buoy',-40.5,-30.5,now()+interval '1 day',now()+interval '1 day 2 hours','UTC',
  'import',(select id from public.event_sources where slug='test_invites'),'i1','withdrawn');
update public.events set merged_into=current_setting('test.room')::uuid where id=current_setting('test.copy')::uuid;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 assert (select name from public.invite_inviter(current_setting('test.token'), current_setting('test.copy')::uuid))='Тарас', 'old id of a merged event';
end $$;
reset role;

-- Ім'я-заглушка й обмежений акаунт не кличуть.
update public.profiles set display_name='Учасник' where id=current_setting('test.host')::uuid;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin assert not exists(select 1 from public.invite_inviter(current_setting('test.token'), current_setting('test.room')::uuid)), 'placeholder name'; end $$;
reset role;
update public.profiles set display_name='Тарас' where id=current_setting('test.host')::uuid;
insert into public.account_facts(user_id,status) values (current_setting('test.host')::uuid,'limited')
 on conflict (user_id) do update set status='limited';
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin assert not exists(select 1 from public.invite_inviter(current_setting('test.token'), current_setting('test.room')::uuid)), 'restricted inviter'; end $$;
reset role;
update public.account_facts set status='active' where user_id=current_setting('test.host')::uuid;

-- Прихована чи скасована подія не просвічує через запрошення, і нове на неї не створити.
update public.events set status='hidden' where id=current_setting('test.room')::uuid;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin assert not exists(select 1 from public.invite_inviter(current_setting('test.token'), current_setting('test.room')::uuid)), 'hidden event'; end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 begin perform public.create_invite(current_setting('test.room')::uuid); raise exception 'hidden event invited';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_NOT_FOUND'; end;
end $$;
reset role;
update public.events set status='cancelled' where id=current_setting('test.room')::uuid;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin assert not exists(select 1 from public.invite_inviter(current_setting('test.token'), current_setting('test.room')::uuid)), 'cancelled event'; end $$;
reset role;

-- Ліміт: 30 нових запрошень на годину, повтор наявного не рахується.
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
select gen_random_uuid(),current_setting('test.friend')::uuid,'Подія '||n,'Test description','social','Ocean','Buoy',-40.5,-30.5,
 now()+interval '3 days',now()+interval '3 days 2 hours','UTC',10 from generate_series(1,30) n;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ declare v_id uuid; v_made integer := 0; begin
 for v_id in select id from public.events where title like 'Подія %' and organizer_id=current_setting('test.friend')::uuid order by title loop
  begin perform public.create_invite(v_id); v_made := v_made + 1;
  exception when sqlstate 'P0001' then assert sqlerrm='TOO_MANY_INVITES'; end;
 end loop;
 -- За годину вже є два (Настолки й Біг), тож влазить ще 28.
 assert v_made=28, format('28 more fit the hour, made %s', v_made);
 perform public.create_invite(current_setting('test.other')::uuid);
end $$;
reset role;
select 'PASS: token per person and event, limit, first name and photo only, own event only, hidden/cancelled/past/blocked/restricted show nothing, merged id' as result;
rollback;

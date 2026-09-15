-- Запускати адміністратором бази. Усе відкочується. Правила безпеки: вік, вікові межі,
-- підтвердження, блокування, скарги, статус акаунта. Кожна перевірка — правило проти пропатченого клієнта.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.adult',gen_random_uuid()::text,true),
 set_config('test.young',gen_random_uuid()::text,true),set_config('test.unknown',gen_random_uuid()::text,true),
 set_config('test.banned',gen_random_uuid()::text,true),set_config('test.open',gen_random_uuid()::text,true),
 set_config('test.gated',gen_random_uuid()::text,true),set_config('test.aged',gen_random_uuid()::text,true);

-- Неповнолітня реєстрація не стає профілем.
do $$ begin
 begin
  insert into auth.users(id,email,raw_user_meta_data) values
   (gen_random_uuid(),'poruch-test-underage-'||gen_random_uuid()||'@example.invalid',
    jsonb_build_object('display_name','Teen','birth_date',to_char(current_date - interval '15 years','YYYY-MM-DD')));
  raise exception 'expected underage rejection';
 exception when sqlstate 'P0001' then if sqlerrm <> 'UNDERAGE' then raise; end if; end;
end $$;

insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-test-host-'||current_setting('test.host')||'@example.invalid',
  jsonb_build_object('display_name','Host','birth_date',to_char(current_date - interval '30 years','YYYY-MM-DD'))),
 (current_setting('test.adult')::uuid,'poruch-test-adult-'||current_setting('test.adult')||'@example.invalid',
  jsonb_build_object('display_name','Adult','birth_date',to_char(current_date - interval '24 years','YYYY-MM-DD'))),
 (current_setting('test.young')::uuid,'poruch-test-young-'||current_setting('test.young')||'@example.invalid',
  jsonb_build_object('display_name','Younger','birth_date',to_char(current_date - interval '19 years','YYYY-MM-DD'))),
 (current_setting('test.unknown')::uuid,'poruch-test-unknown-'||current_setting('test.unknown')||'@example.invalid',
  '{"display_name":"Unstated"}'),
 (current_setting('test.banned')::uuid,'poruch-test-banned-'||current_setting('test.banned')||'@example.invalid',
  jsonb_build_object('display_name','Banned','birth_date',to_char(current_date - interval '40 years','YYYY-MM-DD')));

do $$ begin
 assert (select birth_date is not null from public.account_facts where user_id=current_setting('test.host')::uuid),'birth date stored at sign-up';
 assert (select birth_date is null from public.account_facts where user_id=current_setting('test.unknown')::uuid),'no date declared stays null';
 assert (select status='active' from public.account_facts where user_id=current_setting('test.host')::uuid),'new accounts are active';
end $$;

set local role authenticated;

-- Акаунт без віку вказує його рівно раз.
select set_config('request.jwt.claim.sub',current_setting('test.unknown'),true);
do $$ begin
 begin perform public.set_birth_date((current_date - interval '15 years')::date); raise exception 'expected underage rejection';
 exception when sqlstate 'P0001' then if sqlerrm <> 'UNDERAGE' then raise; end if; end;
end $$;
select public.set_birth_date((current_date - interval '20 years')::date);
do $$ begin
 begin perform public.set_birth_date((current_date - interval '40 years')::date); raise exception 'expected second declaration to fail';
 exception when sqlstate 'P0001' then if sqlerrm <> 'AGE_ALREADY_SET' then raise; end if; end;
end $$;

-- Організатор публікує відкриту, вікову і з підтвердженням.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
select public.create_event(current_setting('test.open')::uuid,'Open evening','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null);
select public.create_event(current_setting('test.aged')::uuid,'Twenties only','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,21,25,false);
select public.create_event(current_setting('test.gated')::uuid,'By approval','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,18,null,true);
do $$ begin
 assert (select min_age=18 and max_age is null and not approval_required from public.events where id=current_setting('test.open')::uuid),'defaults are the platform floor';
 begin perform public.create_event(gen_random_uuid(),'Under the floor','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,14,null,false);
  raise exception 'expected age limit rejection';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_AGE_LIMIT'; end;
 begin perform public.create_event(gen_random_uuid(),'Backwards range','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null,30,25,false);
  raise exception 'expected age range rejection';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_AGE_LIMIT'; end;
end $$;

-- Вікові межі перевіряє сервер.
select set_config('request.jwt.claim.sub',current_setting('test.young'),true);
do $$ begin
 begin perform public.join_event(current_setting('test.aged')::uuid); raise exception 'expected too young';
 exception when sqlstate 'P0001' then if sqlerrm <> 'TOO_YOUNG' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 -- Організатору 30: поза межею події для двадцятирічних, і він організатор.
 assert (select max_age=25 from public.events where id=current_setting('test.aged')::uuid),'upper bound stored';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.adult'),true);
select public.join_event(current_setting('test.aged')::uuid);
do $$ begin
 assert (select joined and attendee_count=1 from public.event_details(current_setting('test.aged')::uuid)),'in range joins';
end $$;

-- Без віку не приєднатись ніяк. Скинути дату може лише модератор (service role).
reset role;
update public.account_facts set birth_date=null where user_id=current_setting('test.unknown')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.unknown'),true);
do $$ begin
 begin perform public.join_event(current_setting('test.open')::uuid); raise exception 'expected age requirement';
 exception when sqlstate 'P0001' then if sqlerrm <> 'AGE_REQUIRED' then raise; end if; end;
end $$;
select public.set_birth_date((current_date - interval '20 years')::date);

-- Підтвердження: запит — не місце, вирішує організатор.
select public.join_event(current_setting('test.gated')::uuid);
do $$ begin
 assert (select membership='requested' and not joined and attendee_count=0 from public.event_details(current_setting('test.gated')::uuid)),'request holds no seat';
 assert (select count(*)=0 from public.event_attendees(current_setting('test.gated')::uuid)),'requests are not on the roster';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.adult'),true);
do $$ begin
 begin perform public.approve_member(current_setting('test.gated')::uuid,current_setting('test.unknown')::uuid); raise exception 'expected organizer check';
 exception when sqlstate '42501' then assert sqlerrm='NOT_ORGANIZER'; end;
 assert (select count(*)=0 from public.event_requests(current_setting('test.gated')::uuid)),'requests are the organizer''s to see';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
do $$ begin
 assert (select count(*)=1 from public.event_requests(current_setting('test.gated')::uuid)),'organizer sees the request';
end $$;
select public.approve_member(current_setting('test.gated')::uuid,current_setting('test.unknown')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.unknown'),true);
do $$ begin
 assert (select joined and membership='approved' and attendee_count=1 from public.event_details(current_setting('test.gated')::uuid)),'approval seats the member';
end $$;

-- Блокування в обидва боки: закриває і вхід, і видачу.
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
insert into public.user_blocks(user_id,blocked_id) values (auth.uid(),current_setting('test.young')::uuid);
select set_config('request.jwt.claim.sub',current_setting('test.young'),true);
do $$ begin
 assert (select count(*)=0 from public.event_details(current_setting('test.open')::uuid)),'a blocked organizer is not listed';
 begin perform public.join_event(current_setting('test.open')::uuid); raise exception 'expected block';
 exception when sqlstate '42501' then assert sqlerrm='BLOCKED'; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.host'),true);
delete from public.user_blocks where user_id=auth.uid() and blocked_id=current_setting('test.young')::uuid;

-- Обмежений акаунт зберігає рядки, але зникає з видачі.
select set_config('request.jwt.claim.sub',current_setting('test.banned'),true);
select set_config('test.banned_event',gen_random_uuid()::text,true);
select public.create_event(current_setting('test.banned_event')::uuid,'Before the ban','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null);
reset role;
update public.account_facts set status='banned' where user_id=current_setting('test.banned')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.adult'),true);
do $$ begin
 assert (select count(*)=0 from public.event_details(current_setting('test.banned_event')::uuid)),'a suspended organizer disappears from the app';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.banned'),true);
do $$ begin
 assert (select count(*)=1 from public.event_details(current_setting('test.banned_event')::uuid)),'the owner still sees their own event';
 begin perform public.join_event(current_setting('test.open')::uuid); raise exception 'expected account restriction';
 exception when sqlstate '42501' then assert sqlerrm='ACCOUNT_RESTRICTED'; end;
 begin perform public.create_event(gen_random_uuid(),'After the ban','Description here','social','Kyiv','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',5,null);
  raise exception 'expected account restriction';
 exception when sqlstate '42501' then assert sqlerrm='ACCOUNT_RESTRICTED'; end;
end $$;

-- Скарги: приватні, без дублів, з лімітом.
select set_config('request.jwt.claim.sub',current_setting('test.adult'),true);
select set_config('test.report',public.report_event(current_setting('test.open')::uuid,'minors','Молодші за вказаний вік')::text,true);
do $$ begin
 assert public.report_event(current_setting('test.open')::uuid,'minors',null)=current_setting('test.report')::uuid,'the same complaint twice is one report';
 assert (select count(*)=1 from public.reports where reporter_id=auth.uid()),'one row';
 assert (select reason='minors' and status='new' from public.reports where id=current_setting('test.report')::uuid),'filed as new';
 begin perform public.report_user(auth.uid(),'spam',null); raise exception 'expected self-report rejection';
 exception when sqlstate 'P0001' then assert sqlerrm='CANNOT_REPORT_SELF'; end;
 begin perform public.report_event(current_setting('test.open')::uuid,'nonsense',null); raise exception 'expected reason validation';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_REASON'; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.young'),true);
do $$ begin
 assert (select count(*)=0 from public.reports),'a report is private to the person who filed it';
end $$;
-- Ліміт десять на годину. Рядки вставляємо напряму: через RPC вони злилися б в один.
reset role;
insert into public.reports(reporter_id,subject_type,subject_user_id,reason)
select current_setting('test.adult')::uuid,'user',current_setting('test.host')::uuid,'other' from generate_series(1,9);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.adult'),true);
do $$ begin
 begin perform public.report_event(current_setting('test.gated')::uuid,'spam',null); raise exception 'expected rate limit';
 exception when sqlstate 'P0001' then assert sqlerrm='TOO_MANY_REPORTS'; end;
end $$;

rollback;

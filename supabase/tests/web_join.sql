-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Запис з вебу (`via`) і галочка «Мені вже є 18» — 20261117120000_web_join.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.dated',gen_random_uuid()::text,true),
 set_config('test.ticked',gen_random_uuid()::text,true),set_config('test.bare',gen_random_uuid()::text,true),
 set_config('test.open',gen_random_uuid()::text,true),set_config('test.over21',gen_random_uuid()::text,true),
 set_config('test.capped',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-webjoin-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','birth_date','1990-01-01')),
 (current_setting('test.dated')::uuid,'poruch-webjoin-dated-'||current_setting('test.dated')||'@example.invalid',jsonb_build_object('display_name','Dated','birth_date','1990-01-01')),
 (current_setting('test.ticked')::uuid,'poruch-webjoin-ticked-'||current_setting('test.ticked')||'@example.invalid',jsonb_build_object('display_name','Ticked','adult_confirmed',true)),
 (current_setting('test.bare')::uuid,'poruch-webjoin-bare-'||current_setting('test.bare')||'@example.invalid','{}'::jsonb);
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,min_age,max_age)
values
 (current_setting('test.open')::uuid,current_setting('test.host')::uuid,'Web join open','For adults','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',1,18,null),
 (current_setting('test.over21')::uuid,current_setting('test.host')::uuid,'Web join 21+','Older crowd','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',5,21,null),
 (current_setting('test.capped')::uuid,current_setting('test.host')::uuid,'Web join capped','Up to thirty five','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',5,18,35);

do $$ begin
 assert (select adult_confirmed_at is not null and birth_date is null from public.account_facts where user_id=current_setting('test.ticked')::uuid),
  'adult_confirmed metadata ticks the box at sign-up';
 assert private.age_of(current_setting('test.ticked')::uuid)=18,'ticked age is the platform minimum';
 assert private.age_of(current_setting('test.bare')::uuid) is null,'no date, no tick — age unknown';
end $$;

set local role authenticated;
do $$ begin
 -- Без віку запис з вебу просить крок 3, після галочки проходить і позначається як веб.
 perform set_config('request.jwt.claim.sub',current_setting('test.bare'),true);
 begin perform public.join_event_web(current_setting('test.open')::uuid); raise exception 'joined without age';
 exception when sqlstate 'P0001' then assert sqlerrm='AGE_REQUIRED','no age is AGE_REQUIRED'; end;
 perform public.confirm_adult();
 perform public.confirm_adult();
 perform public.join_event_web(current_setting('test.open')::uuid);

 -- Подія повна: застосунок відмовляє, а черга з вебу запамʼятовує веб.
 perform set_config('request.jwt.claim.sub',current_setting('test.dated'),true);
 begin perform public.join_event(current_setting('test.open')::uuid); raise exception 'full event accepted a join';
 exception when sqlstate 'P0001' then assert sqlerrm='EVENT_FULL','full is EVENT_FULL'; end;
 perform public.join_waitlist_web(current_setting('test.open')::uuid);

 -- Галочки не досить для віку від 19 чи верхньої межі: потрібна дата.
 perform set_config('request.jwt.claim.sub',current_setting('test.ticked'),true);
 begin perform public.join_event_web(current_setting('test.over21')::uuid); raise exception 'ticked joined 21+';
 exception when sqlstate 'P0001' then assert sqlerrm='AGE_REQUIRED','21+ asks for a date'; end;
 begin perform public.join_event_web(current_setting('test.capped')::uuid); raise exception 'ticked joined capped';
 exception when sqlstate 'P0001' then assert sqlerrm='AGE_REQUIRED','upper bound asks for a date'; end;
 perform public.set_birth_date('1995-05-05'::date);
 perform public.join_event_web(current_setting('test.over21')::uuid);
 perform public.join_event(current_setting('test.capped')::uuid);

 -- Місце звільнилось: людина з черги переходить в учасники зі своїм `via`.
 perform set_config('request.jwt.claim.sub',current_setting('test.bare'),true);
 perform public.leave_event(current_setting('test.open')::uuid);
end $$;
reset role;

do $$ begin
 assert (select via from public.event_members where event_id=current_setting('test.open')::uuid and user_id=current_setting('test.dated')::uuid)='web',
  'promoted from a web waitlist stays web';
 assert not exists(select 1 from public.event_members where event_id=current_setting('test.open')::uuid and user_id=current_setting('test.bare')::uuid),
  'left the event';
 assert (select via from public.event_members where event_id=current_setting('test.over21')::uuid and user_id=current_setting('test.ticked')::uuid)='web',
  'web join is web';
 assert (select via from public.event_members where event_id=current_setting('test.capped')::uuid and user_id=current_setting('test.ticked')::uuid)='app',
  'app join stays app';
 assert private.age_of(current_setting('test.ticked')::uuid) > 18,'a declared date beats the tick';
 assert (select count(*)=1 from public.account_facts where user_id=current_setting('test.bare')::uuid and adult_confirmed_at is not null),
  'confirm_adult is idempotent';
end $$;
rollback;

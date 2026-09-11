-- Administrative test. Transaction-local fixtures are always rolled back.
begin;
select set_config('test.host',gen_random_uuid()::text,true);
select set_config('test.member',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) select current_setting('test.'||x)::uuid,'poruch-search-'||current_setting('test.'||x)||'@example.invalid',jsonb_build_object('birth_date','1990-01-01') from unnest(array['host','member']) x;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
select gen_random_uuid(),current_setting('test.host')::uuid,'SearchFixture Full '||i,'','social','Test','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',1 from generate_series(1,301) i;
insert into public.event_members(event_id,user_id) select id,current_setting('test.member')::uuid from public.events where organizer_id=current_setting('test.host')::uuid;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values(gen_random_uuid(),current_setting('test.host')::uuid,'SearchFixture Музика 100%_','needle-description','music','needle-city','needle-address',50.45,30.52,now()+interval '3 days',now()+interval '4 days','Europe/Kyiv',10);
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 assert (select count(*)=300 from public.search_events_in_view(49,29,51,32,p_text=>'SearchFixture')),'unfiltered limit';
 assert (select count(*)=1 from public.search_events_in_view(49,29,51,32,p_text=>'SearchFixture',p_available=>true)),'capacity filters before 300 limit despite guest RLS';
 assert (select count(*)=1 from public.search_events_in_view(49,29,51,32,p_text=>'  мУзИкА  ')),'Unicode case-insensitive trimmed query';
 assert (select count(*)=1 from public.search_events_in_view(49,29,51,32,p_text=>'100%_')),'literal percent and underscore';
 assert (select count(*)=0 from public.search_events_in_view(49,29,51,32,p_text=>'100%%')),'no SQL wildcard expansion';
 assert (select count(*)=1 from public.search_events_in_view(49,29,51,32,p_text=>'needle-description')),'description';
 assert (select count(*)=1 from public.search_events_in_view(49,29,51,32,p_text=>'needle-city')),'city';
 assert (select count(*)=1 from public.search_events_in_view(49,29,51,32,p_text=>'needle-address')),'address';
 assert (select count(*)=0 from public.search_events_in_view(49,29,51,32,p_category=>'social',p_text=>'needle-description')),'combined category';
 begin perform public.search_events_in_view(91,0,92,1); raise exception 'invalid bounds accepted'; exception when sqlstate '22023' then assert sqlerrm='INVALID_BOUNDS'; end;
 begin perform public.search_events_in_view(49,29,51,32,p_text=>repeat('x',121)); raise exception 'long search accepted'; exception when sqlstate '22023' then assert sqlerrm='INVALID_SEARCH_TEXT'; end;
 begin perform 1 from public.event_members; raise exception 'guest roster access permitted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: search, literal symbols, pre-limit availability, RLS, validation' as result;
rollback;

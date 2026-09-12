-- Administrative test. Transaction-local fixtures are always rolled back.
begin;
select set_config('test.host',gen_random_uuid()::text,true);
select set_config('test.member',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) select current_setting('test.'||x)::uuid,'poruch-search-'||current_setting('test.'||x)||'@example.invalid',jsonb_build_object('birth_date','1990-01-01') from unnest(array['host','member']) x;
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
select gen_random_uuid(),current_setting('test.host')::uuid,'SearchFixture Full '||i,'','social','Test','Park',50.45,30.52,now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',1 from generate_series(1,301) i;
-- Виставка, що вже йде: почалась 38 днів тому, прокат до кінця тижня. До 20260911120000 її не
-- існувало для жодного екрана, бо умова стояла на часі початку. Місткість 1, як у сусідів вище:
-- рядок з учасниками нижче заповнює її, і перевірка «Є місця» лишається про одну подію.
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values(gen_random_uuid(),current_setting('test.host')::uuid,'SearchFixture Прокат','','art','Test','Park',50.45,30.52,now()-interval '38 days',now()+interval '3 days','Europe/Kyiv',1);
-- І те, що вже скінчилось: умова на `ends_at` не має стати дверима для минулого.
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values(gen_random_uuid(),current_setting('test.host')::uuid,'SearchFixture Минуле','','art','Test','Park',50.45,30.52,now()-interval '9 days',now()-interval '8 days','Europe/Kyiv',1);
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
 assert (select count(*)=1 from public.search_events_in_view(49,29,51,32,p_text=>'SearchFixture Прокат')),'an event already under way is still discoverable';
 assert (select count(*)=0 from public.search_events_in_view(49,29,51,32,p_text=>'SearchFixture Минуле')),'an event that has ended is not';
 -- «На вихідних» питає, що ПОЧНЕТЬСЯ на вихідних, а не що тоді триватиме: `p_from`/`p_to`
 -- лишаються на `starts_at`, інакше кожен прокат потрапляв би в кожне вікно дат.
 assert (select count(*)=0 from public.search_events_in_view(49,29,51,32,p_from=>now(),p_text=>'SearchFixture Прокат')),'date window still asks about the start';
 -- Порядок: `greatest(starts_at, now())` згортає все, що вже йде, в одну точку «зараз», далі
 -- розрізняючи за `id`. Тут це не перевірити — `id` випадковий, а прокат у наборі один. Що
 -- перевірити можна: він змагається як «зараз», тобто попереду того, що почнеться завтра.
 assert (select title from public.search_events_in_view(49,29,51,32,p_text=>'SearchFixture') limit 1)='SearchFixture Прокат','what is already under way competes as now';
 -- Те саме у функції, якою ходять клієнти. Позиція 6 у кортежі індексу — назва; вона ж
 -- `Column.TITLE` у `DiscoveryDto.kt`, і розійтись їм не можна.
 assert (public.discover_events(49,29,51,32,p_text=>'SearchFixture Прокат')->>'total')::int=1,'ongoing event reaches the index';
 assert public.discover_events(49,29,51,32,p_text=>'SearchFixture')->'index'->0->>6='SearchFixture Прокат','index leads with what is under way';
 begin perform public.search_events_in_view(91,0,92,1); raise exception 'invalid bounds accepted'; exception when sqlstate '22023' then assert sqlerrm='INVALID_BOUNDS'; end;
 begin perform public.search_events_in_view(49,29,51,32,p_text=>repeat('x',121)); raise exception 'long search accepted'; exception when sqlstate '22023' then assert sqlerrm='INVALID_SEARCH_TEXT'; end;
 begin perform 1 from public.event_members; raise exception 'guest roster access permitted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: search, ongoing events, date window, order, literal symbols, pre-limit availability, RLS, validation' as result;
rollback;

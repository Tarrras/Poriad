-- Запускати адміністратором бази. Усе відкочується. Вимикач кіно (20261115120000, docs/cinema-import.md): прапорець
-- `cinema` і вимкнена мережа ховають кіно з видачі, «Що тут», пошуку місць і підписок на заклад; без `p_cinema`
-- (збірки 1.3.x) кіно нема й з прапорцем; решта афіші закладу від вимикача не залежить.
begin;

insert into public.event_sources(slug,name,kind,base_url,enabled) values ('test_cinema','Test','manual','https://example.invalid',true);
insert into public.places (name, city, address, latitude, longitude, source)
values ('Тест-кінотеатр Лагуна', 'Ocean', 'Buoy, 9', -41.3, -31.3, 'manual');
select set_config('test.place',(select id::text from public.places where name='Тест-кінотеатр Лагуна'),true),
 set_config('test.user',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
values (current_setting('test.user')::uuid,'poruch-cinema-'||current_setting('test.user')||'@example.invalid',jsonb_build_object('birth_date','1990-01-01'));

-- Два сеанси одного фільму й концерт у тому самому залі.
insert into public.events(id,title,description,category,city,address,latitude,longitude,place_id,starts_at,ends_at,time_zone,
 origin,source_id,source_uid,import_status,quality)
select gen_random_uuid(),t,'',c,'Ocean','Buoy, 9',-41.3,-31.3,current_setting('test.place')::uuid,now()+s,now()+s+interval '2 hours',
 'Europe/Kyiv','import',(select id from public.event_sources where slug='test_cinema'),t||s::text,'live',0.9
from (values ('Лагуна-фільм','cinema',interval '1 day'),('Лагуна-фільм','cinema',interval '2 days'),
             ('Лагуна-концерт','music',interval '1 day')) v(t,c,s);
insert into public.follows(user_id,target_kind,target_id) values (current_setting('test.user')::uuid,'place',current_setting('test.place')::uuid);

create function pg_temp.seen(p_cinema boolean) returns text[] language sql as $$
 select array(select r->>6 || ':' || case when jsonb_typeof(r->13) = 'array' then jsonb_array_length(r->13) else 1 end
              from jsonb_array_elements(public.discover_events(-42,-32,-41,-31,p_cards=>0,p_cinema=>p_cinema)->'index') r
              order by 1);
$$;
create function pg_temp.at_place(p_cinema boolean) returns text[] language sql as $$
 select array(select c->>'title' from jsonb_array_elements(public.place_events(current_setting('test.place')::uuid, 100, p_cinema)) c
              order by 1);
$$;
create function pg_temp.upcoming(p_cinema boolean) returns int language sql as $$
 select (public.search_places('лагуна', p_cinema=>p_cinema)->0->>'upcoming')::int;
$$;
create function pg_temp.followed() returns bigint language sql as $$
 select count(*) from private.followed_events where user_id = current_setting('test.user')::uuid and title = 'Лагуна-фільм';
$$;

do $$ begin
 assert exists (select 1 from private.flags where name = 'cinema'), 'прапорець зареєстровано';
 update private.flags set enabled = false where name = 'cinema';
 assert pg_temp.seen(true) = array['Лагуна-концерт:1'], 'прапорець вимкнено — кіно нема навіть новій збірці';
 assert pg_temp.at_place(true) = array['Лагуна-концерт'], '«Що тут» без кіно, концерт лишається';
 assert pg_temp.upcoming(true) = 1, 'у пошуку місць лічиться лише концерт';
 assert pg_temp.followed() = 0, 'підписка на заклад кіно не бачить';

 update private.flags set enabled = true where name = 'cinema';
 assert pg_temp.seen(true) = array['Лагуна-концерт:1','Лагуна-фільм:2'], 'прапорець увімкнено — прокат одним рядком, два сеанси';
 assert pg_temp.seen(false) = array['Лагуна-концерт:1'], 'без p_cinema (1.3.x) кіно нема й з прапорцем';
 assert pg_temp.at_place(true) = array['Лагуна-концерт','Лагуна-фільм','Лагуна-фільм'], '«Що тут» — усі сеанси';
 assert pg_temp.at_place(false) = array['Лагуна-концерт'], '«Що тут» у 1.3.x без кіно';
 assert pg_temp.upcoming(true) = 2 and pg_temp.upcoming(false) = 1, 'пошук місць лічить фільм лише з p_cinema';
 assert pg_temp.followed() = 2, 'підписка на заклад бачить сеанси';

 update public.event_sources set enabled = false where slug = 'test_cinema';
 assert pg_temp.seen(true) = array['Лагуна-концерт:1'], 'вимкнена мережа — без її кіно, решта афіші закладу лишається';
 assert pg_temp.at_place(true) = array['Лагуна-концерт'], 'у «Що тут» ховається лише кіно вимкненої мережі';
 assert pg_temp.followed() = 0, 'і з підписок';
end $$;

rollback;

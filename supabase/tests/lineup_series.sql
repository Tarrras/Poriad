-- Запускати адміністратором бази. Усе відкочується. Склад і серія (20261130120000): організатор називає артистів своєї
-- події (з каталогу й нових), чужу подію не чіпає; серія — до 12 подій поза денною стелею, пуш підписникам один.
-- Чужих рядків не чіпає.
begin;

create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;

select set_config('test.u1',gen_random_uuid()::text,true),set_config('test.u2',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-lineup-'||id||'@example.invalid',jsonb_build_object('display_name','Кафе Lineup','birth_date','1990-01-01')
from unnest(array[current_setting('test.u1'),current_setting('test.u2')]) id;
insert into public.artists(name,key,kind) values ('Lineup Solo','lineup solo test','person'),('Lineup Own','lineup own test','group');
select set_config('test.solo',(select id::text from public.artists where key='lineup solo test'),true),
 set_config('test.own',(select id::text from public.artists where key='lineup own test'),true);
do $$ begin perform private.set_artist_owner(current_setting('test.own')::uuid,current_setting('test.u1')::uuid); end $$;

-- Подія: ім'я фікстури, серія (id першої події) і через скільки днів.
create function pg_temp.make(p_name text, p_series uuid default null, p_days integer default 1) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
 perform public.create_event(p_id => v_id, p_title => 'Вечір Lineup '||p_name, p_description => 'Test description',
  p_category => 'music', p_city => 'Ocean', p_address => 'Buoy, 12', p_latitude => -46.1, p_longitude => -36.1,
  p_starts_at => now()+make_interval(days => p_days), p_ends_at => now()+make_interval(days => p_days, hours => 2), p_time_zone => 'UTC',
  p_capacity => 20, p_via => 'web', p_series => p_series);
 perform set_config('test.'||p_name, v_id::text, true);
 return v_id;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u2'),true);
do $$ begin perform pg_temp.make('foreign'); end $$;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$
declare v jsonb;
begin
 perform pg_temp.make('head');
 -- З каталогу, новий і той самий ще раз за назвою: без повторів, свій артист (власник) лишається.
 v := public.set_event_lineup(current_setting('test.head')::uuid, array[current_setting('test.solo')::uuid],
  '[{"name":"  Гурт   «Lineup New» ","kind":"group"},{"name":"lineup solo test"}]'::jsonb);
 assert jsonb_array_length(v) = 3,'own + solo + new: '||v::text;
 assert (v->0->>'id') = current_setting('test.own') and (v->0->>'own')::boolean,'the owner''s artist first, marked own';
 assert (v->1->>'id') = current_setting('test.solo') and not (v->1 ? 'own') and v->2->>'name' = 'Гурт «Lineup New»','catalog, then the new one';
 begin perform public.set_event_lineup(current_setting('test.head')::uuid, array[gen_random_uuid()]); raise exception 'unknown artist';
 exception when sqlstate 'P0001' then assert sqlerrm='ARTIST_NOT_FOUND'; end;
 begin perform public.set_event_lineup(current_setting('test.head')::uuid, null, '[{"name":"X"}]'::jsonb); raise exception 'short name';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_ARTIST_NAME'; end;
 begin perform public.set_event_lineup(current_setting('test.head')::uuid, null, '[{"name":"Lineup Show","kind":"show"}]'::jsonb); raise exception 'bad kind';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_ARTIST_KIND'; end;
 begin perform public.set_event_lineup(current_setting('test.head')::uuid, null, '{"name":"Lineup Obj"}'::jsonb); raise exception 'not an array';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_LINEUP'; end;
 begin perform public.set_event_lineup(current_setting('test.head')::uuid, null,
   (select jsonb_agg(jsonb_build_object('name','Lineup Many '||i)) from generate_series(1,9) i)); raise exception 'nine artists';
 exception when sqlstate 'P0001' then assert sqlerrm='TOO_MANY_ARTISTS'; end;
 begin perform public.set_event_lineup(current_setting('test.foreign')::uuid, array[current_setting('test.solo')::uuid]); raise exception 'someone else''s event';
 exception when insufficient_privilege then assert sqlerrm='NOT_ORGANIZER'; end;
end $$;
reset role;
do $$ begin
 assert (select name = 'Гурт «Lineup New»' and kind = 'group' and source = 'manual' and created_by = current_setting('test.u1')::uuid
         from public.artists where key = 'гурт lineup new'),'the new artist: trimmed, manual, with its author';
 assert not exists (select 1 from public.artists where key like 'lineup many %'),'a refused lineup creates nobody';
 assert (select count(*) = 2 from public.event_artists where event_id = current_setting('test.head')::uuid and how = 'lineup');
 assert not exists (select 1 from public.event_artists where event_id = current_setting('test.foreign')::uuid);
end $$;

-- Гість: склад видно в картці й на сторінці артиста; поставити не може.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$
declare c jsonb;
begin
 c := public.event_cards_by_ids(array[current_setting('test.head')::uuid]);
 assert jsonb_array_length(c->0->'artists') = 3 and (select count(*) from jsonb_array_elements(c->0->'artists') a
  where a->>'name' in ('Lineup Own','Lineup Solo','Гурт «Lineup New»')) = 3,'the card names the lineup: '||coalesce((c->0->'artists')::text,'null');
 assert exists (select 1 from jsonb_array_elements(public.artist_events(current_setting('test.solo')::uuid)) e where e->>'id' = current_setting('test.head')),
  'the event is on the artist''s page';
 begin perform public.set_event_lineup(current_setting('test.head')::uuid, null); raise exception 'anon set a lineup';
 exception when insufficient_privilege then null; end;
end $$;
reset role;

-- Порожній список знімає склад організатора; свій артист лишається.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$ begin
 assert public.set_event_lineup(current_setting('test.head')::uuid, null) = jsonb_build_array(
  jsonb_build_object('id',current_setting('test.own'),'name','Lineup Own','kind','group','own',true)),'only the owner''s artist is left';
end $$;

-- Серія: ще одинадцять дат поза денною стелею, дванадцята зайва — ні; чужа перша подія й подія серії — не голова.
do $$
declare i integer;
begin
 for i in 1..11 loop perform pg_temp.make('s'||i, current_setting('test.head')::uuid, 1 + 7*i); end loop;
 begin perform pg_temp.make('s12', current_setting('test.head')::uuid, 90); raise exception 'a thirteenth event in the series';
 exception when sqlstate 'P0001' then assert sqlerrm='TOO_MANY_EVENTS'; end;
 begin perform pg_temp.make('bad', current_setting('test.foreign')::uuid); raise exception 'a series on someone else''s event';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_SERIES'; end;
 begin perform pg_temp.make('bad', current_setting('test.s1')::uuid); raise exception 'a series on a series member';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_SERIES'; end;
 begin perform pg_temp.make('bad', gen_random_uuid()); raise exception 'a series on nothing';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_SERIES'; end;
 -- Дванадцять подій за добу, а окрему ще можна: стеля рахує окремі події й перші події серій.
 perform pg_temp.make('single');
end $$;
reset role;
do $$ begin
 assert (select count(*) = 12 from public.events where series_id = current_setting('test.head')::uuid),'the head joins its own series';
 assert (select series_id is null from public.events where id = current_setting('test.single')::uuid);
 assert (select count(*) = 12 from public.event_artists ea join public.events e on e.id = ea.event_id
         where e.series_id = current_setting('test.head')::uuid and ea.artist_id = current_setting('test.own')::uuid),'every date carries the owner''s artist';
 assert (select array_agg(payload->>'event_id' order by payload->>'event_id') from pg_temp.sent
         where payload->>'kind' = 'organizer' and payload->>'event_id' <> current_setting('test.foreign'))
  = (select array_agg(x order by x) from unnest(array[current_setting('test.head'),current_setting('test.single')]) x),
  'followers hear about the first date and the single event, not about eleven more';
end $$;

rollback;

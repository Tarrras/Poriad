-- Запускати адміністратором бази. Усе відкочується. Заклад і артист з власником (20261126120000): подія власника
-- стає на заклад і до артиста, її бачать їхні підписники, а чужа подія на тих самих координатах — ні.
begin;

-- Чужих рядків не чіпаємо: усі перевірки — лише про свої фікстури, тож справжні підписки в базі не заважають.

create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select 'https://example.invalid'::text, 'x'::text $$;

-- owner веде заклад і артиста; other — сторонній організатор; a стежить за закладом, b — за закладом і самим
-- організатором, c — за артистом.
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.other',gen_random_uuid()::text,true),
 set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.c',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-owned-'||id||'@example.invalid',jsonb_build_object('display_name','O','birth_date','1990-01-01')
from unnest(array[current_setting('test.owner'),current_setting('test.other'),current_setting('test.a'),
 current_setting('test.b'),current_setting('test.c')]) id;
insert into public.push_tokens(token,user_id,platform) values
 ('owned-test-a-0123456789',current_setting('test.a')::uuid,'android'),('owned-test-b-0123456789',current_setting('test.b')::uuid,'ios'),
 ('owned-test-c-0123456789',current_setting('test.c')::uuid,'ios');

insert into public.places(name,city,address,latitude,longitude,source) values ('Кафе Owned','Ocean','Buoy, 9',-42.1,-32.1,'osm');
insert into public.artists(name,key,kind) values ('Гурт Owned','owned-test-band','group');
select set_config('test.place',(select id::text from public.places where name='Кафе Owned'),true),
 set_config('test.artist',(select id::text from public.artists where key='owned-test-band'),true);

-- Подія від людей: ім'я фікстури, організатор, зсув на північ у градусах (0.001° ≈ 111 м), через скільки початок.
create function pg_temp.ev(p_name text,p_organizer text,p_north double precision,p_start interval,p_companion uuid default null)
returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,companion_of)
 values (v_id,current_setting('test.'||p_organizer)::uuid,'Вечір '||p_name,'Test description','music','Ocean','Buoy, 9',
  -42.1+p_north,-32.1,now()+p_start,now()+p_start+interval '2 hours','UTC',case when p_companion is null then 10 else 4 end,p_companion);
 perform set_config('test.'||p_name,v_id::text,true);
 return v_id;
end $$;
create function pg_temp.place_of(p_name text) returns uuid language sql as $$
 select place_id from public.events where id = current_setting('test.'||p_name)::uuid $$;

-- Подія з афіші в цьому ж закладі: на неї піде супутник «Шукаю компанію».
insert into public.event_sources(slug,name,kind,base_url) values ('test_owned','Test','manual','https://example.invalid');
select set_config('test.poster',gen_random_uuid()::text,true);
insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
 origin,source_id,source_uid,import_status,quality,place_id)
values (current_setting('test.poster')::uuid,'Концерт з афіші','','music','Ocean','Buoy, 9',-42.1,-32.1,now()+interval '1 day',
 now()+interval '1 day 2 hours','UTC','import',(select id from public.event_sources where slug='test_owned'),'owned-poster','live',0.9,
 current_setting('test.place')::uuid);

-- До власника: подія на координатах закладу — без закладу й без артиста.
select pg_temp.ev('early','owner',0,interval '1 day');
do $$ begin
 assert pg_temp.place_of('early') is null,'no owner yet: no place';
 assert not exists (select 1 from public.event_artists where event_id = current_setting('test.early')::uuid),'no owner yet: no artist';
end $$;

-- Клієнт призначити власника не може.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.other'),true);
do $$ begin
 begin perform private.set_place_owner(current_setting('test.place')::uuid,current_setting('test.other')::uuid); raise exception 'a client claimed a place';
 exception when insufficient_privilege then null; end;
 begin perform private.set_artist_owner(current_setting('test.artist')::uuid,current_setting('test.other')::uuid); raise exception 'a client claimed an artist';
 exception when insufficient_privilege then null; end;
 begin update public.places set owner_id = current_setting('test.other')::uuid where id = current_setting('test.place')::uuid; raise exception 'a client wrote owner_id';
 exception when insufficient_privilege then null; end;
end $$;
reset role;

-- Адміністратор призначає: майбутні події власника підтягуються; невідомий заклад — помилка.
do $$ begin
 assert private.set_place_owner(current_setting('test.place')::uuid,current_setting('test.owner')::uuid) = 1,'the owner''s upcoming event moved to the place';
 assert pg_temp.place_of('early') = current_setting('test.place')::uuid;
 assert private.set_place_owner(current_setting('test.place')::uuid,current_setting('test.owner')::uuid) = 0,'a repeat changes nothing';
 assert private.set_artist_owner(current_setting('test.artist')::uuid,current_setting('test.owner')::uuid) = 1,'the upcoming event got the artist';
 assert private.set_artist_owner(current_setting('test.artist')::uuid,current_setting('test.owner')::uuid) = 0;
 begin perform private.set_place_owner(gen_random_uuid(),current_setting('test.owner')::uuid); raise exception 'unknown place accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='PLACE_NOT_FOUND'; end;
 begin perform private.set_artist_owner(gen_random_uuid(),current_setting('test.owner')::uuid); raise exception 'unknown artist accepted';
 exception when sqlstate 'P0001' then assert sqlerrm='ARTIST_NOT_FOUND'; end;
end $$;

-- Підписки — до нових подій: «нове» рахується від підписки.
insert into public.follows(user_id,target_kind,target_id,created_at) values
 (current_setting('test.a')::uuid,'place',current_setting('test.place')::uuid,now()-interval '2 hours'),
 (current_setting('test.b')::uuid,'place',current_setting('test.place')::uuid,now()-interval '2 hours'),
 (current_setting('test.b')::uuid,'organizer',current_setting('test.owner')::uuid,now()-interval '2 hours'),
 (current_setting('test.c')::uuid,'artist',current_setting('test.artist')::uuid,now()-interval '2 hours');
update public.events set created_at = now()-interval '3 hours' where id in (current_setting('test.early')::uuid,current_setting('test.poster')::uuid);

-- Нові події: власник поруч (≈ 55 м), власник далеко (≈ 550 м), сторонній на тих самих координатах, супутник власника.
select pg_temp.ev('near','owner',0.0005,interval '2 days');
select pg_temp.ev('far','owner',0.005,interval '3 days');
select pg_temp.ev('stranger','other',0,interval '2 days');
select pg_temp.ev('comp','owner',0,interval '1 day',current_setting('test.poster')::uuid);
-- Сторонній «сів» на заклад і до артиста руками — як могло б статися з імпортом координат чи складу.
update public.events set place_id = current_setting('test.place')::uuid where id = current_setting('test.stranger')::uuid;
insert into public.event_artists(event_id,artist_id,role,position,how,confidence)
values (current_setting('test.stranger')::uuid,current_setting('test.artist')::uuid,'headliner',0,'source',1);

do $$ begin
 assert pg_temp.place_of('near') = current_setting('test.place')::uuid,'within 150 m: on the place';
 assert pg_temp.place_of('far') is null,'550 m away: not the place';
 assert pg_temp.place_of('comp') is null,'a companion is not the venue''s event';
 assert (select count(*) = 3 from public.event_artists ea join public.events e on e.id = ea.event_id
         where ea.artist_id = current_setting('test.artist')::uuid and e.organizer_id = current_setting('test.owner')::uuid),
  'early (backfilled), near and far carry the artist; the companion does not';
 assert not exists (select 1 from public.event_artists where event_id = current_setting('test.comp')::uuid);
end $$;

-- Хто що бачить у підписках.
do $$
declare v_a uuid := current_setting('test.a')::uuid; v_b uuid := current_setting('test.b')::uuid; v_c uuid := current_setting('test.c')::uuid;
begin
 assert (select array_agg(event_id order by starts_at, title) from private.followed_events where user_id = v_a and target_kind = 'place')
  = array[current_setting('test.early')::uuid,current_setting('test.poster')::uuid,current_setting('test.near')::uuid],
  'the place follower sees the poster and the owner''s events at the place, not the stranger''s';
 assert not exists (select 1 from private.followed_events where user_id = v_b and target_kind = 'place'
                    and event_id <> current_setting('test.poster')::uuid),
  'following the organizer too: the owner''s event comes once, as the organizer''s; the poster stays';
 assert (select count(*) = 3 from private.followed_events where user_id = v_b and target_kind = 'organizer'),'early, near and far';
 assert (select array_agg(event_id order by starts_at) from private.followed_events where user_id = v_c and target_kind = 'artist')
  = array[current_setting('test.early')::uuid,current_setting('test.near')::uuid,current_setting('test.far')::uuid],
  'the artist follower sees the owner''s events, not the stranger''s';
end $$;

-- Пуш закладу: лише a, лише нова подія (early з'явилась до підписки). b уже отримав її як подію організатора.
do $$
declare v_place jsonb;
begin
 assert (select count(*) = 2 from pg_temp.sent where payload->>'kind' = 'organizer'
         and payload->>'event_id' in (current_setting('test.near'),current_setting('test.far'))),'near and far pushed at once to the organizer''s followers';
 perform private.notify_place_follows();
 select payload into v_place from pg_temp.sent where payload->>'kind' = 'place' and payload->>'user_id' = current_setting('test.a');
 assert v_place is not null,'the place follower gets the digest';
 assert v_place->'event_ids' = jsonb_build_array(current_setting('test.near')),'only the new event at the place: early and the poster predate the follow';
 assert not exists (select 1 from pg_temp.sent where payload->>'kind' = 'place' and payload->>'user_id' = current_setting('test.b')),
  'the one who follows the organizer too gets no second push';
end $$;

-- Перенесли з закладу — знімається; повернули — стає знову. Чужий place_id переїзд не чіпає.
update public.events set latitude = -42.1+0.005 where id = current_setting('test.near')::uuid;
do $$ begin assert pg_temp.place_of('near') is null,'moved away'; end $$;
update public.events set latitude = -42.1 where id = current_setting('test.near')::uuid;
do $$ begin assert pg_temp.place_of('near') = current_setting('test.place')::uuid,'moved back'; end $$;
update public.events set latitude = -42.1+0.0001 where id = current_setting('test.stranger')::uuid;
do $$ begin assert pg_temp.place_of('stranger') = current_setting('test.place')::uuid,'a stranger''s place_id is left alone'; end $$;

-- Власника зняли: нові події більше не стають на заклад, а старі зникають з підписок закладу.
do $$ begin
 perform private.set_place_owner(current_setting('test.place')::uuid,null);
 assert (select array_agg(event_id) from private.followed_events where user_id = current_setting('test.a')::uuid and target_kind = 'place')
  = array[current_setting('test.poster')::uuid],'only the poster is left at the place';
end $$;
select pg_temp.ev('after','owner',0,interval '4 days');
do $$ begin assert pg_temp.place_of('after') is null,'no owner: no place'; end $$;

-- Акаунт власника видалили — заклад і артист лишаються, просто без власника (on delete set null).
do $$ begin
 assert (select count(*) = 2 from pg_constraint c where c.contype = 'f' and c.confdeltype = 'n'
         and c.conname in ('places_owner_id_fkey','artists_owner_id_fkey')),'owner_id is cleared, the row stays';
end $$;

rollback;

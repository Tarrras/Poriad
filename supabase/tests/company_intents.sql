-- Запускати адміністратором бази. Усе відкочується. «Хочу піти з компанією» (docs/return-hooks.md, хвиля 1): намір і
-- відмови, тизер гостю й з входом (без віку), люди лише для тих, хто сам має намір, «бачиш те, що показуєш» (Instagram),
-- блокування, «Піти разом» → збіг → супутник, третій у той самий супутник, пуші, 12-та позиція видачі, зняття.
begin;

-- Пуші ловимо в таблицю замість pg_net, адреса функції підроблена.
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select 'https://example.invalid'::text, 'x'::text $$;

select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.c',gen_random_uuid()::text,true),set_config('test.d',gen_random_uuid()::text,true),
 set_config('test.g',gen_random_uuid()::text,true),set_config('test.x',gen_random_uuid()::text,true),
 set_config('test.p1',gen_random_uuid()::text,true),set_config('test.p2',gen_random_uuid()::text,true),
 set_config('test.room',gen_random_uuid()::text,true);
-- Вік: a — 36 (35–39), b — 26 (25–29), c — 31 (30–34), d — 40. x — без дати народження.
insert into auth.users(id,email,raw_user_meta_data)
select current_setting('test.'||k)::uuid,'poruch-company-'||k||'-'||current_setting('test.'||k)||'@example.invalid',
 jsonb_build_object('display_name',upper(k)||' Прізвище')
  || case when bd is null then '{}'::jsonb else jsonb_build_object('birth_date',bd) end
from (values ('a',(current_date - interval '36 years 1 day')::date::text),('b',(current_date - interval '26 years 1 day')::date::text),
 ('c',(current_date - interval '31 years 1 day')::date::text),('d',(current_date - interval '40 years 1 day')::date::text),
 ('g','1990-01-01'),('x',null)) v(k,bd);
-- Пуш знають усі, крім d (застосунок до 1.4).
insert into public.push_tokens(token,user_id,platform,features)
select 'company-test-'||k||'-0123456789',current_setting('test.'||k)::uuid,'android',
 case when k='d' then array['companion_decision','companion'] else array['companion_decision','companion','company'] end
from unnest(array['a','b','c','d','g']) k;
update public.user_preferences set categories = case user_id
 when current_setting('test.a')::uuid then array['music','comedy','food']
 when current_setting('test.b')::uuid then array['music','comedy']
 when current_setting('test.c')::uuid then array['music','sport']
 else categories end
where user_id in (current_setting('test.a')::uuid,current_setting('test.b')::uuid,current_setting('test.c')::uuid);
-- a заблокував d.
insert into public.user_blocks(user_id,blocked_id) values (current_setting('test.a')::uuid,current_setting('test.d')::uuid);

insert into public.event_sources(slug,name,kind,base_url) values ('test_company','Test','manual','https://example.invalid');
-- p1 — афіша за два дні, p2 — уже почалась.
insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,origin,source_id,source_uid,import_status,quality)
select current_setting('test.'||k)::uuid,'Афіша '||k,'','music','Ocean','Buoy, 1',-40.5,-30.5,date_trunc('hour',now())+d,date_trunc('hour',now())+d+interval '3 hours',
 'Europe/Kyiv','import',(select id from public.event_sources where slug='test_company'),'co-'||k,'live',0.9
from (values ('p1',interval '2 days'),('p2',interval '-1 hour')) v(k,d);

create function pg_temp.as_user(p_who text) returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub',coalesce(current_setting('test.'||p_who,true),''),true);
end $$;
create function pg_temp.intent(p_who text,p_event text,p_on boolean default true) returns integer language plpgsql as $$
declare n integer;
begin
 perform pg_temp.as_user(p_who);
 set local role authenticated;
 n := public.set_company_intent(current_setting('test.'||p_event)::uuid,p_on);
 reset role;
 return n;
end $$;
create function pg_temp.yes(p_who text,p_to text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
 perform pg_temp.as_user(p_who);
 set local role authenticated;
 r := public.company_yes(current_setting('test.p1')::uuid,current_setting('test.'||p_to)::uuid);
 reset role;
 return r;
end $$;
create function pg_temp.fails(p_sql text) returns text language plpgsql as $$
begin
 set local role authenticated;
 execute p_sql;
 reset role;
 return null;
exception when others then
 reset role;
 return sqlerrm;
end $$;

-- ── Гість на порожній афіші: нуль, не мій.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ declare t record; begin
 select * into t from public.company_teaser(current_setting('test.p1')::uuid);
 assert t.count = 0 and not t.mine, 'empty teaser for a guest';
end $$;
reset role;

-- ── Відмови.
select pg_temp.as_user('x');
do $$ begin
 assert pg_temp.fails('select public.set_company_intent('''||current_setting('test.p1')||''',true)') = 'AGE_REQUIRED',
  'no birth date — no intent';
end $$;
select pg_temp.as_user('a');
do $$ begin
 assert pg_temp.fails('select public.set_company_intent('''||current_setting('test.p2')||''',true)') = 'COMPANION_UNAVAILABLE',
  'an event that has started takes no intents';
end $$;

-- ── a — перший: нікого нема, пуша нема.
do $$ begin
 assert pg_temp.intent('a','p1') = 0, 'a is the first';
 assert pg_temp.intent('a','p1') = 0, 'a repeat changes nothing';
 assert not exists(select 1 from pg_temp.sent), 'nobody to tell yet';
end $$;

-- ── b: пуш «ще хтось» — a.
do $$ declare v jsonb; begin
 assert pg_temp.intent('b','p1') = 1, 'b sees one other';
 select payload into v from pg_temp.sent;
 assert v->>'type' = 'company' and v->>'event_id' = current_setting('test.p1') and v->>'title' = 'Афіша p1'
  and v->'user_ids' = jsonb_build_array(current_setting('test.a')), 'a is told that someone else wants to go';
end $$;
delete from pg_temp.sent;

-- ── c: a вже казали сьогодні — лише b. d (без пуша 1.4, заблокований a) — ставить намір, a про нього не дізнається.
do $$ begin
 assert pg_temp.intent('c','p1') = 2, 'c sees two others';
 assert (select payload->'user_ids' from pg_temp.sent) = jsonb_build_array(current_setting('test.b')), 'a was told today, only b now';
 delete from pg_temp.sent;
 assert pg_temp.intent('d','p1') = 2, 'd does not count a (blocked)';
 assert (select payload->'user_ids' from pg_temp.sent) = jsonb_build_array(current_setting('test.c')), 'a blocked d, b was told today: only c';
end $$;
delete from pg_temp.sent;

-- Усе в одній транзакції має той самий now(): розводимо час наміру, щоб «хто раніше» був a, b, c, d.
update private.company_intents set created_at = now() - interval '1 minute' * (5 - position(k in 'abcd'))
from (select current_setting('test.'||k)::uuid as id, k from unnest(array['a','b','c','d']) k) u where user_id = u.id;

-- ── Тизер: гість — усі четверо, без спільного; a — без d, спільне з a.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ declare t record; begin
 select * into t from public.company_teaser(current_setting('test.p1')::uuid);
 assert t.count = 4 and t.shared = '{}' and not t.mine, 'guest teaser: '||row(t)::text;
end $$;
reset role;
select pg_temp.as_user('a');
set local role authenticated;
do $$ declare t record; begin
 select * into t from public.company_teaser(current_setting('test.p1')::uuid);
 assert t.count = 2 and t.mine, 'a teaser: '||row(t)::text;
 assert t.shared = array['music','comedy'], 'shared with a, most common first: '||t.shared::text;
end $$;
reset role;

-- ── Люди: g без наміру — нікого; a — b і c, без d. Instagram — лише коли в a свій.
select pg_temp.as_user('b');
set local role authenticated;
select public.set_instagram('b.handle');
reset role;
select pg_temp.as_user('g');
set local role authenticated;
do $$ begin
 assert not exists(select 1 from public.company_people(current_setting('test.p1')::uuid)), 'no intent — no people';
 assert not exists(select 1 from public.profile_card(current_setting('test.b')::uuid)), 'no intent — no card';
end $$;
reset role;
select pg_temp.as_user('a');
set local role authenticated;
do $$ declare r record; begin
 assert (select array_agg(user_id order by user_id) from public.company_people(current_setting('test.p1')::uuid))
  = array(select x::uuid from unnest(array[current_setting('test.b'),current_setting('test.c')]) x order by 1), 'a sees b and c, not d';
 select * into r from public.company_people(current_setting('test.p1')::uuid) where user_id = current_setting('test.b')::uuid;
 assert r.name = 'B' and r.shared = array['comedy','music'] and r.attended = 0, 'b row: '||row(r)::text;
 assert r.instagram is null, 'a has no Instagram — sees none';
 assert (select instagram from public.profile_card(current_setting('test.b')::uuid)) is null, 'nor in the card';
 assert exists(select 1 from public.profile_card(current_setting('test.b')::uuid)), 'but a sees b''s card';
end $$;
select public.set_instagram('  A_H  ');
do $$ begin
 assert (select instagram from public.company_people(current_setting('test.p1')::uuid) where user_id = current_setting('test.b')::uuid) = 'b.handle',
  'with own Instagram, a sees b''s';
 assert (select instagram from public.profile_card(current_setting('test.b')::uuid)) = 'b.handle', 'and in the card';
 assert (select instagram from public.profile_card(current_setting('test.a')::uuid)) = 'a_h', 'own handle is normalized';
 assert pg_temp.fails('select public.set_instagram(''https://instagram.com/a'')') = 'INVALID_INSTAGRAM', 'a link is not a handle';
end $$;
reset role;

-- ── «Піти разом»: a → b — пуш b; повтор — тиша; a → d — блок; g → b — не в компанії.
do $$ declare r jsonb; v jsonb; begin
 r := pg_temp.yes('a','b');
 assert r = '{"matched": false}'::jsonb, 'a → b is not a match yet';
 select payload into v from pg_temp.sent;
 assert v->>'body' = 'A хоче піти з вами' and v->'user_ids' = jsonb_build_array(current_setting('test.b')), 'b is told: '||v::text;
 delete from pg_temp.sent;
 r := pg_temp.yes('a','b');
 assert not exists(select 1 from pg_temp.sent), 'a repeat sends nothing';
 perform pg_temp.as_user('a');
 assert pg_temp.fails('select public.company_yes('''||current_setting('test.p1')||''','''||current_setting('test.d')||''')') = 'BLOCKED',
  'blocked pair';
 perform pg_temp.as_user('g');
 assert pg_temp.fails('select public.company_yes('''||current_setting('test.p1')||''','''||current_setting('test.b')||''')') = 'NOT_IN_COMPANY',
  'g has no intent';
end $$;
select pg_temp.as_user('b');
set local role authenticated;
do $$ begin
 assert (select they_said_yes from public.company_people(current_setting('test.p1')::uuid) where user_id = current_setting('test.a')::uuid),
  'b sees that a wants to go together';
 assert (select user_id from public.company_people(current_setting('test.p1')::uuid) limit 1) = current_setting('test.a')::uuid,
  'and a goes first';
end $$;
reset role;

-- ── b → a: збіг. Супутник збирає a (намір раніше), b — підтверджений, зустріч за 30 хв, пуш обом, без «приєднався».
do $$ declare r jsonb; v jsonb; c public.events; begin
 r := pg_temp.yes('b','a');
 assert (r->>'matched')::boolean and r ? 'companion_id', 'b → a is a match: '||r::text;
 perform set_config('test.comp', r->>'companion_id', true);
 select * into c from public.events where id = (r->>'companion_id')::uuid;
 assert c.organizer_id = current_setting('test.a')::uuid and c.companion_of = current_setting('test.p1')::uuid and c.capacity = 4
  and c.approval_required and c.min_age = 18, 'a organizes the companion';
 assert c.starts_at = (select starts_at from public.events where id = current_setting('test.p1')::uuid) - interval '30 minutes', 'meet 30 min before';
 assert exists(select 1 from public.event_members where event_id = c.id and user_id = current_setting('test.b')::uuid and status = 'approved'),
  'b is approved';
 assert not exists(select 1 from pg_temp.sent where payload->>'type' in ('joined','request')), 'no «joined» push';
 select payload into v from pg_temp.sent where payload->>'type' = 'company';
 assert v->>'event_id' = c.id::text and v->>'body' = 'Ви йдете разом — чат відкрито'
  and v->'user_ids' = jsonb_build_array(current_setting('test.b'), current_setting('test.a')), 'both are told: '||v::text;
end $$;
delete from pg_temp.sent;

-- ── c бачить a і b у компанії; c ↔ a — c іде в той самий супутник.
select pg_temp.as_user('c');
set local role authenticated;
do $$ begin
 assert (select bool_and(companion_id = current_setting('test.comp')::uuid) from public.company_people(current_setting('test.p1')::uuid)
  where user_id in (current_setting('test.a')::uuid, current_setting('test.b')::uuid)), 'c sees the companion of a and b';
end $$;
reset role;
do $$ declare r jsonb; begin
 r := pg_temp.yes('c','a');
 assert r = '{"matched": false}'::jsonb, 'c → a';
 r := pg_temp.yes('a','c');
 assert (r->>'companion_id') = current_setting('test.comp'), 'a ↔ c lands in the same companion';
 assert (select count(*) from public.event_members where event_id = current_setting('test.comp')::uuid and status = 'approved') = 2, 'b and c';
end $$;

-- ── Видача: 12-та позиція — скільки хочуть піти.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ declare idx jsonb; begin
 select (public.discover_events(-41,-31,-40,-30,null,null,null,null,false,5000,24))->'index' into idx;
 assert (select e->>11 from jsonb_array_elements(idx) e where e->>0 = current_setting('test.p1')) = '4', 'index carries the count: '||idx::text;
 assert (select e->>11 from jsonb_array_elements(idx) e where e->>0 = current_setting('test.comp')) = '0', 'a companion carries zero';
end $$;
reset role;

-- ── Зняття: c більше не шукає — його «Піти разом» зникає, тизер a бачить лише b.
do $$ begin
 perform pg_temp.intent('c','p1',false);
 assert not exists(select 1 from private.company_yes where from_id = current_setting('test.c')::uuid), 'c''s yeses are gone';
 assert not exists(select 1 from private.company_intents where user_id = current_setting('test.c')::uuid), 'and the intent';
end $$;
select pg_temp.as_user('a');
set local role authenticated;
do $$ begin
 assert (select count from public.company_teaser(current_setting('test.p1')::uuid)) = 1, 'a sees only b now';
end $$;
reset role;

select 'PASS: company_intents' as result;
rollback;

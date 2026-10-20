-- Запускати адміністратором бази. Усе відкочується. Канал повернення (docs/guest-channel.md): межі вікон 28/35 і
-- 56/63 днів, після кроку 2 — тиша, повернення скидає драбину, контрольна група стабільна й близька до 20%, менше
-- 3 подій — крок не зараховано, година й день за Києвом, чистка за 120 днів, перевірки `touch_device`, стеля
-- рядків, `forget_device`.
begin;

-- Ізоляція: пристрої на базі можуть бути справжні, а прогін бере всіх. Міста подій вигадані — справжня афіша
-- в підрахунок не потрапляє.
delete from private.devices;
create temp table sent(payload jsonb) on commit drop;
create or replace function private.notify_push(p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into pg_temp.sent values (p_payload);
$$;
insert into public.event_sources(slug,name,kind,base_url) values ('test_winback','Test','manual','https://example.invalid');

-- Наступна пʼятниця, 17:30 за Києвом: завжди попереду, тож події її вихідних живі для `is_listed`.
create temp table clock on commit drop as
 select (date_trunc('week', now() at time zone 'Europe/Kyiv') + interval '11 days 17 hours 30 minutes') at time zone 'Europe/Kyiv' as fri;
create function pg_temp.fri() returns timestamptz language sql as $$ select fri from pg_temp.clock $$;
-- Час від пʼятниці за Києвом: '1 day 12:00' — субота, полудень.
create function pg_temp.at(p interval) returns timestamptz language sql as $$
 select ((pg_temp.fri() at time zone 'Europe/Kyiv')::date + p) at time zone 'Europe/Kyiv'
$$;

create function pg_temp.ev(p_city text, p_title text, p_category text, p_at interval) returns void language sql as $$
 insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
  origin,source_id,source_uid,import_status,quality)
 values (gen_random_uuid(),p_title,'',p_category,p_city,'Buoy',-41.1,-31.1,pg_temp.at(p_at),pg_temp.at(p_at)+interval '2 hours',
  'Europe/Kyiv','import',(select id from public.event_sources where slug='test_winback'),gen_random_uuid()::text,'live',0.9)
$$;
-- Ocean: 4 події на вихідних (джаз двома сеансами — одна), плюс пʼятниця й понеділок, що не рахуються.
select pg_temp.ev('Ocean','Виставка','art',interval '1 day 10:00');
select pg_temp.ev('Ocean','Джаз','music',interval '1 day 12:00');
select pg_temp.ev('Ocean','Стендап','comedy',interval '1 day 19:00');
select pg_temp.ev('Ocean','Джаз','music',interval '2 days 12:00');
select pg_temp.ev('Ocean','Футбол','sport',interval '2 days 15:00');
select pg_temp.ev('Ocean','Пʼятничний концерт','music',interval '20:00');
select pg_temp.ev('Ocean','Понеділок','music',interval '3 days 10:00');
-- Pond: лише дві.
select pg_temp.ev('Pond','Раз','music',interval '1 day 12:00');
select pg_temp.ev('Pond','Два','music',interval '2 days 12:00');

-- Токен із наперед відомою групою: перебираємо, поки хеш не скаже потрібне.
create function pg_temp.tok(p_seed text, p_holdout boolean) returns text language plpgsql as $$
declare i integer := 0; v text;
begin
 loop
  v := md5(p_seed || i) || md5(p_seed);
  exit when (abs(hashtext(v)::bigint) % 5 = 0) = p_holdout;
  i := i + 1;
 end loop;
 return v;
end $$;
create temp table names(name text primary key, token text) on commit drop;
create function pg_temp.dev(p_name text, p_city text, p_age interval, p_interests text[] default '{}', p_holdout boolean default false)
returns void language plpgsql as $$
declare v text := pg_temp.tok(p_name, p_holdout);
begin
 insert into pg_temp.names values (p_name, v);
 insert into private.devices(token,platform,city,interests,last_seen) values (v,'ios',p_city,p_interests,pg_temp.fri()-p_age);
end $$;
create function pg_temp.t(p_name text) returns text language sql as $$ select token from pg_temp.names where name = p_name $$;
create function pg_temp.due_step(p_name text, p_at timestamptz) returns smallint language sql as $$
 select step from private.winback_due(p_at) where token = pg_temp.t(p_name)
$$;

select pg_temp.dev('d27', 'Ocean', interval '27 days 23 hours');
select pg_temp.dev('d28', 'Ocean', interval '28 days', '{comedy}');
select pg_temp.dev('d34', 'Ocean', interval '34 days 23 hours');
select pg_temp.dev('d35', 'Ocean', interval '35 days');
select pg_temp.dev('d55', 'Ocean', interval '55 days 23 hours');
select pg_temp.dev('d56', 'Ocean', interval '56 days');
select pg_temp.dev('d62', 'Ocean', interval '62 days 23 hours');
select pg_temp.dev('d63', 'Ocean', interval '63 days');
select pg_temp.dev('d90', 'Ocean', interval '90 days');
select pg_temp.dev('hold', 'Ocean', interval '30 days', '{}', true);
select pg_temp.dev('pond', 'Pond', interval '30 days');
select pg_temp.dev('nocity', null, interval '30 days');
select pg_temp.dev('d119', 'Ocean', interval '119 days');
select pg_temp.dev('d121', 'Ocean', interval '121 days');

-- Вікна.
do $$ begin
 assert pg_temp.due_step('d27', pg_temp.fri()) is null, '27 днів 23 години — ще рано';
 assert pg_temp.due_step('d28', pg_temp.fri()) = 1, '28 днів — крок 1';
 assert pg_temp.due_step('d34', pg_temp.fri()) = 1, '34 дні 23 години — ще крок 1';
 assert pg_temp.due_step('d35', pg_temp.fri()) is null, '35 днів — вікно кроку 1 минуло';
 assert pg_temp.due_step('d55', pg_temp.fri()) is null, '55 днів — між кроками';
 assert pg_temp.due_step('d56', pg_temp.fri()) = 2, '56 днів — крок 2';
 assert pg_temp.due_step('d62', pg_temp.fri()) = 2, '62 дні 23 години — ще крок 2';
 assert pg_temp.due_step('d63', pg_temp.fri()) is null, '63 дні — після кроку 2 тиша';
 assert pg_temp.due_step('d90', pg_temp.fri()) is null, '90 днів — тиша';
end $$;

-- Не пʼятниця 17-та за Києвом — нічого, і крок не зараховано.
do $$ begin
 assert private.send_winbacks(pg_temp.fri() - interval '1 hour') = 0, '16:30 — рано';
 assert private.send_winbacks(pg_temp.fri() + interval '1 hour') = 0, '18:30 — пізно';
 assert private.send_winbacks(pg_temp.fri() - interval '1 day') = 0, 'четвер 17:30 — не той день';
 assert not exists (select 1 from private.winback_sends), 'поза годиною нічого не записано';
 assert not exists (select 1 from pg_temp.sent), 'і не надіслано';
 assert exists (select 1 from private.devices where token = pg_temp.t('d119')), '119 днів — ще живий';
 assert not exists (select 1 from private.devices where token = pg_temp.t('d121')), 'старше 120 днів — видалено й поза годиною';
end $$;

-- Пʼятниця 17:30.
do $$
declare v_sent integer := private.send_winbacks(pg_temp.fri()); p jsonb;
begin
 assert v_sent = 4, format('надіслано 4 (d28, d34, d56, d62), а не %s', v_sent);
 assert (select count(*) from pg_temp.sent) = 4, 'чотири виклики push';
 assert (select count(*) from private.winback_sends where not holdout) = 4, 'чотири кроки зараховано';
 assert (select holdout from private.winback_sends where token = pg_temp.t('hold') and step = 1), 'контрольна група — у журналі';
 assert not exists (select 1 from pg_temp.sent where payload->>'token' = pg_temp.t('hold')), 'контрольній — без пушу';
 assert not exists (select 1 from private.winback_sends where token = pg_temp.t('pond')), 'менше 3 подій — крок не зараховано';
 assert not exists (select 1 from private.winback_sends where token = pg_temp.t('nocity')), 'без міста — нічого';
 select payload into p from pg_temp.sent where payload->>'token' = pg_temp.t('d28');
 assert p->>'type' = 'winback' and p->>'platform' = 'ios' and (p->>'step')::int = 1 and p->>'city' = 'Ocean', format('пейлоад: %s', p);
 assert (p->>'total')::int = 4, format('4 події: прокат один, пʼятниця й понеділок не рахуються, а не %s', p->>'total');
 assert p->'titles' = '["Стендап","Виставка"]'::jsonb, format('спершу інтерес, далі за часом: %s', p->'titles');
 assert (select payload->'titles' from pg_temp.sent where payload->>'token' = pg_temp.t('d34')) = '["Виставка","Джаз"]'::jsonb, 'без інтересів — за часом';
 assert (select (payload->>'step')::int from pg_temp.sent where payload->>'token' = pg_temp.t('d56')) = 2, 'крок 2';
 assert private.send_winbacks(pg_temp.fri() + interval '20 minutes') = 0, 'другий прогін тієї ж години нічого не повторює';
 assert (select count(*) from pg_temp.sent) = 4, 'пушів так само чотири';
end $$;

-- Тиждень потому: d28 і d34 уже за вікном кроку 1, d56 і d62 — за вікном кроку 2.
do $$ begin
 assert not exists (select 1 from private.winback_due(pg_temp.fri() + interval '7 days')
  where token in (pg_temp.t('d28'), pg_temp.t('d34'), pg_temp.t('d56'), pg_temp.t('d62'))), 'через тиждень нікому з них';
 assert pg_temp.due_step('d28', pg_temp.fri() + interval '28 days') = 2, 'd28 через 4 тижні — крок 2';
end $$;

-- Крок 2 надіслано — більше нічого: ні через тиждень, ні пізніше.
insert into private.winback_sends(token, step, holdout, sent_at) values (pg_temp.t('d28'), 2, false, pg_temp.fri() + interval '28 days');
do $$ begin
 assert pg_temp.due_step('d28', pg_temp.fri() + interval '28 days') is null, 'крок 2 уже був';
 assert pg_temp.due_step('d28', pg_temp.fri() + interval '35 days') is null, 'після кроку 2 тиша';
end $$;

-- Повернення скидає драбину: новий `last_seen` пізніший за всі надіслані кроки.
update private.devices set last_seen = pg_temp.fri() + interval '29 days' where token = pg_temp.t('d28');
do $$ begin
 assert pg_temp.due_step('d28', pg_temp.fri() + interval '57 days') = 1, 'повернувся й знову заснув — знову крок 1';
end $$;

-- Контрольна група: той самий токен — та сама група, на 1 000 токенах — близько 20%.
do $$
declare v_share numeric;
begin
 insert into private.devices(token, platform, last_seen) select md5('holdout' || i) || md5(i::text), 'ios', pg_temp.fri() - interval '30 days'
  from generate_series(1, 1000) i;
 select avg(holdout::int) into v_share from private.winback_due(pg_temp.fri()) where token not in (select token from pg_temp.names);
 assert v_share between 0.16 and 0.24, format('частка контрольної групи %s', v_share);
 assert not exists (select 1 from private.winback_due(pg_temp.fri()) a join private.winback_due(pg_temp.fri() + interval '1 day') b using (token)
  where a.holdout <> b.holdout), 'той самий токен — та сама група в іншому прогоні';
 assert (select count(*) from private.winback_due(pg_temp.fri() + interval '1 day') where token not in (select token from pg_temp.names)) = 1000,
  'наступного дня ті самі 1 000 ще у вікні';
end $$;
delete from private.devices where token not in (select token from pg_temp.names);

-- `touch_device`: формат, місто, інтереси; лише публічним ключем, як кличе застосунок.
create function pg_temp.rejected(p_token text, p_platform text, p_city text, p_interests text[]) returns text language plpgsql as $$
begin
 perform public.touch_device(p_token, p_platform, p_city, p_interests);
 return null;
exception when sqlstate '22023' then return sqlerrm;
end $$;
grant execute on function pg_temp.rejected(text,text,text,text[]) to anon;
set local role anon;
do $$
declare ios text := repeat('ab', 32); fcm text := repeat('A1_:-', 30);
begin
 assert pg_temp.rejected(left(ios, 63), 'ios', null, '{}') = 'INVALID_TOKEN', 'APNs: 63 символи';
 assert pg_temp.rejected(upper(ios), 'ios', null, '{}') = 'INVALID_TOKEN', 'APNs: великі літери';
 assert pg_temp.rejected(left(fcm, 99), 'android', null, '{}') = 'INVALID_TOKEN', 'FCM: коротший за 100';
 assert pg_temp.rejected(fcm || '/x', 'android', null, '{}') = 'INVALID_TOKEN', 'FCM: зайвий символ';
 assert pg_temp.rejected(repeat('a', 4097), 'android', null, '{}') = 'INVALID_TOKEN', 'FCM: довший за 4096';
 assert pg_temp.rejected(ios, 'web', null, '{}') = 'INVALID_PLATFORM', 'платформа';
 assert pg_temp.rejected(ios, 'ios', 'Ocean', '{}') = 'INVALID_CITY', 'місто не з пʼяти';
 assert pg_temp.rejected(ios, 'ios', 'Київ', '{jazz}') = 'INVALID_INTERESTS', 'невідомий інтерес';
 assert pg_temp.rejected(ios, 'ios', 'Київ', array['music', null]) = 'INVALID_INTERESTS', 'null серед інтересів';
 assert pg_temp.rejected(ios, 'ios', 'Київ', array['music','sport','art','food','games','outdoors','social','comedy','kids','tours','conference','music'])
  = 'INVALID_INTERESTS', 'більше 11';
 assert pg_temp.rejected(ios, 'ios', 'Київ', '{music,comedy}') is null, 'APNs з Києвом приймається';
 assert pg_temp.rejected(fcm, 'android', null, null) is null, 'FCM без міста й інтересів приймається';
end $$;
reset role;
do $$ begin
 assert (select city = 'Київ' and interests = '{music,comedy}' and last_seen = now() from private.devices where token = repeat('ab', 32)), 'APNs записано';
 assert (select interests = '{}' and city is null from private.devices where token = repeat('A1_:-', 30)), 'FCM записано';
 assert not has_table_privilege('anon', 'private.devices', 'select'), 'таблицю публічний ключ не бачить';
end $$;
update private.devices set last_seen = now() - interval '40 days' where token = repeat('ab', 32);
select public.touch_device(repeat('ab', 32), 'ios', 'Львів', '{art}');
do $$ begin
 assert (select city = 'Львів' and interests = '{art}' and last_seen = now() from private.devices where token = repeat('ab', 32)), 'повторний виклик оновлює';
end $$;

-- `forget_device` видаляє пристрій разом з його кроками.
select public.forget_device(pg_temp.t('d56'));
do $$ begin
 assert not exists (select 1 from private.devices where token = pg_temp.t('d56')), 'пристрій видалено';
 assert not exists (select 1 from private.winback_sends where token = pg_temp.t('d56')), 'кроки теж';
end $$;

-- Стеля: на 100 000 новий пристрій не пишемо, наявний оновлюємо.
insert into private.devices(token, platform) select 'ceiling' || i, 'android' from generate_series(1, 100000 - (select count(*) from private.devices)) i;
select public.touch_device(repeat('cd', 32), 'ios', null, '{}');
update private.devices set last_seen = now() - interval '1 day' where token = repeat('ab', 32);
select public.touch_device(repeat('ab', 32), 'ios', null, '{}');
do $$ begin
 assert not exists (select 1 from private.devices where token = repeat('cd', 32)), 'вище стелі новий не записано';
 assert (select last_seen = now() from private.devices where token = repeat('ab', 32)), 'наявний оновлено';
end $$;

select 'PASS: winback' as result;
rollback;

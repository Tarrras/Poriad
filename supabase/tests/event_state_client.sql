-- Запускати адміністратором бази. Усе відкочується. Стан події й продавці — клієнтам (docs/event-offers.md, фаза 4:
-- R8, R10, R11): поля 1.3.0 ті самі, стан береться з event_state лише за перемикачем фази 3 і на тому ж часі, перенос —
-- лише застосований, знята без стану — «не знайшли», продавці основним першим і без вимкненого джерела, у спільнотної —
-- нічого. Потребує міграцій 20261027120000 (перемикач) і 20261028120000.
begin;

create or replace function private.notify_push(p_payload jsonb) returns void language plpgsql security definer
 set search_path='' as $$ begin end $$;

select set_config('test.host',gen_random_uuid()::text,true),set_config('test.run',gen_random_uuid()::text,true),
 set_config('test.room',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values (current_setting('test.host')::uuid,
 'poruch-client-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','H','birth_date','1990-01-01'));
insert into public.event_sources(slug,name,kind,base_url,weight,enabled) values
 ('test_client_a','Продавець А','manual','https://example.invalid',0.8,true),
 ('test_client_b','Продавець Б','manual','https://example.invalid',0.7,true),
 ('test_client_off','Вимкнений','manual','https://example.invalid',0.9,true);
select set_config('test.t',(date_trunc('minute',now())+interval '10 days')::text,true);

create function pg_temp.w(p_slug text, p_uid text, p_title text, p_price numeric) returns jsonb language sql as $$
 select jsonb_build_object('id',gen_random_uuid(),'slug',p_slug,'uid',p_uid,'url','https://example.invalid/'||p_uid,
  'title',p_title,'description','','category','music','city','Ocean','address','Buoy, 1','lat',-40.5,'lon',-30.5,
  'starts',current_setting('test.t')::timestamptz,'ends',current_setting('test.t')::timestamptz+interval '2 hours',
  'tz','Europe/Kyiv','dedupe','x','quality',0.9,'price',p_price) $$;
create function pg_temp.c(p_slug text, p_uid text, p_title text, p_price numeric, p_wuid text) returns jsonb language sql as $$
 select jsonb_build_object('slug',p_slug,'uid',p_uid,'url','https://example.invalid/'||p_uid,'title',p_title,
  'starts',current_setting('test.t')::timestamptz,'price',p_price,'winner_slug','test_client_a','winner_uid',p_wuid,
  'linked','rule') $$;
create function pg_temp.ingest(p_rows jsonb) returns integer language sql as $$
 select private.ingest_offers(current_setting('test.run')::uuid, p_rows) $$;
create function pg_temp.ev(p_uid text) returns uuid language sql as $$
 select o.event_id from public.event_offers o join public.event_sources s on s.id=o.source_id
 where s.slug like 'test_client_%' and o.source_uid=p_uid $$;
create function pg_temp.d(p_uid text) returns public.event_result language sql as $$
 select * from public.event_details(pg_temp.ev(p_uid)) $$;
create function pg_temp.card(p_uid text) returns jsonb language sql as $$
 select private.event_cards(array[pg_temp.ev(p_uid)])->0 $$;
create function pg_temp.state(p_uid text, p_state text, p_shift interval default '0', p_prev interval default null)
returns void language sql as $$
 insert into private.event_state(event_id,state,starts_at,previous_starts_at,checked_at)
 values (pg_temp.ev(p_uid), p_state, current_setting('test.t')::timestamptz + p_shift,
  current_setting('test.t')::timestamptz + p_prev, now())
 on conflict (event_id) do update set state=excluded.state, starts_at=excluded.starts_at,
  previous_starts_at=excluded.previous_starts_at, checked_at=excluded.checked_at $$;

-- Подія з трьома продавцями: А основний (300), Б дешевший (250), вимкнене джерело — найважче.
select pg_temp.ingest(jsonb_build_array(pg_temp.w('test_client_a','c1a','Концерт Клієнт',300)));
select pg_temp.ingest(jsonb_build_array(pg_temp.c('test_client_b','c1b','Концерт Клієнт',250,'c1a'),
 pg_temp.c('test_client_off','c1o','Концерт Клієнт',200,'c1a')));
update public.event_sources set enabled=false where slug='test_client_off';

-- ── 1. Без стану: «в силі», продавці основним першим, поля 1.3.0 як були.
do $$ declare d public.event_result := pg_temp.d('c1a'); begin
 assert pg_temp.ev('c1a') = pg_temp.ev('c1b') and pg_temp.ev('c1a') = pg_temp.ev('c1o'), 'one event, three sellers';
 assert d.state = 'scheduled' and d.previous_starts_at is null and d.checked_at is null, 'scheduled without a check';
 assert d.canonical_url = 'https://example.invalid/c1a' and d.source_name = 'Продавець А' and d.import_status = 'live',
  '1.3.0 fields: primary seller';
 assert jsonb_array_length(d.offers) = 2, 'disabled source not shown';
 assert d.offers->0->>'source' = 'Продавець А' and (d.offers->0->>'price_min')::numeric = 300
  and (d.offers->0->>'live')::boolean, 'primary first with its price';
 assert d.offers->1->>'source' = 'Продавець Б' and d.offers->1->>'url' = 'https://example.invalid/c1b', 'second seller';
 assert pg_temp.card('c1a')->>'state' = 'scheduled' and jsonb_array_length(pg_temp.card('c1a')->'offers') = 2,
  'cards carry the same';
end $$;

-- ── 2. Скасовано на тому ж часі. Перемикач фази 3 вимкнено — клієнт стану тіні не бачить.
select pg_temp.state('c1a','cancelled');
update private.flags set enabled = false where name = 'event_changes';
do $$ declare d public.event_result := pg_temp.d('c1a'); begin
 assert d.state = 'scheduled' and d.checked_at is null, 'flag off: shadow state stays hidden';
 assert pg_temp.card('c1a')->>'state' = 'scheduled' and not (pg_temp.card('c1a') ? 'checked_at'), 'card too';
end $$;
-- Увімкнено (лише прапорець, без перерахунку import_status: тут перевіряємо клієнтські поля).
update private.flags set enabled = true where name = 'event_changes';
do $$ declare d public.event_result := pg_temp.d('c1a'); begin
 assert d.state = 'cancelled' and d.checked_at is not null and d.import_status = 'live', 'cancelled, checked';
 assert pg_temp.card('c1a')->>'state' = 'cancelled' and pg_temp.card('c1a') ? 'checked_at', 'card too';
end $$;

-- ── 3. Перенос у тіні (час стану ≠ час рядка) — про цей рядок нічого не каже.
select pg_temp.state('c1a','scheduled','1 day','0');
do $$ declare d public.event_result := pg_temp.d('c1a'); begin
 assert d.state = 'scheduled' and d.previous_starts_at is null, 'unapplied move is invisible';
end $$;
update public.events set import_status='withdrawn' where id=pg_temp.ev('c1a');
do $$ begin assert (pg_temp.d('c1a')).state = 'unknown', 'unapplied move on a withdrawn row: not found on sale'; end $$;
update public.events set import_status='live' where id=pg_temp.ev('c1a');

-- ── 4. Застосований перенос: стара дата віддається.
select pg_temp.state('c1a','scheduled','0','-1 day');
do $$ declare d public.event_result := pg_temp.d('c1a'); begin
 assert d.state = 'scheduled' and d.previous_starts_at = current_setting('test.t')::timestamptz - interval '1 day',
  'moved: previous date';
 assert (pg_temp.card('c1a')->>'previous_starts_at')::timestamptz = d.previous_starts_at, 'card too';
end $$;

-- ── 5. Знята без стану — «не знайшли в продажу»; зняті продавці лишаються для «Якщо купили квиток».
delete from private.event_state where event_id=pg_temp.ev('c1a');
update public.event_offers set status='withdrawn' where event_id=pg_temp.ev('c1a');
update public.events set import_status='withdrawn' where id=pg_temp.ev('c1a');
do $$ declare d public.event_result := pg_temp.d('c1a'); begin
 assert d.state = 'unknown', 'withdrawn without state: unknown';
 assert jsonb_array_length(d.offers) = 2 and not (d.offers->0->>'live')::boolean, 'withdrawn sellers still listed';
end $$;

-- ── 6. Спільнотна подія: ні стану, ні продавців.
insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
values(current_setting('test.room')::uuid,current_setting('test.host')::uuid,'Кімната','Опис кімнати для тесту стану','social','Ocean','Buoy, 1',-40.5,-30.5,
 now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10);
do $$ declare d public.event_result; c jsonb; begin
 select * into d from public.event_details(current_setting('test.room')::uuid);
 assert d.state is null and d.offers is null and d.checked_at is null, 'community: nothing';
 c := private.event_cards(array[current_setting('test.room')::uuid])->0;
 assert not (c ? 'state') and not (c ? 'offers'), 'community card: nothing';
end $$;

select 'PASS' as event_state_client;
rollback;

-- Запускати адміністратором бази. Усе відкочується. Тихі години: межі вікна за Києвом (і після переходу на
-- зимовий час), пуш «Стежити» вночі йде в чергу, транзакційний — одразу, ранковий прогін чергу відправляє, нічний — ні.
begin;

do $$ begin
 assert not private.quiet_hours('2026-10-20 21:59:59+03'), '21:59 — ще день';
 assert private.quiet_hours('2026-10-20 22:00:00+03'), '22:00 — тихо';
 assert private.quiet_hours('2026-10-21 08:59:59+03'), '08:59 — ще тихо';
 assert not private.quiet_hours('2026-10-21 09:00:00+03'), '09:00 — день';
 assert private.quiet_hours('2026-11-02 21:30:00+00'), 'зимовий час: 23:30 за Києвом — тихо';
 assert not private.quiet_hours('2026-11-02 07:30:00+00'), 'зимовий час: 09:30 за Києвом — день';
end $$;

-- Адреса функції підроблена, а виклики pg_net лишаються в його черзі транзакції й відкотяться разом з нею.
create or replace function private.push_endpoint(out url text, out secret text) language sql as $$ select 'https://example.invalid'::text, 'x'::text $$;
delete from private.deferred_pushes;
create temp table net_before on commit drop as select count(*) n from net.http_request_queue;

-- Ніч.
create or replace function private.quiet_hours(p_at timestamptz default now()) returns boolean language sql as $$ select true $$;
select private.notify_push(jsonb_build_object('type','follow','kind','organizer','event_id',gen_random_uuid()));
select private.notify_push(jsonb_build_object('type','message','message_id',gen_random_uuid(),'event_id',gen_random_uuid()));
select private.notify_push(jsonb_build_object('type','event','kind','cancelled','event_id',gen_random_uuid()));
do $$ begin
 assert (select count(*)=1 from private.deferred_pushes where payload->>'kind'='organizer'), 'follow вночі — у черзі';
 assert (select count(*) from net.http_request_queue) = (select n+2 from net_before), 'чат і скасування — одразу';
 assert private.flush_deferred_pushes() = 0, 'вночі черга стоїть';
 assert (select count(*)=1 from private.deferred_pushes), 'черга ціла';
end $$;

-- Ранок.
create or replace function private.quiet_hours(p_at timestamptz default now()) returns boolean language sql as $$ select false $$;
do $$ begin
 assert private.flush_deferred_pushes() = 1, 'вранці черга йде';
 assert not exists (select 1 from private.deferred_pushes), 'черга порожня';
 assert (select count(*) from net.http_request_queue) = (select n+3 from net_before), 'нічний follow пішов у функцію';
end $$;

select 'PASS: quiet_hours' as result;
rollback;

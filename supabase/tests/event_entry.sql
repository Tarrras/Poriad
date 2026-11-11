-- Запускати адміністратором бази. Усе відкочується. Спосіб входу на подію (20261129120000): «Квитки за посиланням» і
-- «Вільний вхід» — оголошення для клієнта (origin = 'partner'), без місць і без запису; «Шукаю компанію» на них є;
-- спосіб не міняється, коли вже є люди. Чужих рядків не чіпає.
begin;

select set_config('test.u1',gen_random_uuid()::text,true),set_config('test.u2',gen_random_uuid()::text,true),
 set_config('test.tickets',gen_random_uuid()::text,true),set_config('test.open',gen_random_uuid()::text,true),
 set_config('test.room',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-entry-'||id||'@example.invalid',jsonb_build_object('display_name','Кафе Entry','birth_date','1990-01-01')
from unnest(array[current_setting('test.u1'),current_setting('test.u2')]) id;

create function pg_temp.make(p_name text, p_entry text, p_url text default null, p_price integer default null, p_capacity integer default 50)
returns uuid language sql as $$
 select public.create_event(p_id => current_setting('test.'||p_name)::uuid, p_title => 'Вечір Entry '||p_name, p_description => 'Test description',
  p_category => 'music', p_city => 'Ocean', p_address => 'Buoy, 11', p_latitude => -45.1, p_longitude => -35.1,
  p_starts_at => now()+interval '1 day', p_ends_at => now()+interval '1 day 2 hours', p_time_zone => 'UTC', p_capacity => p_capacity,
  p_approval_required => true, p_contact_url => 'https://t.me/entrytest', p_via => 'web', p_price => p_price, p_prepay => true,
  p_entry => p_entry, p_ticket_url => p_url);
$$;
create function pg_temp.row_of(p_name text) returns public.events language sql as $$
 select e from public.events e where e.id = current_setting('test.'||p_name)::uuid $$;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$ begin
 begin perform pg_temp.make('tickets','tickets'); raise exception 'tickets without a link';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_TICKET_URL'; end;
 begin perform pg_temp.make('tickets','tickets','http://example.invalid/t'); raise exception 'http link';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_TICKET_URL'; end;
 begin perform pg_temp.make('tickets','tickets','https://example.invalid/t <b>'); raise exception 'a link with a space';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_TICKET_URL'; end;
 begin perform pg_temp.make('tickets','tickets','https://x'); raise exception 'a link too short';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_TICKET_URL'; end;
 begin perform pg_temp.make('tickets','tickets','https://example.invalid/'||repeat('a',500)); raise exception 'a link too long';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_TICKET_URL'; end;
 begin perform pg_temp.make('open','door'); raise exception 'unknown entry';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_ENTRY'; end;
 begin perform pg_temp.make('room','signup',null,null,null); raise exception 'a room without capacity';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_CAPACITY'; end;
 perform pg_temp.make('tickets','tickets',' https://example.invalid/tickets?id=1 ',300);
 perform pg_temp.make('open','open',null,null,null);
 perform pg_temp.make('room',null);
end $$;
reset role;
do $$
declare t public.events := pg_temp.row_of('tickets'); o public.events := pg_temp.row_of('open'); r public.events := pg_temp.row_of('room');
begin
 assert t.entry = 'tickets' and t.capacity is null and t.canonical_url = 'https://example.invalid/tickets?id=1' and t.price_min = 300 and t.is_free is null,'tickets row';
 assert not t.approval_required and t.contact_url is null and not t.prepay and t.origin = 'community' and t.organizer_id = current_setting('test.u1')::uuid,'no room extras, still the organizer''s event';
 assert o.entry = 'open' and o.capacity is null and o.canonical_url is null and o.is_free,'open row: free entry';
 assert r.entry = 'signup' and r.capacity = 50 and r.approval_required and r.contact_url is not null,'a room as before';
end $$;

-- Клієнт: гість бачить оголошення з кнопкою «Квитки», а не кімнату; записатись не можна.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$
declare d public.event_result; c jsonb;
begin
 select * into d from public.event_details(current_setting('test.tickets')::uuid);
 assert d.origin = 'partner' and d.canonical_url = 'https://example.invalid/tickets?id=1' and d.capacity is null and d.organizer_id = current_setting('test.u1')::uuid,'details: a listing that still names its organizer';
 select * into d from public.event_details(current_setting('test.room')::uuid);
 assert d.origin = 'community' and d.capacity = 50,'a room stays a room';
 c := public.event_cards_by_ids(array[current_setting('test.tickets'),current_setting('test.open'),current_setting('test.room')]::uuid[]);
 assert (select jsonb_object_agg(x->>'id', x->>'origin') from jsonb_array_elements(c) x)
  = jsonb_build_object(current_setting('test.tickets'),'partner',current_setting('test.open'),'partner',current_setting('test.room'),'community'),'cards';
 assert (select (x->>'is_free')::boolean from jsonb_array_elements(c) x where x->>'id' = current_setting('test.open')),'the open card is free';
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u2'),true);
do $$ begin
 begin perform public.join_event(current_setting('test.tickets')::uuid); raise exception 'joined a ticketed event';
 exception when sqlstate 'P0001' then assert sqlerrm='IMPORTED_EVENT'; end;
 begin perform public.join_event(current_setting('test.open')::uuid); raise exception 'joined an open event';
 exception when sqlstate 'P0001' then assert sqlerrm='IMPORTED_EVENT'; end;
 perform public.join_event(current_setting('test.room')::uuid);
 -- «Шукаю компанію» — на подію без запису так, на кімнату ні.
 perform set_config('test.comp', public.create_companion(current_setting('test.open')::uuid, now()+interval '23 hours 30 minutes', null, 4)::text, true);
 begin perform public.create_companion(current_setting('test.room')::uuid, now()+interval '23 hours 30 minutes', null, 4); raise exception 'a companion to a room';
 exception when sqlstate 'P0001' then assert sqlerrm='COMPANION_UNAVAILABLE'; end;
end $$;
reset role;
do $$ begin
 assert (select entry = 'signup' and capacity = 4 and companion_of = current_setting('test.open')::uuid from public.events where id = current_setting('test.comp')::uuid),'the companion is a room';
 assert private.company_event_ok(current_setting('test.tickets')::uuid) and not private.company_event_ok(current_setting('test.room')::uuid),'company intents: listings only';
end $$;

-- Правка: старий клієнт (p_entry = null) способу не чіпає; з людьми спосіб не міняється; без людей — міняється.
create function pg_temp.edit(p_name text, p_entry text, p_url text default null, p_capacity integer default 20)
returns uuid language sql as $$
 select public.update_event(p_id => current_setting('test.'||p_name)::uuid, p_title => 'Вечір Entry '||p_name, p_description => 'Test description',
  p_category => 'music', p_city => 'Ocean', p_address => 'Buoy, 11', p_latitude => -45.1, p_longitude => -35.1,
  p_starts_at => now()+interval '1 day', p_ends_at => now()+interval '1 day 2 hours', p_time_zone => 'UTC', p_capacity => p_capacity,
  p_entry => p_entry, p_ticket_url => p_url);
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$ begin
 perform pg_temp.edit('tickets',null);
 begin perform pg_temp.edit('room','open'); raise exception 'dropped a room with a member';
 exception when sqlstate 'P0001' then assert sqlerrm='ENTRY_LOCKED'; end;
 begin perform pg_temp.edit('open','signup'); raise exception 'made a room under a companion';
 exception when sqlstate 'P0001' then assert sqlerrm='ENTRY_LOCKED'; end;
 perform pg_temp.edit('room',null,null,30);
end $$;
reset role;
do $$
declare t public.events := pg_temp.row_of('tickets');
begin
 assert t.entry = 'tickets' and t.capacity is null and t.canonical_url = 'https://example.invalid/tickets?id=1','an old client keeps the entry and the link';
 assert (pg_temp.row_of('room')).capacity = 30 and (pg_temp.row_of('room')).entry = 'signup';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$ begin perform pg_temp.edit('tickets','tickets','https://example.invalid/new'); end $$;
reset role;
do $$ begin assert (pg_temp.row_of('tickets')).canonical_url = 'https://example.invalid/new','a new link'; end $$;
set local role authenticated;
do $$ begin perform pg_temp.edit('tickets','open'); end $$;
reset role;
do $$ begin
 assert (select entry = 'open' and canonical_url is null and is_free = false from public.events where id = current_setting('test.tickets')::uuid),'open with a price: not free, no link';
end $$;
set local role authenticated;
do $$ begin
 perform pg_temp.edit('tickets','signup');
 begin perform pg_temp.edit('tickets','signup',null,null); raise exception 'a room without capacity';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_CAPACITY'; end;
end $$;
reset role;
do $$ begin
 assert (select entry = 'signup' and capacity = 20 and is_free is null from public.events where id = current_setting('test.tickets')::uuid),'back to a room';
end $$;

rollback;

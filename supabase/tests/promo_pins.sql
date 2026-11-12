-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Промокоди й піни — 20261204120000_promo_pins.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.early',gen_random_uuid()::text,true),set_config('test.late',gen_random_uuid()::text,true),
 set_config('test.word','pinword'||replace(gen_random_uuid()::text,'-',''),true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-promo-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','birth_date','1990-01-01')),
 (current_setting('test.guest')::uuid,'poruch-promo-guest-'||current_setting('test.guest')||'@example.invalid',jsonb_build_object('display_name','Guest','adult_confirmed',true));

set local role authenticated;
do $$
declare v record;
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.create_event(current_setting('test.early')::uuid,'Early '||current_setting('test.word'),'Board games night','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10);
 perform public.create_event(current_setting('test.late')::uuid,'Late '||current_setting('test.word'),'Board games night','games','Kyiv','Podil',50.46,30.52,
  now()+interval '5 days',now()+interval '5 days 3 hours','Europe/Kyiv',10);

 -- Промокод ставить лише організатор.
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 begin perform public.set_event_promo(current_setting('test.early')::uuid,'PORIAD15','−15% на квитки');
  raise exception 'guest set a promo code';
 exception when sqlstate '42501' then assert sqlerrm='NOT_ORGANIZER','only the organizer'; end;

 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.set_event_promo(current_setting('test.early')::uuid,' PORIAD15 ','−15% на квитки');
 select * into v from public.event_details(current_setting('test.early')::uuid);
 assert v.promo_code='PORIAD15' and v.promo_note='−15% на квитки','promo is public';
 assert v.promo_until=v.starts_at,'by default — until the start';

 begin perform public.set_event_promo(current_setting('test.early')::uuid,'two words');
  raise exception 'code with a space accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PROMO_CODE','latin, digits, - and _'; end;
 begin perform public.set_event_promo(current_setting('test.early')::uuid,'PORIAD15',null,now()+interval '9 days');
  raise exception 'promo after the event accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_PROMO_UNTIL','not after the end'; end;

 -- Порожній код прибирає все.
 perform public.set_event_promo(current_setting('test.early')::uuid,'');
 select * into v from public.event_details(current_setting('test.early')::uuid);
 assert v.promo_code is null and v.promo_note is null and v.promo_until is null,'empty code clears';

 -- Правка застосунком (update_event без промокоду) його не стирає.
 perform public.set_event_promo(current_setting('test.early')::uuid,'KEEP-ME');
 perform public.update_event(current_setting('test.early')::uuid,'Early '||current_setting('test.word'),'Board games night','games','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false);
 select * into v from public.event_details(current_setting('test.early')::uuid);
 assert v.promo_code='KEEP-ME','update_event keeps the promo';
end $$;
reset role;

-- Минулий строк — промокоду не видно.
update public.events set promo_until = now() - interval '1 minute' where id = current_setting('test.early')::uuid;
-- Пін на пізнішу подію.
insert into private.event_pins(event_id) values (current_setting('test.late')::uuid);

set local role anon;
do $$
declare v record; d jsonb;
begin
 select * into v from public.event_details(current_setting('test.early')::uuid);
 assert v.promo_code is null and v.promo_until is null,'expired promo is hidden';

 -- Закріплена — перша, хоч і пізніша, з 15-ю позицією 1; решта — null.
 d := public.discover_events(50.0,30.0,51.0,31.0,null,null,null,current_setting('test.word'),false,5000,24,false);
 assert jsonb_array_length(d->'index')=2,'both events found';
 assert d->'index'->0->>0=current_setting('test.late') and d->'index'->0->>14='1','pinned first, flagged';
 assert d->'index'->1->>0=current_setting('test.early') and d->'index'->1->14='null'::jsonb,'others unflagged';
 assert d->'cards' @> jsonb_build_array(jsonb_build_object('id',current_setting('test.late'))),'pinned among the first cards';
end $$;
reset role;

-- Пін зі строком у минулому не діє.
update private.event_pins set ends_at = now() - interval '1 minute' where event_id = current_setting('test.late')::uuid;
set local role anon;
do $$
declare d jsonb;
begin
 d := public.discover_events(50.0,30.0,51.0,31.0,null,null,null,current_setting('test.word'),false,5000,24,false);
 assert d->'index'->0->>0=current_setting('test.early'),'expired pin — usual order';
end $$;
reset role;
select 'PASS: promo_pins' as result;
rollback;

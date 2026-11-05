-- Оплата онлайн: безпека для трьох сторін (docs/organizer-events.md, «Безпека оплати онлайн»; власник 05.11, P0).
-- «Поряд» лишається посередником, що не торкається грошей, але дбає: допуск за рівнями, зафіксовані згоди, правила
-- повернення до заявки, вимикач для окремого організатора за скаргами, розмова про повернення після скасування й
-- докази, що не зникають з видаленням акаунта.
--
-- Рівні (private.pay_online_tiers, міняються запитом, без релізу): новий — до 500 ₴ і 10 місць; після першої
-- проведеної події з учасниками й 30 днів — до 1 500 ₴ і 30; після трьох і 90 днів — до 5 000 ₴ і 100. Оплата на
-- місці — без обмежень.
--
--   update private.pay_online_tiers set max_price = 800 where level = 0;          -- новачкам — до 800 ₴
--   delete from private.pay_online_blocks where user_id = '…';                    -- повернути організатору оплату онлайн

-- ───── Рівні допуску

create table private.pay_online_tiers (
 level integer primary key,
 min_held integer not null,      -- проведених подій з учасниками
 min_days integer not null,      -- днів на «Поряд»
 max_price integer not null,     -- ₴ за людину
 max_capacity integer not null   -- місць на подію
);
insert into private.pay_online_tiers values (0,0,0,500,10),(1,1,30,1500,30),(2,3,90,5000,100);
revoke all on private.pay_online_tiers from public, anon, authenticated;

-- Проведені: спільнотні, опубліковані, вже минули, хоч один учасник, окрім організатора.
create function private.events_held(p_user uuid) returns integer
language sql stable security definer set search_path='' as $$
 select count(*)::integer from public.events e
 where e.organizer_id=p_user and e.origin='community' and e.status='published' and e.ends_at < now()
 and exists(select 1 from public.event_members m where m.event_id=e.id and m.status='approved' and m.user_id<>p_user);
$$;

create function private.pay_online_tier(p_user uuid) returns private.pay_online_tiers
language sql stable security definer set search_path='' as $$
 -- Невідомий вік акаунта — як новий: межі не мають зникати.
 with h as (select private.events_held(p_user) as held, coalesce((select now() - u.created_at from auth.users u where u.id=p_user), interval '0') as age)
 select t.* from private.pay_online_tiers t, h
 where t.min_held <= h.held and t.min_days <= extract(epoch from h.age) / 86400
 order by t.level desc limit 1;
$$;

-- ───── Вимикач для окремого організатора: скарги платників (on_payment_report) чи модератор.

create table private.pay_online_blocks (
 user_id uuid primary key references auth.users(id) on delete cascade,
 reason text not null,
 blocked_at timestamptz not null default now()
);
revoke all on private.pay_online_blocks from public, anon, authenticated;

create function private.pay_online_allowed(p_organizer uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.flag('pay_online') and not exists(select 1 from private.pay_online_blocks b where b.user_id=p_organizer);
$$;

-- ───── Згоди: організатор — на «Правила оплати онлайн», платник — перед заявкою на конкретну подію. Версія — дата
-- редакції розділу «Оплата онлайн» в Умовах (site/terms.html); нова редакція — нова згода.

create function private.pay_terms_version() returns text language sql immutable set search_path='' as $$ select '2026-11-05'::text; $$;

create table private.pay_consents (
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check (role in ('organizer','payer')),
 event_id uuid references public.events(id) on delete cascade,
 version text not null,
 accepted_at timestamptz not null default now()
);
create unique index pay_consents_once on private.pay_consents (user_id, role, coalesce(event_id, '00000000-0000-0000-0000-000000000000'::uuid), version);
revoke all on private.pay_consents from public, anon, authenticated;

create function private.has_pay_consent(p_user uuid, p_role text, p_event uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.pay_consents c where c.user_id=p_user and c.role=p_role
  and c.event_id is not distinct from p_event and c.version=private.pay_terms_version());
$$;

create function public.accept_pay_terms(p_role text, p_event_id uuid default null) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_role not in ('organizer','payer') or (p_role='payer') <> (p_event_id is not null) then raise exception 'INVALID_ROLE' using errcode='22023'; end if;
 insert into private.pay_consents(user_id, role, event_id, version) values (v_user, p_role, p_event_id, private.pay_terms_version())
 on conflict do nothing;
end $$;

-- Кабінету: що можна цьому організатору зараз і що відкриється далі.
create function public.my_pay_online_limits() returns jsonb
language sql stable security definer set search_path='' as $$
 with t as (select * from private.pay_online_tier(auth.uid()))
 select jsonb_build_object(
  'enabled', private.pay_online_allowed(auth.uid()),
  'level', t.level, 'max_price', t.max_price, 'max_capacity', t.max_capacity,
  'held', private.events_held(auth.uid()),
  'terms', private.has_pay_consent(auth.uid(), 'organizer'),
  'next', (select jsonb_build_object('held', n.min_held, 'days', n.min_days, 'max_price', n.max_price, 'max_capacity', n.max_capacity)
           from private.pay_online_tiers n where n.level = t.level + 1))
 from t where auth.uid() is not null;
$$;

-- ───── Правила повернення: обов'язкові в онлайн-події, показуються до заявки. Скасовано організатором — повертає
-- все за будь-якого правила (Умови, «Оплата онлайн»).

alter table public.events add column refund_policy text check (refund_policy in ('before_48h','before_24h','cancel_only'));
comment on column public.events.refund_policy is 'Оплата онлайн: before_48h, before_24h — повне повернення, якщо скасувати заявку раніше; cancel_only — лише якщо подію скасовано.';

-- ───── Подія онлайн: прапорець, блок, згода організатора, правила повернення й межі рівня.

create or replace function private.guard_pay_online() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_becoming boolean := new.pay_online and (tg_op = 'INSERT' or not old.pay_online); v_tier private.pay_online_tiers;
begin
 if not new.pay_online then return new; end if;
 if v_becoming then
  if not private.flag('pay_online') then raise exception 'PAY_ONLINE_OFF' using errcode='P0001'; end if;
  if not private.pay_online_allowed(new.organizer_id) then raise exception 'PAY_ONLINE_BLOCKED' using errcode='P0001'; end if;
  if not private.has_pay_consent(new.organizer_id, 'organizer') then raise exception 'PAY_TERMS_REQUIRED' using errcode='P0001'; end if;
 end if;
 if new.refund_policy is null and (v_becoming or old.refund_policy is not null) then
  raise exception 'REFUND_POLICY_REQUIRED' using errcode='22023'; end if;
 -- Межі — коли подія стає онлайн чи змінюються ціна й місця; стара подія, що вже вища за рівень, лишається як є.
 if v_becoming or new.price_min is distinct from old.price_min or new.capacity is distinct from old.capacity then
  v_tier := private.pay_online_tier(new.organizer_id);
  if new.price_min > v_tier.max_price or coalesce(new.capacity, 2147483647) > v_tier.max_capacity then
   raise exception 'PAY_ONLINE_LIMIT' using errcode='P0001'; end if;
 end if;
 return new;
end $$;
drop trigger events_pay_online on public.events;
create trigger events_pay_online before insert or update of pay_online, price_min, capacity, refund_policy on public.events
 for each row execute function private.guard_pay_online();

-- ───── Заявка на онлайн-подію — лише зі згодою платника на цю подію (бачив правила повернення й «Поряд» не приймає
-- оплату). Онлайн-події завжди за підтвердженням, і черга їх не просуває (promote_waitlist), тож учасник з'являється
-- лише заявкою.

create function private.guard_payer_terms() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_event public.events;
begin
 if new.status <> 'requested' then return new; end if;
 select * into v_event from public.events where id=new.event_id;
 if v_event.pay_online and private.pay_online_allowed(v_event.organizer_id) and new.user_id <> v_event.organizer_id
    and not private.has_pay_consent(new.user_id, 'payer', new.event_id) then
  raise exception 'PAY_TERMS_REQUIRED' using errcode='P0001'; end if;
 return new;
end $$;
create trigger event_members_payer_terms before insert on public.event_members
 for each row execute function private.guard_payer_terms();

-- ───── Реквізити й скріншоти: лише в опублікованій онлайн-події дозволеного організатора.

create or replace function private.guard_payment_messages() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_event public.events;
begin
 if not (new.payment_details or new.image is not null) then return new; end if;
 select * into v_event from public.events where id=new.event_id;
 if not private.pay_online_allowed(v_event.organizer_id) or v_event.status <> 'published' then
  raise exception '%', case when new.image is not null then 'INVALID_IMAGE' else 'PAYMENT_DETAILS' end using errcode='22023';
 end if;
 return new;
end $$;

-- Тіло — з 20261125160000, змінено: дозвіл організатора замість лише прапорця.
create or replace function private.can_upload_proof(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
  and private.proof_owner(p_name) = auth.uid()
  and exists(select 1 from public.events e join public.event_members m on m.event_id=e.id and m.user_id=auth.uid()
   where e.id = private.proof_event(p_name) and e.pay_online and private.pay_online_allowed(e.organizer_id) and e.status='published'
   and e.ends_at > now() - interval '7 days' and not private.blocked_between(auth.uid(), e.organizer_id))
  -- Тека людини — діапазоном імені (байтово «/» < «0»), а не split_part: індекс (bucket_id, name collate "C") Storage
  -- читає лише її файли, а не весь бакет.
  and (select count(*) from storage.objects o where o.bucket_id='payment-proofs'
   and o.name collate "C" >= auth.uid()::text || '/' and o.name collate "C" < auth.uid()::text || '0'
   and o.created_at > now() - interval '1 day') < 20;
$$;

-- Тіло — з 20261125130000, змінено: розмова про оплату після скасування й 30 днів після кінця.
create or replace function private.send_message(p_event_id uuid, p_body text, p_thread uuid default null, p_image text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_body text := btrim(p_body); v_id uuid; v_details boolean;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 2000 then raise exception 'INVALID_MESSAGE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_body);
 select * into v_event from public.events where id=p_event_id;
 if not found then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 if p_thread is null then
  if not private.can_view_members(p_event_id) then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
  -- Запит без відповіді ще не всередині: can_view_members пускає його до ростера, але не до чату.
  if v_event.organizer_id is distinct from v_user and not exists(
   select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=v_user and m.status='approved') then
   raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 else
  -- Афіша без організатора в застосунку, питання самому собі, сторонній у чужій розмові — ні.
  if v_event.organizer_id is null or p_thread = v_event.organizer_id
     or v_user not in (p_thread, v_event.organizer_id)
     or private.blocked_between(v_event.organizer_id, p_thread) then
   raise exception 'NOT_MEMBER' using errcode='42501'; end if;
  -- Організатор першим пише лише тому, хто вже питав, записався, подав заявку чи стоїть у черзі.
  if v_user = v_event.organizer_id
     and not exists(select 1 from public.event_messages m where m.event_id=p_event_id and m.thread_user_id=p_thread and m.author_id=p_thread)
     and not exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=p_thread)
     and not exists(select 1 from public.event_waitlist w where w.event_id=p_event_id and w.user_id=p_thread) then
   raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 end if;
 -- Розмова про оплату онлайн-події лишається й після скасування: домовитись про повернення грошей. Реквізитів і
 -- скріншотів там уже не приймає тригер event_messages_pay_online.
 if v_event.status <> 'published' and not (v_event.status = 'cancelled' and p_thread is not null and v_event.pay_online) then
  raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 -- Тиждень після кінця — щоб домовитись про фото й речі; розмова про оплату — 30 днів, на повернення.
 if v_event.ends_at < now() - (case when p_thread is not null and v_event.pay_online then interval '30 days' else interval '7 days' end) then
  raise exception 'CHAT_CLOSED' using errcode='P0001'; end if;
 -- Реквізити — лише вдвох і лише там, де оплата онлайн: у загальному чаті їх бачать усі, а «на місці» — без передоплати.
 v_details := private.has_payment_details(v_body);
 if v_details and not (v_event.pay_online and p_thread is not null) then raise exception 'PAYMENT_DETAILS' using errcode='22023'; end if;
 -- Скріншот оплати — лише від людини в її розмові онлайн-події і лише свій уже вивантажений файл цієї події.
 if p_image is not null and (p_thread is null or v_user <> p_thread or not v_event.pay_online
     or private.proof_owner(p_image) is distinct from v_user or private.proof_event(p_image) is distinct from p_event_id
     or not exists(select 1 from storage.objects o where o.bucket_id='payment-proofs' and o.name=p_image)) then
  raise exception 'INVALID_IMAGE' using errcode='22023'; end if;
 -- Двадцять на хвилину — розмова; більше — скрипт. Видалені й розмови теж рахуються.
 if (select count(*) from public.event_messages where author_id=v_user and created_at > now()-interval '1 minute') >= 20 then
  raise exception 'TOO_MANY_MESSAGES' using errcode='P0001'; end if;
 insert into public.event_messages(event_id,author_id,body,thread_user_id,payment_details,image)
 values (p_event_id,v_user,v_body,p_thread,v_details,p_image) returning id into v_id;
 return v_id;
end $$;

-- ───── Клієнтам: дозвіл організатора й правила повернення.
alter type public.event_result add attribute refund_policy text;
-- Тіло — з 20261125160000, змінено: pay_online з дозволом організатора, додано refund_policy.
create or replace function private.event_rows(p_ids uuid[])
returns setof public.event_result language sql stable security definer set search_path='' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,
 coalesce(p.display_name, s.name),
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
 e.origin,s.name,e.canonical_url,e.import_status,e.price_min,e.is_free,
 -- Чат — лише своїм: організатору й підтвердженим. Запит і черга ще не всередині.
 case when e.organizer_id=auth.uid()
       or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved')
      then e.contact_url end,
 e.companion_of,
 pe.title,
 cs.state, cs.previous_starts_at, cs.checked_at,
 case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end,
 -- R7а: питання до організатора збору бачать усі, кому видно збір (учасникам — «Організатор вирішує»).
 case when e.status = 'published' then d.proposed_at end,
 case when e.status = 'published' then d.decide_by end,
 pe.starts_at,
 e.media,
 -- Вимкнено (усім чи цьому організатору) — усі бачать «на місці»; правила повернення — лише в онлайн-події.
 e.pay_online and private.pay_online_allowed(e.organizer_id),
 case when e.pay_online and private.pay_online_allowed(e.organizer_id) then e.refund_policy end
 from public.events e
 left join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 left join public.events pe on pe.id=e.companion_of
 left join private.companion_decisions d on d.companion_id=e.id
 cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
 where e.id=any(p_ids) and private.has_event_access(e.id)
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$$;

-- ───── Створення й правка: правила повернення. Старі сигнатури зникають: PostgREST не має вибирати між двома.
drop function if exists public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean);
drop function if exists private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean);
drop function if exists public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean);
drop function if exists private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean);

-- Тіла — з 20261125120000, додано: `p_refund_policy` (null — не чіпати; лише в онлайн-події).
create function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_via text default 'app', p_price integer default null, p_pay_online boolean default null, p_refund_policy text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events; v_media jsonb := coalesce(p_media,'[]'::jsonb);
 v_price integer := nullif(p_price,0); v_online boolean;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into v_existing from public.events where id=p_id for update;
 if found then
  if v_existing.organizer_id is distinct from v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
  return p_id;
 end if;
 if p_via not in ('app','web') then raise exception 'INVALID_VIA' using errcode='22023'; end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 perform private.assert_contact_url(p_contact_url);
 perform private.assert_image_url(p_image_url, v_user, p_id);
 perform private.assert_media(v_media, v_user, p_id);
 perform private.assert_price(p_price);
 -- Місто й адреса теж показуються всім на мапі й картці — той самий стоп-словник.
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 if private.has_payment_details(concat_ws(' ', p_title, p_description, p_address, p_contact_url)) then
  raise exception 'PAYMENT_DETAILS' using errcode='22023'; end if;
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 v_online := coalesce(p_pay_online,false) and v_price is not null;
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required,contact_url,media,created_via,price_min,pay_online,refund_policy)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,
  case when p_media is null then p_image_url else private.media_cover(p_media,null) end,p_min_age,p_max_age,p_approval_required or v_online,
  nullif(btrim(p_contact_url),''),v_media,p_via,v_price,v_online,case when v_online then p_refund_policy end);
 return p_id;
end $$;

create function private.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_price integer default null, p_pay_online boolean default null, p_refund_policy text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_existing public.events; v_price numeric; v_online boolean;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_existing from public.events where id=p_id for update;
 perform private.assert_organizer(v_existing, v_user);
 if v_existing.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if p_capacity < (select count(*) from public.event_members where event_id=p_id and status='approved') then raise exception 'CAPACITY_BELOW_ATTENDANCE' using errcode='P0001'; end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 perform private.assert_contact_url(p_contact_url);
 perform private.assert_image_url(p_image_url, v_user, p_id);
 perform private.assert_media(p_media, v_user, p_id);
 perform private.assert_price(p_price);
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 if private.has_payment_details(concat_ws(' ', p_title, p_description, p_address, p_contact_url)) then
  raise exception 'PAYMENT_DETAILS' using errcode='22023'; end if;
 v_price := case when p_price is null then v_existing.price_min else nullif(p_price,0) end;
 v_online := coalesce(p_pay_online, v_existing.pay_online) and v_price is not null;
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=p_capacity,
 image_url=case when p_media is null then p_image_url else private.media_cover(p_media,null) end,
 media=coalesce(p_media,media),
 price_min=v_price, pay_online=v_online, refund_policy=case when v_online then coalesce(p_refund_policy, v_existing.refund_policy) end,
 min_age=p_min_age,max_age=p_max_age,approval_required=p_approval_required or v_online,contact_url=nullif(btrim(p_contact_url),''),updated_at=now() where id=p_id;
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

create function public.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_via text default 'app',p_price integer default null,p_pay_online boolean default null,p_refund_policy text default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_via,p_price,p_pay_online,p_refund_policy);
$$;

create function public.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_price integer default null,p_pay_online boolean default null,p_refund_policy text default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.update_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_price,p_pay_online,p_refund_policy);
$$;

revoke all on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text), public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text), public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text)
 from public,anon,authenticated;
grant execute on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text), public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean,text),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text), public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean,text)
 to authenticated;

-- ───── Скарги: двоє різних платників онлайн-подій організатора скаржаться на шахрайство (на нього чи на
-- повідомлення в розмові) — його оплату онлайн вимкнено до розгляду. Подія й акаунт лишаються.

create function private.on_payment_report() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_org uuid; v_count integer;
begin
 if new.reason <> 'scam' or new.subject_type <> 'user' or new.event_id is null then return new; end if;
 select e.organizer_id into v_org from public.events e where e.id=new.event_id and e.pay_online and e.organizer_id=new.subject_user_id;
 if v_org is null then return new; end if;
 select count(distinct r.reporter_id) into v_count from public.reports r join public.events e on e.id=r.event_id
  where r.reason='scam' and r.subject_type='user' and r.subject_user_id=v_org and r.status in ('new','reviewing','actioned')
  and e.organizer_id=v_org and e.pay_online
  and exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=r.reporter_id);
 if v_count >= 2 then insert into private.pay_online_blocks(user_id, reason) values (v_org, 'reports') on conflict do nothing; end if;
 return new;
end $$;
create trigger reports_payment after insert on public.reports for each row execute function private.on_payment_report();

-- ───── Видалення акаунта: організатор з майбутньою онлайн-подією, на яку вже записались, спершу її скасовує
-- (PAID_EVENTS_ACTIVE). Розмови про оплату онлайн-подій (з реквізитами чи скріншотом), згоди й дані організатора
-- зберігаються ще 180 днів після події — для розгляду скарг і запитів правоохоронців (Політика конфіденційності).

create table private.payment_evidence (
 id bigint generated always as identity primary key,
 event_id uuid not null,
 organizer_id uuid not null,
 deleted_user_id uuid not null,
 snapshot jsonb not null,
 archived_at timestamptz not null default now(),
 purge_after timestamptz not null
);
revoke all on private.payment_evidence from public, anon, authenticated;

create function private.prepare_account_deletion(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.events e where e.organizer_id=p_user and e.pay_online and e.status='published' and e.ends_at > now()
   and exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id<>p_user)) then
  raise exception 'PAID_EVENTS_ACTIVE' using errcode='P0001'; end if;
 insert into private.payment_evidence(event_id, organizer_id, deleted_user_id, snapshot, purge_after)
 select e.id, e.organizer_id, p_user, jsonb_build_object(
   'event', jsonb_build_object('title', e.title, 'starts_at', e.starts_at, 'status', e.status, 'price', e.price_min, 'refund_policy', e.refund_policy),
   'organizer', (select jsonb_build_object('name', p.display_name, 'email', u.email) from public.profiles p join auth.users u on u.id=p.id where p.id=e.organizer_id),
   'payer', (select jsonb_build_object('id', p.id, 'name', p.display_name, 'email', u.email) from public.profiles p join auth.users u on u.id=p.id where p.id=t.thread_user_id),
   'messages', (select jsonb_agg(jsonb_build_object('author', m.author_id, 'body', m.body, 'at', m.created_at, 'payment_details', m.payment_details,
      'image', m.image, 'deleted_at', m.deleted_at) order by m.created_at) from public.event_messages m where m.event_id=e.id and m.thread_user_id=t.thread_user_id),
   'consents', (select jsonb_agg(jsonb_build_object('user', c.user_id, 'role', c.role, 'version', c.version, 'at', c.accepted_at))
      from private.pay_consents c where (c.user_id=e.organizer_id and c.role='organizer') or (c.user_id=t.thread_user_id and c.event_id=e.id))),
  greatest(e.ends_at, now()) + interval '180 days'
 from public.events e
 join (select distinct m.event_id, m.thread_user_id from public.event_messages m where m.thread_user_id is not null) t on t.event_id=e.id
 where e.pay_online and (e.organizer_id=p_user or t.thread_user_id=p_user) and e.ends_at > now() - interval '180 days'
 and exists(select 1 from public.event_messages m where m.event_id=e.id and m.thread_user_id=t.thread_user_id and (m.payment_details or m.image is not null));
end $$;
-- Функція `delete-account` ключем service role, перед видаленням.
create function public.prepare_account_deletion(p_user uuid) returns void
language sql security definer set search_path='' as $$ select private.prepare_account_deletion(p_user); $$;

-- Видалення з SQL (старий шлях) — так само.
create or replace function private.delete_my_account() returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform private.prepare_account_deletion(v_user);
 perform pg_catalog.set_config('storage.allow_delete_query','true',true);
 delete from storage.objects where bucket_id in ('event-images','event-videos') and name like v_user::text || '/%';
 delete from auth.users where id=v_user;
end $$;

create function private.purge_payment_evidence() returns integer language sql security definer set search_path='' as $$
 with gone as (delete from private.payment_evidence where purge_after < now() returning 1) select count(*)::integer from gone;
$$;
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('purge-payment-evidence', '41 4 * * *', 'select private.purge_payment_evidence()')$cron$;
 end if;
end $$;

revoke all on function private.events_held(uuid), private.pay_online_tier(uuid), private.pay_online_allowed(uuid),
 private.has_pay_consent(uuid,text,uuid), private.guard_payer_terms(), private.on_payment_report(),
 private.prepare_account_deletion(uuid), public.prepare_account_deletion(uuid), private.purge_payment_evidence()
 from public, anon, authenticated;
grant execute on function public.prepare_account_deletion(uuid) to service_role;
revoke all on function public.accept_pay_terms(text,uuid), public.my_pay_online_limits() from public, anon;
grant execute on function public.accept_pay_terms(text,uuid), public.my_pay_online_limits() to authenticated;

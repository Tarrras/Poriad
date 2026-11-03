-- «Оплата онлайн» (docs/organizer-events.md, власник 03.11): у платної події від людей два способи оплати.
-- «На місці» — як і було: «Оплата на місці, без передоплати». «Онлайн» — людина записується заявкою («Чекає оплати»),
-- організатор надсилає реквізити в розмові на двох і схвалює заявку, коли гроші прийшли («Оплату отримано»). «Поряд» —
-- лише міст: пошти й телефону одне одного вони не бачать, гроші йдуть повз нас, і за оплату ми не відповідаємо — так
-- написано на сторінці події, у шторці запису й під повідомленням з реквізитами. Вмикати може будь-хто (власник 03.11).
--
-- 1. `events.pay_online`; `p_pay_online` у create_event/update_event (null — не чіпати: так поводиться старий клієнт).
--    Онлайн — лише з ціною й завжди за підтвердженням: схвалення і є «Оплату отримано».
-- 2. Реквізити — номер картки (з перевіркою Луна), IBAN UA, посилання на банку чи переказ — лише в розмові на двох
--    онлайн-події. У назві, описі, адресі й посиланні на чат їх побачили б усі, а в події «на місці» вони суперечать
--    «без передоплати»: `PAYMENT_DETAILS`. Повідомлення з реквізитами позначене (`payment_details`), і клієнт показує
--    під ним застереження.
-- 3. Організатор пише першим тому, хто записався, подав заявку чи став у чергу: реквізити надсилають, не чекаючи
--    питання. Чужим, як і раніше, лише відповідає.
-- 4. Лист тому, хто питав, коли організатор написав (функція `push`): не частіше разу на годину на розмову, окремо від
--    листів організатору — інакше відповідь на свіже питання мовчала б годину.

-- ───── 1. Спосіб оплати
alter table public.events add column pay_online boolean not null default false;
comment on column public.events.pay_online is 'Оплата онлайн організатору до зустрічі (реквізити в розмові); false — на місці.';

-- ───── 2. Реквізити в тексті
create function private.has_payment_details(p_text text) returns boolean
language plpgsql immutable set search_path='' as $$
declare v_match text[]; v_digits text; v_n integer; v_sum integer; v_d integer;
begin
 if p_text is null or p_text = '' then return false; end if;
 -- IBAN України: UA, дві контрольні цифри й 25 цифр, групи через пробіл.
 if p_text ~* 'UA[[:space:]]*[0-9]{2}([[:space:]]*[0-9]){25}' then return true; end if;
 -- Банка й переказ на картку посиланням.
 if p_text ~* '(send|pay|base)\.monobank\.ua|monobank\.ua/(jar|send)|privat24\.ua|privatbank\.ua/(send|p2p)|paypal\.me/' then return true; end if;
 -- Картка: 13–19 цифр, групи через пробіл чи дефіс, і контрольна цифра Луна. Телефон (12 цифр) сюди не влазить.
 for v_match in select regexp_matches(p_text, '(^|[^0-9])([0-9](?:[ -]?[0-9]){12,18})(?![0-9])', 'g') loop
  v_digits := regexp_replace(v_match[2], '[^0-9]', '', 'g');
  continue when v_digits ~ '^(.)\1+$'; -- «0000 0000 0000 0000» Луна проходить, але це не картка
  v_n := length(v_digits);
  v_sum := 0;
  for i in 1..v_n loop
   v_d := substr(v_digits, v_n - i + 1, 1)::integer;
   if i % 2 = 0 then v_d := v_d * 2; if v_d > 9 then v_d := v_d - 9; end if; end if;
   v_sum := v_sum + v_d;
  end loop;
  if v_sum % 10 = 0 then return true; end if;
 end loop;
 return false;
end $$;
revoke all on function private.has_payment_details(text) from public, anon, authenticated;

alter table public.event_messages add column payment_details boolean not null default false;

-- ───── Подія: створення й зміна. Старі сигнатури (з p_price) зникають: PostgREST не має вибирати між двома, а
-- клієнт без `p_pay_online` потрапляє в нову через значення за замовчуванням.
drop function if exists public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer);
drop function if exists private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer);
drop function if exists public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer);
drop function if exists private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer);

-- Тіло — з 20261124120000, додано: `p_pay_online` і реквізити в тексті.
create function private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_via text default 'app', p_price integer default null, p_pay_online boolean default null) returns uuid
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
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required,contact_url,media,created_via,price_min,pay_online)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,
  case when p_media is null then p_image_url else private.media_cover(p_media,null) end,p_min_age,p_max_age,p_approval_required or v_online,
  nullif(btrim(p_contact_url),''),v_media,p_via,v_price,v_online);
 return p_id;
end $$;

-- Тіло — з 20261124120000, додано: `p_pay_online` (null — не чіпати) і реквізити в тексті. Онлайн без ціни — на місці.
create function private.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamptz, p_ends_at timestamptz, p_time_zone text, p_capacity integer, p_image_url text default null, p_min_age integer default 18, p_max_age integer default null, p_approval_required boolean default false, p_contact_url text default null, p_media jsonb default null, p_price integer default null, p_pay_online boolean default null) returns uuid
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
 price_min=v_price, pay_online=v_online,
 min_age=p_min_age,max_age=p_max_age,approval_required=p_approval_required or v_online,contact_url=nullif(btrim(p_contact_url),''),updated_at=now() where id=p_id;
 perform private.promote_waitlist(p_id);
 return p_id;
end $$;

create function public.create_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_via text default 'app',p_price integer default null,p_pay_online boolean default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_via,p_price,p_pay_online);
$$;
create function public.update_event(p_id uuid,p_title text,p_description text,p_category text,p_city text,p_address text,p_latitude double precision,p_longitude double precision,p_starts_at timestamptz,p_ends_at timestamptz,p_time_zone text,p_capacity integer,p_image_url text default null,p_min_age integer default 18,p_max_age integer default null,p_approval_required boolean default false,p_contact_url text default null,p_media jsonb default null,p_price integer default null,p_pay_online boolean default null) returns uuid language sql security invoker set search_path = '' as $$
 select private.update_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url,p_media,p_price,p_pay_online);
$$;
revoke all on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean),
 public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean),
 public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean)
 from public,anon,authenticated;
grant execute on function
 private.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean),
 public.create_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,text,integer,boolean),
 private.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean),
 public.update_event(uuid,text,text,text,text,text,double precision,double precision,timestamptz,timestamptz,text,integer,text,integer,integer,boolean,text,jsonb,integer,boolean)
 to authenticated;

-- ───── Клієнтам: спосіб оплати в деталях
alter type public.event_result add attribute pay_online boolean;

-- Тіло — з 20261118120000, додано: `e.pay_online`.
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
 e.pay_online
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

-- ───── 3. Розмова: організатор пише першим тим, хто записався; реквізити — лише в розмові онлайн-події
-- Тіло — з 20261116120000, додано: організатор першим — тим, хто в ростері, заявках чи черзі; `PAYMENT_DETAILS`;
-- позначка `payment_details`.
create or replace function private.send_message(p_event_id uuid, p_body text, p_thread uuid default null) returns uuid
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
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 -- Тиждень після кінця — щоб домовитись про фото й речі; далі чат закривається.
 if v_event.ends_at < now() - interval '7 days' then raise exception 'CHAT_CLOSED' using errcode='P0001'; end if;
 -- Реквізити — лише вдвох і лише там, де оплата онлайн: у загальному чаті їх бачать усі, а «на місці» — без передоплати.
 v_details := private.has_payment_details(v_body);
 if v_details and not (v_event.pay_online and p_thread is not null) then raise exception 'PAYMENT_DETAILS' using errcode='22023'; end if;
 -- Двадцять на хвилину — розмова; більше — скрипт. Видалені й розмови теж рахуються.
 if (select count(*) from public.event_messages where author_id=v_user and created_at > now()-interval '1 minute') >= 20 then
  raise exception 'TOO_MANY_MESSAGES' using errcode='P0001'; end if;
 insert into public.event_messages(event_id,author_id,body,thread_user_id,payment_details)
 values (p_event_id,v_user,v_body,p_thread,v_details) returning id into v_id;
 return v_id;
end $$;

-- Стрічка віддає й позначку реквізитів: під таким повідомленням клієнт показує застереження.
alter type public.message_result add attribute payment_details boolean;
-- Тіло — з 20261116120000, додано: `m.payment_details`.
create or replace function public.event_messages(p_event_id uuid,p_after timestamptz default null,p_limit integer default 100,p_thread uuid default null)
 returns setof public.message_result language sql stable security invoker set search_path='' as $$
 select * from (
  select m.id,m.event_id,m.author_id,p.display_name,p.avatar_url,m.body,m.created_at,m.payment_details
  from public.event_messages m join public.profiles p on p.id=m.author_id
  where m.event_id=p_event_id and m.thread_user_id is not distinct from p_thread and (p_after is null or m.created_at > p_after)
  order by m.created_at desc,m.id desc limit greatest(1,least(coalesce(p_limit,100),200))
 ) tail order by created_at,id;
$$;

-- ───── 4. Лист тому, хто питав: окремий лічильник, один лист на годину на розмову (функція `push`, `answer_mail_due`).
create table private.answer_mails (
 event_id uuid not null references public.events(id) on delete cascade,
 thread_user_id uuid not null references public.profiles(id) on delete cascade,
 sent_at timestamptz not null default now(),
 primary key (event_id, thread_user_id)
);
revoke all on private.answer_mails from public, anon, authenticated;

create function private.answer_mail_due(p_event uuid, p_thread uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_due boolean;
begin
 insert into private.answer_mails as a (event_id, thread_user_id) values (p_event, p_thread)
 on conflict (event_id, thread_user_id) do update set sent_at = now() where a.sent_at <= now() - interval '1 hour'
 returning true into v_due;
 return coalesce(v_due, false);
end $$;
create function public.answer_mail_due(p_event uuid, p_thread uuid) returns boolean
language sql security invoker set search_path='' as $$ select private.answer_mail_due(p_event, p_thread); $$;
revoke all on function private.answer_mail_due(uuid, uuid), public.answer_mail_due(uuid, uuid) from public, anon, authenticated;
-- Лише функція `push` ключем service role.
grant execute on function private.answer_mail_due(uuid, uuid), public.answer_mail_due(uuid, uuid) to service_role;

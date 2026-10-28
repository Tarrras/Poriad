-- 1.4 «Хочу піти з компанією» (docs/return-hooks.md, хвиля 1). Легкий намір на афішу замість форми супутника: тизер
-- бачать усі, людей — лише ті, хто сам має намір, а взаємне «Піти разом» збирає звичайний супутник з чатом.
--
-- Порядок викладки: спершу `functions deploy push` (тип `company`), потім ця міграція. Старим клієнтам вона нічого не
-- ламає: 12-ту позицію видачі вони не читають, пуш `company` іде лише на токени з прапорцем `company`.

-- ───────────────────────────────────────────── Instagram

-- Окремо від `profiles`: ті, хто ділить з людиною подію, читають її рядок `profiles` напряму, а Instagram має бачити
-- лише той, хто має намір на ту саму подію і вказав свій.
create table private.profile_links (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 instagram text not null check (instagram ~ '^[a-z0-9._]{1,30}$'),
 updated_at timestamptz not null default now()
);
revoke all on private.profile_links from public, anon, authenticated;

-- Порожнє — прибрати. Клієнт нормалізує сам (`CompanyRules.normalizeInstagram`), сервер лише перевіряє.
create function private.set_instagram(p_handle text) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_handle text := nullif(lower(btrim(p_handle)), '');
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if v_handle is null then delete from private.profile_links where user_id = v_user; return; end if;
 if v_handle !~ '^[a-z0-9._]{1,30}$' then raise exception 'INVALID_INSTAGRAM' using errcode='22023'; end if;
 insert into private.profile_links(user_id, instagram) values (v_user, v_handle)
 on conflict (user_id) do update set instagram = excluded.instagram, updated_at = now();
end $$;
create function public.set_instagram(p_handle text) returns void
language sql security invoker set search_path='' as $$ select private.set_instagram(p_handle); $$;
revoke all on function private.set_instagram(text), public.set_instagram(text) from public, anon, authenticated;
grant execute on function private.set_instagram(text), public.set_instagram(text) to authenticated;

-- ───────────────────────────────────────────── наміри

create table private.company_intents (
 event_id uuid not null references public.events(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (event_id, user_id)
);
create index company_intents_user_idx on private.company_intents (user_id, created_at);
revoke all on private.company_intents from public, anon, authenticated;

-- «Піти разом» від однієї людини іншій на одну афішу. Пара в обидва боки — збіг.
create table private.company_yes (
 event_id uuid not null references public.events(id) on delete cascade,
 from_id uuid not null references public.profiles(id) on delete cascade,
 to_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (event_id, from_id, to_id)
);
create index company_yes_from_idx on private.company_yes (from_id, created_at);
revoke all on private.company_yes from public, anon, authenticated;

-- Журнал пушів «ще хтось хоче піти»: дедуп (людині про афішу — раз на добу) і метрика.
create table private.company_pushes (
 user_id uuid not null references public.profiles(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 sent_at timestamptz not null default now()
);
create index company_pushes_idx on private.company_pushes (user_id, event_id, sent_at);
revoke all on private.company_pushes from public, anon, authenticated;

-- Афіша, на яку можна мати намір: як у `create_companion` (жива, ще не почалась) і ще у видачі.
-- ponytail: намір на злитому дублі лишається на надгробку й тихо зникає; переносити, як `companion_of`, — якщо
-- злиття почнуть губити помітну частку намірів.
create function private.company_event_ok(p_event uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.events e where e.id = p_event and e.origin = 'import' and e.status = 'published'
  and e.import_status = 'live' and e.starts_at > now()
  and private.is_listed(e.starts_at, e.ends_at, e.title) and private.is_discoverable(e.origin, e.import_status, e.quality));
$$;


-- Двоє мають намір на ту саму живу подію: тоді вони бачать картки одне одного.
create function private.company_peers(a uuid, b uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.company_intents x
  join private.company_intents y on y.event_id = x.event_id and y.user_id = b
  join public.events e on e.id = x.event_id
  where x.user_id = a and e.status = 'published' and e.starts_at > now());
$$;
revoke all on function private.company_event_ok(uuid), private.company_peers(uuid, uuid) from public, anon, authenticated;

-- ───────────────────────────────────────────── пуші

-- Тіло — з 20261020120000, у ранкову чергу йде ще й `company`: «хоче піти з вами» вночі читається як тривога.
create or replace function private.notify_push(p_payload jsonb) returns void language plpgsql security definer set search_path='' as $$
declare v_url text; v_secret text;
begin
 select url,secret into v_url,v_secret from private.push_endpoint();
 if v_url is null or v_secret is null then return; end if;
 -- «Стежити» й компанія вночі — у чергу до ранку: `flush_deferred_pushes` відправить, функція `push` ще раз
 -- перевірить, що подія жива. Решта типів — транзакційні, їх не тримаємо.
 if p_payload->>'type' in ('follow','company') and private.quiet_hours() then
  insert into private.deferred_pushes(payload) values (p_payload);
  return;
 end if;
 -- Асинхронно: відповідь функції транзакцію не тримає.
 perform net.http_post(
  url:=v_url,
  body:=p_payload,
  headers:=jsonb_build_object('Content-Type','application/json','x-push-secret',v_secret),
  timeout_milliseconds:=5000
 );
exception when others then
 -- Пуш — доповнення: збій доставки не має зламати запис повідомлення чи запиту.
 raise warning 'push notify failed: %', sqlerrm;
end $$;

-- Текст складає база, як у `change`: функції `push` лишається перевірити, що подія ще попереду.
create function private.push_company(p_event uuid, p_users uuid[], p_body text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if p_users is null or cardinality(p_users) = 0 then return; end if;
 perform private.notify_push(jsonb_build_object('type', 'company', 'event_id', p_event,
  'title', (select e.title from public.events e where e.id = p_event), 'body', p_body, 'user_ids', to_jsonb(p_users)));
end $$;

-- Новий намір — тим, хто вже має намір на цю афішу, раз на добу на афішу. Лише токени з прапорцем `company`: інакше
-- журнал записав би «сказано» людині, чий застосунок пуш не покаже.
create function private.notify_company_new(p_event uuid, p_from uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare v_users uuid[];
begin
 if (select e.url from private.push_endpoint() e) is null then return 0; end if;
 select array_agg(i.user_id order by i.created_at) into v_users from private.company_intents i
 where i.event_id = p_event and i.user_id <> p_from and private.account_active(i.user_id)
  and not private.blocked_between(i.user_id, p_from)
  and not exists(select 1 from private.company_pushes x
   where x.user_id = i.user_id and x.event_id = p_event and x.sent_at > now() - interval '24 hours')
  and exists(select 1 from public.push_tokens t where t.user_id = i.user_id and 'company' = any(t.features));
 if v_users is null then return 0; end if;
 insert into private.company_pushes(user_id, event_id) select u, p_event from unnest(v_users) u;
 perform private.push_company(p_event, v_users, 'Ще хтось хоче піти з компанією — гляньте, хто');
 return cardinality(v_users);
end $$;
revoke all on function private.push_company(uuid, uuid[], text), private.notify_company_new(uuid, uuid) from public, anon, authenticated;

-- Тіло — з 20260923130000. Збіг сам додає учасника в супутник і шле свій пуш «Ви йдете разом», тож «приєднався»
-- організатору тут зайвий.
create or replace function private.on_member_requested() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if current_setting('poruch.company_match', true) = 'on' then return new; end if;
 perform private.notify_push(jsonb_build_object(
  'type', case when new.status='requested' then 'request' else 'joined' end,
  'event_id', new.event_id, 'user_id', new.user_id));
 return new;
end $$;

-- ───────────────────────────────────────────── намір

-- Повертає, скільки інших уже хоче піти. Зняття прибирає й свої «Піти разом».
create function private.set_company_intent(p_event_id uuid, p_on boolean) returns integer
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if coalesce(p_on, false) then
  if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
  if not private.company_event_ok(p_event_id) then raise exception 'COMPANION_UNAVAILABLE' using errcode='P0001'; end if;
  if not exists(select 1 from private.company_intents where event_id = p_event_id and user_id = v_user) then
   if (select count(*) from private.company_intents where user_id = v_user and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'TOO_MANY_INTENTS' using errcode='P0001'; end if;
   insert into private.company_intents(event_id, user_id) values (p_event_id, v_user) on conflict do nothing;
   begin
    perform private.notify_company_new(p_event_id, v_user);
   exception when others then
    -- Пуш — доповнення: збій розсилки не має забрати намір.
    raise warning 'company push failed: %', sqlerrm;
   end;
  end if;
 else
  delete from private.company_yes where event_id = p_event_id and from_id = v_user;
  delete from private.company_intents where event_id = p_event_id and user_id = v_user;
 end if;
 return (select count(*)::integer from private.company_intents i
  where i.event_id = p_event_id and i.user_id <> v_user and private.account_active(i.user_id)
   and not private.blocked_between(v_user, i.user_id));
end $$;
create function public.set_company_intent(p_event_id uuid, p_on boolean) returns integer
language sql security invoker set search_path='' as $$ select private.set_company_intent(p_event_id, p_on); $$;

-- Рівень 1: скільки людей і спільні з тим, хто дивиться, інтереси (лише з входом). Гість бачить тільки число. Віку тут
-- нема свідомо: і діапазони, і «вашого віку» читались як анкета (власник, 28.10) — хто ця людина, видно в її картці.
create function private.company_teaser(p_event_id uuid)
returns table(count integer, shared text[], mine boolean)
language sql stable security definer set search_path='' as $$
 with others as (
  select i.user_id
  from private.company_intents i
  where i.event_id = p_event_id and i.user_id is distinct from auth.uid() and private.account_active(i.user_id)
   and (auth.uid() is null or not private.blocked_between(auth.uid(), i.user_id))
   and private.company_event_ok(p_event_id)
 ), mine as (
  select coalesce((select up.categories from public.user_preferences up where up.user_id = auth.uid()), '{}'::text[]) as cats
 ), cats as (
  select c, count(*) as n
  from others o join public.user_preferences up on up.user_id = o.user_id cross join mine m, unnest(up.categories) c
  where c = any(m.cats)
  group by c order by count(*) desc, c limit 3
 )
 select count(*)::integer,
  coalesce((select array_agg(x.c order by x.n desc, x.c) from cats x), '{}'::text[]),
  auth.uid() is not null and exists(select 1 from private.company_intents i where i.event_id = p_event_id and i.user_id = auth.uid())
 from others o;
$$;
create function public.company_teaser(p_event_id uuid)
returns table(count integer, shared text[], mine boolean)
language sql stable security invoker set search_path='' as $$ select * from private.company_teaser(p_event_id); $$;

-- Рівень 2: люди з наміром — лише тому, хто сам має намір на цю афішу. Фото й Instagram — за правилом «бачиш те, що
-- показуєш сам». Спершу ті, хто вже сказав «Піти разом», далі за часом наміру.
create function private.company_people(p_event_id uuid)
returns table(user_id uuid, name text, avatar_url text, bio text, instagram text,
 shared text[], attended integer, said_yes boolean, they_said_yes boolean, companion_id uuid)
language sql stable security definer set search_path='' as $$
 with me as (
  select auth.uid() as id,
   (select p.avatar_url from public.profiles p where p.id = auth.uid()) as avatar,
   (select l.instagram from private.profile_links l where l.user_id = auth.uid()) as insta,
   coalesce((select up.categories from public.user_preferences up where up.user_id = auth.uid()), '{}'::text[]) as cats
  where auth.uid() is not null and private.company_event_ok(p_event_id)
   and exists(select 1 from private.company_intents i where i.event_id = p_event_id and i.user_id = auth.uid())
 ), people as (
  select p.id, p.display_name, p.avatar_url, p.bio, l.instagram, up.categories, i.created_at
  from me join private.company_intents i on i.event_id = p_event_id and i.user_id <> me.id
  join public.profiles p on p.id = i.user_id
  left join private.profile_links l on l.user_id = p.id
  left join public.user_preferences up on up.user_id = p.id
  where private.account_active(p.id) and not private.blocked_between(me.id, p.id)
 )
 select x.id, split_part(btrim(x.display_name), ' ', 1),
  case when me.avatar is not null then x.avatar_url end,
  x.bio,
  case when me.insta is not null then x.instagram end,
  coalesce((select array_agg(c order by c) from unnest(coalesce(x.categories, '{}'::text[])) c where c = any(me.cats)), '{}'::text[]),
  (select count(*)::integer from public.event_members m join public.events e on e.id = m.event_id
    where m.user_id = x.id and m.status = 'approved' and e.status = 'published' and e.ends_at < now()),
  exists(select 1 from private.company_yes y where y.event_id = p_event_id and y.from_id = me.id and y.to_id = x.id),
  exists(select 1 from private.company_yes y where y.event_id = p_event_id and y.from_id = x.id and y.to_id = me.id) as they,
  (select c.id from public.events c where c.companion_of = p_event_id and c.status = 'published' and c.starts_at > now()
    and (c.organizer_id = x.id or exists(select 1 from public.event_members m
     where m.event_id = c.id and m.user_id = x.id and m.status = 'approved'))
   order by c.created_at limit 1)
 from me cross join people x
 order by they desc, x.created_at
 limit 20;
$$;
create function public.company_people(p_event_id uuid)
returns table(user_id uuid, name text, avatar_url text, bio text, instagram text,
 shared text[], attended integer, said_yes boolean, they_said_yes boolean, companion_id uuid)
language sql stable security invoker set search_path='' as $$ select * from private.company_people(p_event_id); $$;

-- ───────────────────────────────────────────── збіг

-- Вставка супутника без перевірок людини: їх робить той, хто кличе. Тіло — з `create_companion` (20261008130000).
create function private.insert_companion(p_organizer uuid, p_parent public.events, p_meet_at timestamptz, p_note text, p_capacity integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid := pg_catalog.gen_random_uuid();
begin
 -- Назву й опис складаємо тут: людина пише лише примітку. Місце, категорія й пояс — батьківські.
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
  capacity,min_age,approval_required,place_id,companion_of,meet_note)
 values(v_id,p_organizer,btrim(left('Йдемо разом: '||p_parent.title,120)),
  left('Йдемо разом на «'||p_parent.title||'».'||coalesce(' Збір: '||p_note,''),5000),
  p_parent.category,p_parent.city,p_parent.address,p_parent.latitude,p_parent.longitude,p_meet_at,p_parent.ends_at,p_parent.time_zone,
  p_capacity,18,true,p_parent.place_id,p_parent.id,p_note);
 return v_id;
end $$;

-- Тіло — з 20261008130000, вставку винесено в `insert_companion`.
create or replace function private.create_companion(p_parent_id uuid, p_meet_at timestamptz, p_meet_note text default null, p_capacity integer default 4) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_parent public.events; v_note text := nullif(btrim(p_meet_note),''); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 -- Той самий замок, що в create_event: ліміт на добу рахується без гонки.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 select * into v_parent from public.events where id=p_parent_id;
 if not found or v_parent.origin <> 'import' or v_parent.status <> 'published' or v_parent.import_status is distinct from 'live'
    or v_parent.starts_at <= now() then
  raise exception 'COMPANION_UNAVAILABLE' using errcode='P0001'; end if;
 -- Повтор після непевної відповіді чи другий тап — той самий супутник, а не другий.
 select e.id into v_id from public.events e where e.companion_of=p_parent_id and e.organizer_id=v_user and e.status='published';
 if found then return v_id; end if;
 if p_meet_at is null or p_meet_at <= now() or p_meet_at > v_parent.starts_at or p_meet_at < v_parent.starts_at - interval '3 hours' then
  raise exception 'INVALID_MEET_TIME' using errcode='22023'; end if;
 if p_capacity is null or p_capacity not between 2 and 8 then raise exception 'INVALID_CAPACITY' using errcode='22023'; end if;
 if char_length(v_note) > 140 then raise exception 'INVALID_MEET_NOTE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_note);
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 return private.insert_companion(v_user, v_parent, p_meet_at, v_note, p_capacity);
end $$;

-- Двоє сказали одне одному «Піти разом». Хтось із них уже в живому супутнику цієї афіші (організатор чи учасник) —
-- другий іде туди ж; інакше супутник збирає той, хто поставив намір раніше: зустріч за 30 хв до початку, 4 місця.
-- Ліміт «6 подій на добу» тут не рахується: людина нічого не створювала.
create function private.company_match(p_event uuid, a uuid, b uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_comp uuid; v_org uuid; v_cap integer; v_who uuid; v_parent public.events; v_meet timestamptz;
begin
 select c.id, c.organizer_id, c.capacity into v_comp, v_org, v_cap from public.events c
 where c.companion_of = p_event and c.status = 'published' and c.starts_at > now()
  and (c.organizer_id in (a, b) or exists(select 1 from public.event_members m
   where m.event_id = c.id and m.user_id in (a, b) and m.status = 'approved'))
 order by c.created_at limit 1;
 if v_comp is null then
  select i.user_id into v_org from private.company_intents i
  where i.event_id = p_event and i.user_id in (a, b) order by i.created_at, i.user_id limit 1;
  select * into v_parent from public.events where id = p_event;
  -- Сітка 15 хв, як у шторці супутника; подія вже за пів години — збір на сам початок.
  v_meet := date_bin('15 minutes', v_parent.starts_at - interval '30 minutes', timestamptz '2000-01-01');
  if v_meet <= now() then v_meet := v_parent.starts_at; end if;
  v_comp := private.insert_companion(v_org, v_parent, v_meet, null, 4);
  v_cap := 4;
 end if;
 perform set_config('poruch.company_match', 'on', true);
 foreach v_who in array array[a, b] loop
  if v_who <> v_org and not exists(select 1 from public.event_members m
    where m.event_id = v_comp and m.user_id = v_who and m.status = 'approved') then
   if (select count(*) from public.event_members m where m.event_id = v_comp and m.status = 'approved') >= v_cap then
    perform set_config('poruch.company_match', 'off', true);
    raise exception 'EVENT_FULL' using errcode='P0001';
   end if;
   insert into public.event_members(event_id, user_id, status) values (v_comp, v_who, 'approved')
   on conflict (event_id, user_id) do update set status = 'approved';
   delete from public.event_waitlist w where w.event_id = v_comp and w.user_id = v_who;
  end if;
 end loop;
 perform set_config('poruch.company_match', 'off', true);
 return v_comp;
end $$;

-- «Піти разом». Перше — пуш тому, кому сказали; взаємне — супутник і пуш обом. Повтор нічого не шле вдруге.
create function private.company_yes(p_event_id uuid, p_user_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_new boolean; v_comp uuid; v_name text;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_user_id is null or p_user_id = v_user or not private.company_event_ok(p_event_id) or not private.account_active(p_user_id)
  or not exists(select 1 from private.company_intents where event_id = p_event_id and user_id = v_user)
  or not exists(select 1 from private.company_intents where event_id = p_event_id and user_id = p_user_id) then
  raise exception 'NOT_IN_COMPANY' using errcode='P0001'; end if;
 if private.blocked_between(v_user, p_user_id) then raise exception 'BLOCKED' using errcode='42501'; end if;
 -- Двоє тиснуть одночасно — збіг один, супутник один.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('company:'||p_event_id::text, 0));
 if (select count(*) from private.company_yes where from_id = v_user and created_at > now() - interval '1 hour') >= 30 then
  raise exception 'TOO_MANY_INTENTS' using errcode='P0001'; end if;
 insert into private.company_yes(event_id, from_id, to_id) values (p_event_id, v_user, p_user_id) on conflict do nothing;
 v_new := found;
 if not exists(select 1 from private.company_yes where event_id = p_event_id and from_id = p_user_id and to_id = v_user) then
  if v_new then
   select split_part(btrim(p.display_name), ' ', 1) into v_name from public.profiles p where p.id = v_user;
   perform private.push_company(p_event_id, array[p_user_id], coalesce(v_name, 'Хтось') || ' хоче піти з вами');
  end if;
  return jsonb_build_object('matched', false);
 end if;
 v_comp := private.company_match(p_event_id, v_user, p_user_id);
 if v_new then perform private.push_company(v_comp, array[v_user, p_user_id], 'Ви йдете разом — чат відкрито'); end if;
 return jsonb_build_object('matched', true, 'companion_id', v_comp);
end $$;
create function public.company_yes(p_event_id uuid, p_user_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select private.company_yes(p_event_id, p_user_id); $$;

revoke all on function private.set_company_intent(uuid, boolean), public.set_company_intent(uuid, boolean),
 private.company_teaser(uuid), public.company_teaser(uuid), private.company_people(uuid), public.company_people(uuid),
 private.insert_companion(uuid, public.events, timestamptz, text, integer), private.company_match(uuid, uuid, uuid),
 private.company_yes(uuid, uuid), public.company_yes(uuid, uuid) from public, anon, authenticated;
grant execute on function private.set_company_intent(uuid, boolean), public.set_company_intent(uuid, boolean),
 private.company_people(uuid), public.company_people(uuid), private.company_yes(uuid, uuid), public.company_yes(uuid, uuid)
 to authenticated;
grant execute on function private.company_teaser(uuid), public.company_teaser(uuid) to anon, authenticated;

-- ───────────────────────────────────────────── картка людини

-- Instagram — у картці: свій завжди, чужий — тим, хто з людиною має намір на ту саму подію і вказав свій.
alter type public.profile_card_result add attribute instagram text;

-- Тіло — з 20260924100000: картку видно ще й тому, хто має намір на ту саму живу подію (звідти «Поскаржитись»).
create or replace function private.profile_card(p_user_id uuid) returns setof public.profile_card_result
language sql stable security definer set search_path='' as $$
 select p.id, p.display_name, p.avatar_url, p.bio, p.created_at,
  (select count(*)::integer from public.events e
    where e.organizer_id=p.id and e.origin='community' and e.status='published'),
  (select count(*)::integer from public.event_members m join public.events e on e.id=m.event_id
    where m.user_id=p.id and m.status='approved' and e.status='published' and e.ends_at < now()),
  case when p.id=auth.uid() then auth.jwt()->>'email' end,
  (select l.instagram from private.profile_links l where l.user_id = p.id and (p.id = auth.uid()
    or (private.company_peers(auth.uid(), p.id) and exists(select 1 from private.profile_links me where me.user_id = auth.uid()))))
 from public.profiles p
 where p.id=p_user_id and auth.uid() is not null and (
  p.id=auth.uid() or (
   private.account_active(p.id) and not private.blocked_between(auth.uid(), p.id) and (
    private.can_see_profile(p.id)
    or private.company_peers(auth.uid(), p.id)
    or exists(select 1 from public.events e where e.organizer_id=p.id and e.origin='community' and e.status='published'))));
$$;

-- ───────────────────────────────────────────── видача

-- Тіло — з 20261103120000, додано 12-ту позицію: скільки людей хочуть піти з компанією (лише афіша). Клієнти до 1.4
-- читають перші 11.
create or replace function private.discover_index(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text, p_from timestamptz, p_to timestamptz, p_text text, p_available boolean,
 p_limit integer, p_cards integer)
returns table(index jsonb, total integer, truncated boolean, card_ids uuid[])
language sql stable security definer set search_path='' as $$
 with matched as (
  select e.id, e.starts_at, e.latitude, e.longitude, e.category, e.time_zone, e.title,
         e.origin, e.capacity, e.source_id
  from public.events e
  where e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
    -- Варіант у підзапиті: рахується раз на виклик, а не на кожен рядок.
    and (nullif(btrim(p_text),'') is null
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), lower(btrim(p_text))) > 0
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), (select private.search_translit(p_text))) > 0)
    -- `case` замість `and`: порядок обчислення кон'юнкції не гарантований.
    and (not coalesce(p_available,false)
         or case when e.capacity is null then false else private.event_has_space(e.id) end)
    and (p_category is null or e.category = p_category)
    and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
    and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
      or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
       or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326)))))
 , ranked as (
  select m.*, row_number() over (order by greatest(m.starts_at, now()), m.id) as rank,
         count(*) over () as total
  from matched m
 )
 , page as (select r.* from ranked r where r.rank <= p_limit)
 select
  coalesce((select jsonb_agg(jsonb_build_array(
     p.id, p.latitude, p.longitude, p.category, p.starts_at, p.time_zone, p.title, p.origin,
     s.slug,
     p.capacity,
     case when p.origin='community' then
       (select count(*)::integer from public.event_members mm where mm.event_id=p.id and mm.status='approved')
     else 0 end,
     -- ponytail: рахуємо всіх, без блоків і неактивних — точне число дає `company_teaser` на деталях.
     case when p.origin='import' then
       (select count(*)::integer from private.company_intents ci where ci.event_id=p.id)
     else 0 end
   ) order by p.rank) from page p left join public.event_sources s on s.id=p.source_id), '[]'::jsonb),
  coalesce((select max(r.total)::integer from ranked r), 0),
  coalesce((select max(r.total) from ranked r), 0) > p_limit,
  coalesce((select array_agg(p.id order by p.rank) from page p where p.rank <= p_cards), '{}'::uuid[]);
$$;

-- ───────────────────────────────────────────── копія даних
-- Тіло — з 20260928160000; політика обіцяє в копії й наміри, «Піти разом» та Instagram.
create or replace function public.export_my_data() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'exported_at', now(),
  'email', (select u.email from auth.users u where u.id=auth.uid()),
  'profile', (select to_jsonb(p) from public.profiles p where p.id=auth.uid()),
  'instagram', (select l.instagram from private.profile_links l where l.user_id=auth.uid()),
  'account', (select to_jsonb(a) - 'status_note' from public.account_facts a where a.user_id=auth.uid()),
  'preferences', (select to_jsonb(u) from public.user_preferences u where u.user_id=auth.uid()),
  'events', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from public.events e where e.organizer_id=auth.uid()),
  'memberships', (select coalesce(jsonb_agg(to_jsonb(m)), '[]') from public.event_members m where m.user_id=auth.uid()),
  'saved', (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from public.saved_events s where s.user_id=auth.uid()),
  'waitlist', (select coalesce(jsonb_agg(to_jsonb(w)), '[]') from public.event_waitlist w where w.user_id=auth.uid()),
  'follows', (select coalesce(jsonb_agg(to_jsonb(f)), '[]') from public.follows f where f.user_id=auth.uid()),
  'company_intents', (select coalesce(jsonb_agg(jsonb_build_object('event_id', i.event_id, 'created_at', i.created_at)), '[]')
                      from private.company_intents i where i.user_id=auth.uid()),
  'company_yes', (select coalesce(jsonb_agg(jsonb_build_object('event_id', y.event_id, 'to_id', y.to_id, 'created_at', y.created_at)), '[]')
                  from private.company_yes y where y.from_id=auth.uid()),
  'blocks', (select coalesce(jsonb_agg(to_jsonb(b)), '[]') from public.user_blocks b where b.user_id=auth.uid()),
  'reports', (select coalesce(jsonb_agg(to_jsonb(r)), '[]') from public.reports r where r.reporter_id=auth.uid()),
  'messages', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.event_messages x where x.author_id=auth.uid()),
  'ratings', (select coalesce(jsonb_agg(to_jsonb(g)), '[]') from public.event_ratings g where g.user_id=auth.uid()),
  'chat_reads', (select coalesce(jsonb_agg(to_jsonb(c)), '[]') from public.chat_reads c where c.user_id=auth.uid()),
  'push_devices', (select coalesce(jsonb_agg(jsonb_build_object('platform',t.platform,'updated_at',t.updated_at)), '[]')
                   from public.push_tokens t where t.user_id=auth.uid())
 );
$$;
revoke all on function public.export_my_data() from public, anon, authenticated;
grant execute on function public.export_my_data() to authenticated;

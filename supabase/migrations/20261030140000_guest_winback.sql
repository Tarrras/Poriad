-- Серверний канал повернення (docs/guest-channel.md, варіант А): пристрій без акаунта з `last_seen`, щоб той, хто
-- забув застосунок, отримав не більше двох свіжих пушів своєї афіші — близько 30-го і 60-го дня, у пʼятницю о 17:00.
-- 20% придатних — контрольна група: облік без пушу. Без `user_id` свідомо: пристрій не звʼязаний з акаунтом.

create table private.devices (
 token text primary key,                 -- APNs (64 hex) або FCM; той самий, що в push_tokens
 platform text not null check (platform in ('android','ios')),
 city text,                              -- з HomeLocation, null — своє місце на мапі
 interests text[] not null default '{}', -- ключі EventCategory з Taste.interests
 last_seen timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create index devices_last_seen_idx on private.devices(last_seen);

create table private.winback_sends (
 token text not null references private.devices(token) on delete cascade,
 step smallint not null check (step in (1, 2)),
 holdout boolean not null,               -- true — не надсилали, лише облік контрольної групи
 sent_at timestamptz not null default now()
);
create index winback_sends_token_idx on private.winback_sends(token, step, sent_at);
revoke all on private.devices, private.winback_sends from public, anon, authenticated;

-- ---- Клієнт: відкриття застосунку з дозволом і дайджестом

-- Публічний ключ може насипати рядків, тож формат строгий, а нові пристрої вище стелі мовчки не пишемо.
create function private.touch_device(p_token text, p_platform text, p_city text, p_interests text[]) returns void
language plpgsql security definer set search_path='' as $$
declare v_interests text[] := coalesce(p_interests, '{}');
begin
 if p_platform is null or p_platform not in ('android','ios') then raise exception 'INVALID_PLATFORM' using errcode='22023'; end if;
 -- Межа повтору в регулярних виразах Postgres — 255, тож довжину FCM-токена міряємо окремо.
 if p_token is null or (p_platform = 'ios' and p_token !~ '^[0-9a-f]{64}$')
   or (p_platform = 'android' and (p_token !~ '^[A-Za-z0-9_:-]+$' or length(p_token) not between 100 and 4096)) then
  raise exception 'INVALID_TOKEN' using errcode='22023';
 end if;
 if p_city is not null and p_city not in ('Київ','Харків','Одеса','Дніпро','Львів') then raise exception 'INVALID_CITY' using errcode='22023'; end if;
 if cardinality(v_interests) > 11 or array_position(v_interests, null) is not null or not v_interests <@ array['music','sport','art','food','games',
   'outdoors','social','comedy','kids','tours','conference'] then
  raise exception 'INVALID_INTERESTS' using errcode='22023';
 end if;
 update private.devices set platform = p_platform, city = p_city, interests = v_interests, last_seen = now() where token = p_token;
 if found then return; end if;
 if (select count(*) from private.devices) >= 100000 then
  raise warning 'touch_device: devices ceiling reached, new device not stored';
  return;
 end if;
 insert into private.devices(token, platform, city, interests) values (p_token, p_platform, p_city, v_interests)
 on conflict (token) do update set platform = excluded.platform, city = excluded.city, interests = excluded.interests, last_seen = now();
end $$;

-- Дайджест вимкнено або дозволу нема: пристрій зникає разом з обліком його кроків.
create function private.forget_device(p_token text) returns void language sql security definer set search_path='' as $$
 delete from private.devices where token = p_token;
$$;
create function public.touch_device(p_token text, p_platform text, p_city text, p_interests text[]) returns void
language sql security invoker set search_path='' as $$ select private.touch_device(p_token, p_platform, p_city, p_interests); $$;
create function public.forget_device(p_token text) returns void language sql security invoker set search_path='' as $$
 select private.forget_device(p_token);
$$;
revoke all on function private.touch_device(text,text,text,text[]), private.forget_device(text),
 public.touch_device(text,text,text,text[]), public.forget_device(text) from public, anon, authenticated;
grant execute on function private.touch_device(text,text,text,text[]), private.forget_device(text),
 public.touch_device(text,text,text,text[]), public.forget_device(text) to anon, authenticated;
-- Функція `push` прибирає мертві токени через `forget_device` ключем service role.
grant execute on function private.forget_device(text), public.forget_device(text) to service_role;

-- ---- Сервер: хто заснув і що йому сказати

-- Крок 1 — `last_seen` від 35 до 28 днів тому, крок 2 — від 63 до 56; кожен лише раз після `last_seen`, тож
-- повернення скидає драбину. Вікна по 7 днів: щопʼятничний прогін бачить кожен пристрій у кожному рівно раз.
-- Контрольна група — детерміновано за токеном; `::bigint`, бо `abs` від найменшого int4 переповнюється.
create function private.winback_due(p_now timestamptz default now())
returns table(token text, platform text, step smallint, holdout boolean, city text, interests text[])
language sql stable security definer set search_path='' as $$
 select d.token, d.platform, w.step, abs(hashtext(d.token)::bigint) % 5 = 0, d.city, d.interests
 from private.devices d
 cross join lateral (select case
   when d.last_seen <= p_now - interval '28 days' and d.last_seen > p_now - interval '35 days' then 1
   when d.last_seen <= p_now - interval '56 days' and d.last_seen > p_now - interval '63 days' then 2
  end::smallint as step) w
 where w.step is not null
  and not exists (select 1 from private.winback_sends s where s.token = d.token and s.step = w.step and s.sent_at > d.last_seen);
$$;

-- Пʼятниця, 17:00 за Києвом: як локальний дайджест (`DigestRules`) — події міста на суботу-неділю, спершу з інтересів
-- людини. Менше 3 — пропускаємо цю пʼятницю, крок не зараховано (і контрольній групі теж: групи мають бути рівні).
-- Годину перевіряє сама функція, тож перехід на зимовий час пуш не зсуває. [p_now] — для тестів.
-- ponytail: один виклик `push` на пристрій; тисячі за пʼятницю — пакетами по токенах.
create function private.send_winbacks(p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path='' as $$
declare v_local timestamp := p_now at time zone 'Europe/Kyiv'; v_from timestamptz; v_to timestamptz;
 v_row record; v_sent integer := 0;
begin
 delete from private.devices where last_seen < p_now - interval '120 days';
 if extract(isodow from v_local) <> 5 or extract(hour from v_local) <> 17 then return 0; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('send_winbacks', 0));
 v_from := (v_local::date + 1)::timestamp at time zone 'Europe/Kyiv';
 v_to := (v_local::date + 3)::timestamp at time zone 'Europe/Kyiv';
 for v_row in
  with runs as (
   -- Прокат із кількох сеансів — одна подія; супутники «Шукаю компанію» — не окремі події.
   select distinct on (e.city, lower(btrim(e.title))) e.id, e.city, e.title, e.category, e.starts_at
   from public.events e
   where e.status = 'published' and e.companion_of is null
    and e.starts_at >= v_from and e.starts_at < v_to
    and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
    and (e.organizer_id is null or private.account_active(e.organizer_id))
   order by e.city, lower(btrim(e.title)), e.starts_at, e.id
  ), totals as (
   select r.city, count(*)::integer as total from runs r group by r.city
  )
  select d.token, d.platform, d.step, d.holdout, d.city, t.total,
   array(select r.title from runs r where r.city = d.city
         order by (r.category = any(d.interests)) desc, r.starts_at, r.id limit 2) as titles
  from private.winback_due(p_now) d join totals t on t.city = d.city
  where t.total >= 3
 loop
  insert into private.winback_sends(token, step, holdout, sent_at) values (v_row.token, v_row.step, v_row.holdout, p_now);
  continue when v_row.holdout;
  perform private.notify_push(jsonb_build_object('type','winback','token',v_row.token,'platform',v_row.platform,
   'step',v_row.step,'city',v_row.city,'total',v_row.total,'titles',to_jsonb(v_row.titles)));
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $$;
revoke all on function private.winback_due(timestamptz), private.send_winbacks(timestamptz) from public, anon, authenticated;

-- Щогодини в пʼятницю, де є pg_cron (на prod є); :02, :05 і :07 зайняті зведеннями й чергою тихих годин.
-- Без pg_cron (dev) — ручний `select private.send_winbacks()`.
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('send-winbacks', '12 * * * 5', 'select private.send_winbacks()')$cron$;
 end if;
end $$;

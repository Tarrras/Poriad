-- Аудит безпеки 2026-10-22 (docs/security-audit-2026-10-22.md): M1, M2, L1, L13.

-- ───────────────────────────────────────────── M1: гостьовий канал не забити з публічним ключем

-- Нових пристроїв з однієї адреси — не більше 60 на годину. `cf-connecting-ip` ставить Cloudflare перед API,
-- клієнт його не підробить (на відміну від x-forwarded-for). Без заголовка (сервер, тести) — без ліміту.
-- 60, а не 5: мобільні оператори ховають тисячі людей за однією адресою (CGNAT).
create table private.device_ips (ip text not null, at timestamptz not null default now());
create index device_ips_ip_idx on private.device_ips(ip, at);
revoke all on private.device_ips from public, anon, authenticated;

-- Тіло — з 20261030140000_guest_winback; додано ліміт нових пристроїв на адресу.
create or replace function private.touch_device(p_token text, p_platform text, p_city text, p_interests text[]) returns void
language plpgsql security definer set search_path='' as $$
declare v_interests text[] := coalesce(p_interests, '{}');
 -- nullif: у сесії після запиту PostgREST налаштування лишається порожнім рядком, а не null.
 v_ip text := nullif(nullif(current_setting('request.headers', true), '')::json->>'cf-connecting-ip', '');
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
 if v_ip is not null then
  delete from private.device_ips where ip = v_ip and at < now() - interval '1 hour';
  if (select count(*) from private.device_ips where ip = v_ip) >= 60 then
   raise warning 'touch_device: too many new devices from one address, not stored';
   return;
  end if;
  insert into private.device_ips(ip) values (v_ip);
 end if;
 if (select count(*) from private.devices) >= 100000 then
  raise warning 'touch_device: devices ceiling reached, new device not stored';
  return;
 end if;
 insert into private.devices(token, platform, city, interests) values (p_token, p_platform, p_city, v_interests)
 on conflict (token) do update set platform = excluded.platform, city = excluded.city, interests = excluded.interests, last_seen = now();
end $$;

-- Тіло — з 20261030140000_guest_winback; додано стелю прогону й прибирання адрес.
-- ponytail: стеля 5000 пушів за пʼятницю — кожен пристрій окремий виклик `push`; решта цього тижня випадає з
-- вікна кроку. Коли справжніх сплячих гостей стане тисячі — слати пакетами (багато токенів на виклик) і зняти стелю.
create or replace function private.send_winbacks(p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path='' as $$
declare v_local timestamp := p_now at time zone 'Europe/Kyiv'; v_from timestamptz; v_to timestamptz;
 v_row record; v_sent integer := 0;
begin
 delete from private.devices where last_seen < p_now - interval '120 days';
 delete from private.device_ips where at < p_now - interval '1 hour';
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
  limit 5000
 loop
  insert into private.winback_sends(token, step, holdout, sent_at) values (v_row.token, v_row.step, v_row.holdout, p_now);
  continue when v_row.holdout;
  perform private.notify_push(jsonb_build_object('type','winback','token',v_row.token,'platform',v_row.platform,
   'step',v_row.step,'city',v_row.city,'total',v_row.total,'titles',to_jsonb(v_row.titles)));
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $$;

-- `push` прибирає мертві токени через public.forget_device ключем service role, а ця обгортка (invoker) кличе
-- private.forget_device. Без USAGE на схему виклик мовчки падав (supabase-js повертає error, а не кидає) —
-- мертві й фальшиві пристрої каналу лишались назавжди. Таблиць `private` це service role не відкриває.
grant usage on schema private to service_role;

-- ───────────────────────────────────────────── M2: перенос по колу не сипле пушами

-- Кожен перенос — пуш усім учасникам (events_push, а для «Шукаю компанію» — move_companion), тож людина може
-- перенести подію не більше 5 разів на добу. Рахуємо лише зміни від користувача: імпорт, черга R6–R7 і
-- модерація йдуть без `auth.uid()` і обмеження не мають. Окремий тригер BEFORE ловить обидва шляхи, не
-- переписуючи update_event і move_companion.
create table private.event_moves (event_id uuid not null, at timestamptz not null default now());
create index event_moves_event_idx on private.event_moves(event_id, at);
revoke all on private.event_moves from public, anon, authenticated;

create function private.limit_moves() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then return new; end if;
 delete from private.event_moves where event_id = new.id and at < now() - interval '1 day';
 if (select count(*) from private.event_moves where event_id = new.id) >= 5 then
  raise exception 'TOO_MANY_MOVES' using errcode='P0001';
 end if;
 insert into private.event_moves(event_id) values (new.id);
 return new;
end $$;
revoke all on function private.limit_moves() from public, anon, authenticated;

create trigger events_move_limit before update of starts_at on public.events for each row
 when (old.starts_at is distinct from new.starts_at and new.organizer_id is not null)
 execute function private.limit_moves();

-- ───────────────────────────────────────────── L1: таблиці лише для читання

-- `grant select` не знімав стандартних прав Supabase на нові таблиці; запис тримала лише RLS без політик запису.
revoke insert, update, delete, truncate, references, trigger on public.artists, public.places from anon, authenticated;

-- ───────────────────────────────────────────── L13: зняти токен після виходу без ключа сесії

-- Вийшли без мережі: застосунок пізніше знімає токен цього пристрою, не зберігаючи JWT на диску. Токен знає
-- лише пристрій і сервер, а user_id — щоб не зняти токен, який тим часом зареєстрував інший акаунт.
create function private.release_push_token(p_token text, p_user_id uuid) returns void
language sql security definer set search_path='' as $$
 delete from public.push_tokens where token = p_token and user_id = p_user_id;
$$;
create function public.release_push_token(p_token text, p_user_id uuid) returns void
language sql security invoker set search_path='' as $$ select private.release_push_token(p_token, p_user_id); $$;
revoke all on function private.release_push_token(text, uuid), public.release_push_token(text, uuid) from public, anon, authenticated;
grant execute on function private.release_push_token(text, uuid), public.release_push_token(text, uuid) to anon, authenticated;

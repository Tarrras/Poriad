-- Тихі години: з 22:00 до 09:00 за Києвом пуші «Стежити» (організатор, заклади, артисти) чекають ранку, а не
-- губляться. Нічний пуш в Україні читається як тривога, а нова подія закладу не варта того, щоб будити.
-- Чат, запити, приєднання, скасування й перенесення — одразу, як і було (docs/follows.md, «Тихі години»).
--
-- Відкладати можна лише тут, у воротах `notify_push`: зведення пише подію в `private.follow_announced` і людину в
-- `private.follow_pushes` ще до виклику, тож пропуск у самій функції `push` загубив би подію назавжди.

create table private.deferred_pushes (
 id bigint generated always as identity primary key,
 payload jsonb not null,
 created_at timestamptz not null default now()
);
revoke all on private.deferred_pushes from public, anon, authenticated;

create function private.quiet_hours(p_at timestamptz default now()) returns boolean
language sql stable set search_path='' as $$
 select extract(hour from p_at at time zone 'Europe/Kyiv') not between 9 and 21;
$$;
revoke all on function private.quiet_hours(timestamptz) from public, anon, authenticated;

-- Тіло — з 20260916115335, додано тихі години.
create or replace function private.notify_push(p_payload jsonb) returns void language plpgsql security definer set search_path='' as $$
declare v_url text; v_secret text;
begin
 select url,secret into v_url,v_secret from private.push_endpoint();
 if v_url is null or v_secret is null then return; end if;
 -- «Стежити» вночі — у чергу до ранку: `flush_deferred_pushes` відправить, функція `push` ще раз перевірить,
 -- що подія жива. Решта типів — транзакційні, їх не тримаємо.
 if p_payload->>'type'='follow' and private.quiet_hours() then
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

-- Ранок: усе, що чекало ночі, іде у функцію `push`. Вночі нічого не робить, тож годинна задача безпечна.
create function private.flush_deferred_pushes() returns integer language plpgsql security definer set search_path='' as $$
declare v_payload jsonb; v_sent integer := 0;
begin
 if private.quiet_hours() then return 0; end if;
 for v_payload in delete from private.deferred_pushes returning payload loop
  perform private.notify_push(v_payload);
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $$;
revoke all on function private.flush_deferred_pushes() from public, anon, authenticated;

-- Щогодини, де є pg_cron (на prod є): перший денний прогін о 09:05 відправляє нічну чергу. Без pg_cron (dev) черга
-- чекає ручного `select private.flush_deferred_pushes()`.
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('flush-deferred-pushes', '5 * * * *', 'select private.flush_deferred_pushes()')$cron$;
 end if;
end $$;

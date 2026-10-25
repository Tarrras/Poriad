-- Пуш «Хтось шукає компанію на вашу збережену подію» (docs/companions.md, «Пуш тим, хто зберіг»;
-- docs/retention-brief-2026-10.md №7). Коли на афішу з'являється «Йдемо разом», люди, що зберегли її в акаунті,
-- дізнаються про це, а тап веде на найближчий збір: там видно, хто збирає, і одна кнопка запиту.
--
-- - Кому: зберегли афішу до того, як з'явився збір; не організатор збору, не в жодному зборі цієї афіші (свій,
--   запит, учасник, черга), не заблоковані з організатором у будь-який бік, не молодші за вік збору, акаунт
--   активний. Лише з токеном застосунку, що знає цей пуш (`push_tokens.features` містить `companion`): Android
--   1.3.1 невідомий kind мовчки відкидає, і людина «отримала» б пуш, якого не бачила. Гість поза межами: його
--   закладки лежать на пристрої.
-- - Скільки: один на людину на афішу — назавжди, а не на кожен новий збір; кілька зборів, що чекали ночі, — один
--   пуш. Стеля — один такий пуш на людину за 24 години, найближчий збір першим; решта лишається «новою» на
--   наступний прогін, поки збір живий. Ліміт «Стежити» (`private.follow_pushes`) окремий: про компанію й про нові
--   події — різні приводи.
-- - Коли: одразу, щойно збір створено (тригер), удень; вночі (22:00–09:00 за Києвом) — першим денним прогоном
--   (pg_cron щогодини). Пізніше ніж за хвилину пуш ще має сенс, тож черги, як у `deferred_pushes`, не треба:
--   прогін сам бачить, що ще не сказано. Між прогоном і доставкою функція `push` ще раз перевіряє, що збір живий.
--
-- РОЗГОРТАННЯ: спершу функція `push` (вона вчить тип `companion`), потім ця міграція. Журнал пишеться до виклику,
-- тож невідомий тип дав би 400, а людина вже не отримала б пуш про цю афішу.

-- ───────────────────────────────────────────── журнал

-- Рядок — пуш однієї людині про одну афішу. companion_id — куди вів тап, companions — скільки зборів було в пуші:
-- метрика «скільком сказали → скільки подали запит» (docs/companions.md).
create table private.companion_pushes (
 user_id uuid not null references public.profiles(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 companion_id uuid references public.events(id) on delete set null,
 companions integer not null check (companions >= 1),
 sent_at timestamptz not null default now(),
 primary key (user_id, event_id)
);
create index companion_pushes_user_idx on private.companion_pushes (user_id, sent_at);
revoke all on private.companion_pushes from public, anon, authenticated;

-- ───────────────────────────────────────────── розсилка

-- [p_parent] — лише одна афіша (тригер нового збору), null — усі (годинний прогін). Повертає, скільком людям
-- поставлено пуш. Без адреси функції `push` нічого не пишемо: інакше людина значилась би сповіщеною.
create function private.notify_saved_companions(p_parent uuid default null) returns integer
language plpgsql security definer set search_path='' as $$
declare g record; n integer := 0;
begin
 if (select e.url from private.push_endpoint() e) is null or private.quiet_hours() then return 0; end if;
 -- Тригер і годинний прогін можуть збігтися: другий чекає й бачить уже записаний журнал.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('notify_saved_companions', 0));
 for g in
  with open as (
   -- Збори, куди ще можна подати запит: як у `companions` — опубліковані, попереду, організатор активний, — і з
   -- вільним місцем. Афіша ще у видачі.
   select c.id, c.companion_of as parent_id, c.organizer_id, c.starts_at, c.created_at, c.min_age
   from public.events c join public.events p on p.id = c.companion_of
   where c.companion_of is not null and (p_parent is null or c.companion_of = p_parent)
    and c.status = 'published' and c.starts_at > now() and private.account_active(c.organizer_id)
    and (select count(*) from public.event_members m where m.event_id = c.id and m.status = 'approved') < c.capacity
    and p.status = 'published' and private.is_discoverable(p.origin, p.import_status, p.quality)
  ), due as (
   select s.user_id, o.parent_id, o.id as companion_id, o.starts_at
   from open o join public.saved_events s on s.event_id = o.parent_id
   where s.user_id <> o.organizer_id and o.created_at > s.created_at
    and not private.blocked_between(s.user_id, o.organizer_id)
    and coalesce(private.age_of(s.user_id), o.min_age) >= o.min_age and private.account_active(s.user_id)
    and not exists (select 1 from private.companion_pushes x where x.user_id = s.user_id and x.event_id = o.parent_id)
    -- Компанію на цю афішу людина вже шукає чи знайшла.
    and not exists (select 1 from public.events c where c.companion_of = o.parent_id and c.status = 'published' and (
     c.organizer_id = s.user_id
     or exists (select 1 from public.event_members m where m.event_id = c.id and m.user_id = s.user_id)
     or exists (select 1 from public.event_waitlist w where w.event_id = c.id and w.user_id = s.user_id)))
    and exists (select 1 from public.push_tokens t where t.user_id = s.user_id and 'companion' = any(t.features))
  ), firsts as (
   -- Стеля: одна афіша на людину за прогін і за 24 години — та, де збір найближчий.
   select distinct on (d.user_id) d.user_id, d.parent_id
   from due d
   where not exists (select 1 from private.companion_pushes x where x.user_id = d.user_id and x.sent_at > now() - interval '24 hours')
   order by d.user_id, d.starts_at, d.parent_id
  ), picked as (
   -- Збори афіші, які людина може бачити, найближчий першим: тап веде на перший.
   select f.user_id, f.parent_id,
    (select array_agg(d.companion_id order by d.starts_at, d.companion_id) from due d
     where d.user_id = f.user_id and d.parent_id = f.parent_id) as ids
   from firsts f
  )
  -- Однаковий список зборів — один виклик функції на всіх.
  select p.parent_id, p.ids, array_agg(p.user_id) as users from picked p group by p.parent_id, p.ids
 loop
  insert into private.companion_pushes (user_id, event_id, companion_id, companions)
  select u, g.parent_id, g.ids[1], cardinality(g.ids) from unnest(g.users) u;
  perform private.notify_push(jsonb_build_object('type', 'companion', 'event_id', g.parent_id,
   'companion_ids', to_jsonb(g.ids[1:20]), 'user_ids', to_jsonb(g.users)));
  n := n + cardinality(g.users);
 end loop;
 return n;
end $$;
revoke all on function private.notify_saved_companions(uuid) from public, anon, authenticated;

-- Новий збір — одразу тим, хто зберіг афішу. Пуш — доповнення: збій розсилки не має зламати `create_companion`.
create function private.on_companion_created() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.notify_saved_companions(new.companion_of);
 return new;
exception when others then
 raise warning 'saved companion push failed: %', sqlerrm;
 return new;
end $$;
revoke all on function private.on_companion_created() from public, anon, authenticated;
create trigger events_saved_companion_push after insert on public.events
 for each row when (new.companion_of is not null and new.status = 'published')
 execute function private.on_companion_created();

-- Щогодини, де є pg_cron: перший денний прогін о 09:09 доставляє те, що чекало ночі чи стелі.
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('saved-companion-pushes', '9 * * * *', 'select private.notify_saved_companions()')$cron$;
 end if;
end $$;

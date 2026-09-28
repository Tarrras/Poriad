-- Підписки: «Стежити» на закладі й на організаторі (docs/follows.md, п. 2.1 docs/growth-2026-09.md).
--
-- Хто стежить — приватне: рядки бачить лише власник, тож ні заклад, ні організатор не дізнаються, хто на
-- них підписаний. Пишуть лише RPC й лише акаунт: пуш прив'язаний до токена акаунта, гість гранту не має.
--
-- Про нову спільнотну подію організатора кажемо одразу: тригер → `private.notify_push` → функція `push`.
-- Про нові події закладу — не по одній: конвеєр імпорту вставляє їх пачками, і пуш на кожен рядок був би
-- спамом. Тож `notify_place_follows` раз у прогін (кінець дампу, а де є pg_cron — щогодини) збирає нове в
-- ОДИН пуш на людину, не частіше ніж раз на добу. Скасування, перенесення й чат ліміту не мають.
-- «Нове» — те, про що людині ще не казали (`private.follow_announced`), а не «створено після останнього
-- пуша»: `created_at` — початок транзакції вставки, а видно її з коміту, тож мітка часу губила б події довгого дампу.

create table public.follows (
 user_id uuid not null references public.profiles(id) on delete cascade,
 target_kind text not null check (target_kind in ('place','organizer')),
 target_id uuid not null,
 created_at timestamptz not null default now(),
 primary key (user_id, target_kind, target_id)
);
-- Зворотний напрямок: хто стежить за закладом чи організатором, коли з'явилась подія.
create index follows_target_idx on public.follows (target_kind, target_id);

alter table public.follows enable row level security;
create policy follows_own on public.follows for select to authenticated using (user_id=(select auth.uid()));
revoke all on public.follows from public, anon, authenticated;
grant select on public.follows to authenticated;

-- Коли людині востаннє йшов пуш про заклади: ліміт «раз на добу».
create table private.follow_pushes (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 sent_at timestamptz not null
);
-- Про які події людині вже сказали. Скінчилась подія — рядок зайвий (вона більше не «нова»), функція його прибирає.
create table private.follow_announced (
 user_id uuid not null references public.profiles(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 primary key (user_id, event_id)
);
revoke all on private.follow_pushes, private.follow_announced from public, anon, authenticated;

-- ---- Що вважається подією, за якою стежать: одне правило для пуша, лічильників і головної.
-- Заклад — афіша з імпорту; організатор — його спільнотні події. Супутник «Йдемо разом» не рахується
-- ніде: місце в нього лише успадковане від афіші, і це не оголошення організатора.
create view private.followed_events as
 select f.user_id, f.target_kind, f.target_id, f.created_at as followed_at,
  e.id as event_id, e.title, e.created_at as event_created_at, e.starts_at, e.place_id
 from public.follows f
 join public.events e on e.place_id = f.target_id
 where f.target_kind = 'place' and e.origin = 'import' and e.status = 'published' and e.ends_at > now()
  and private.is_discoverable(e.origin, e.import_status, e.quality)
 union all
 select f.user_id, f.target_kind, f.target_id, f.created_at,
  e.id, e.title, e.created_at, e.starts_at, null::uuid
 from public.follows f
 join public.events e on e.organizer_id = f.target_id
 where f.target_kind = 'organizer' and e.origin = 'community' and e.companion_of is null
  and e.status = 'published' and e.ends_at > now()
  and private.account_active(e.organizer_id) and not private.blocked_between(f.user_id, e.organizer_id);
revoke all on private.followed_events from public, anon, authenticated;

-- ---- RPC. Публічні обгортки — invoker, робота в приватних definer-функціях, як усюди.

create function private.follow(p_kind text, p_target uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_kind is null or p_kind not in ('place','organizer') or p_target is null then
  raise exception 'INVALID_FOLLOW' using errcode='22023'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_kind = 'place' then
  if not exists (select 1 from public.places where id = p_target) then
   raise exception 'FOLLOW_UNAVAILABLE' using errcode='P0001'; end if;
 else
  -- Одна відповідь на все, зокрема на блокування в будь-який бік: інакше `follow` за чужим id казав би, хто заблокував.
  -- Організатор — той, хто вже проводить спільнотні події: на решту людей стежити нема за чим.
  if p_target = v_user or private.blocked_between(v_user, p_target) or not private.account_active(p_target) or not exists (
   select 1 from public.events e where e.organizer_id = p_target and e.origin = 'community' and e.status = 'published') then
   raise exception 'FOLLOW_UNAVAILABLE' using errcode='P0001'; end if;
 end if;
 -- Стеля: кожна підписка — рядок у списку й у кожному прогоні зведення; більше двохсот — це вже скрипт.
 if (select count(*) from public.follows where user_id = v_user) >= 200 and not exists (
  select 1 from public.follows where user_id = v_user and target_kind = p_kind and target_id = p_target) then
  raise exception 'TOO_MANY_FOLLOWS' using errcode='P0001'; end if;
 insert into public.follows (user_id, target_kind, target_id) values (v_user, p_kind, p_target) on conflict do nothing;
end $$;

create function private.unfollow(p_kind text, p_target uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 delete from public.follows where user_id = auth.uid() and target_kind = p_kind and target_id = p_target;
end $$;

-- Мої підписки з тим, що потрібно списку: назва, де це, скільки подій попереду. Заблокований чи
-- обмежений організатор зникає зі списку, рядок лишається: розблокуєш — підписка на місці.
create function private.my_follows() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(t.item order by t.since desc, t.name), '[]'::jsonb) from (
  select f.created_at as since, p.name,
   jsonb_strip_nulls(jsonb_build_object('kind','place','id',p.id,'name',p.name,'city',p.city,'address',p.address,
    'latitude',p.latitude,'longitude',p.longitude,'since',f.created_at,
    'upcoming',(select count(distinct lower(btrim(v.title)))::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'place' and v.target_id = p.id))) as item
  from public.follows f join public.places p on p.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'place'
  union all
  select f.created_at, pr.display_name,
   jsonb_strip_nulls(jsonb_build_object('kind','organizer','id',pr.id,'name',pr.display_name,'avatar_url',pr.avatar_url,
    'since',f.created_at,
    'upcoming',(select count(*)::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'organizer' and v.target_id = pr.id)))
  from public.follows f join public.profiles pr on pr.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'organizer'
   and private.account_active(pr.id) and not private.blocked_between(f.user_id, pr.id)
 ) t;
$$;

-- Майбутні події з підписок для головної, найближчі першими, картками. Афіша: прокат із кількох сеансів —
-- одна картка (найближчий сеанс), як у стосі закладу на мапі й у пуші. Організатор: кожна подія окремо, бо
-- «Щочетверга» — це різні вечори. Порядок — за `greatest(starts_at, now())`, як у `place_events`: виставка,
-- що триває тижнями, не витісняє найближчі події.
create function private.follow_events(p_limit integer default 20) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_ids uuid[];
begin
 if auth.uid() is null then return '[]'::jsonb; end if;
 select array_agg(x.event_id order by x.sort_at, x.event_id) into v_ids from (
  select r.event_id, greatest(r.starts_at, now()) as sort_at from (
   select distinct on (v.target_kind, v.target_id, case when v.target_kind = 'place' then lower(btrim(v.title)) else v.event_id::text end)
    v.event_id, v.starts_at
   from private.followed_events v where v.user_id = auth.uid()
   order by v.target_kind, v.target_id, case when v.target_kind = 'place' then lower(btrim(v.title)) else v.event_id::text end,
    v.starts_at, v.event_id) r
  order by greatest(r.starts_at, now()), r.event_id
  limit least(greatest(coalesce(p_limit, 20), 1), 50)) x;
 return private.event_cards(coalesce(v_ids, '{}'::uuid[]));
end $$;

create function public.follow(p_kind text, p_target uuid) returns void
language sql set search_path='' as $$ select private.follow(p_kind, p_target); $$;
create function public.unfollow(p_kind text, p_target uuid) returns void
language sql set search_path='' as $$ select private.unfollow(p_kind, p_target); $$;
create function public.my_follows() returns jsonb
language sql stable set search_path='' as $$ select private.my_follows(); $$;
create function public.follow_events(p_limit integer default 20) returns jsonb
language sql stable set search_path='' as $$ select private.follow_events(p_limit); $$;

revoke all on function private.follow(text,uuid), private.unfollow(text,uuid), private.my_follows(), private.follow_events(integer),
 public.follow(text,uuid), public.unfollow(text,uuid), public.my_follows(), public.follow_events(integer) from public, anon, authenticated;
grant execute on function private.follow(text,uuid), private.unfollow(text,uuid), private.my_follows(), private.follow_events(integer),
 public.follow(text,uuid), public.unfollow(text,uuid), public.my_follows(), public.follow_events(integer) to authenticated;

-- ---- Організатор: нова спільнотна подія → пуш підписникам одразу. Супутник «Йдемо разом» — ні:
-- він не оголошення організатора, а прохання про компанію. Хто отримує й що — вирішує функція `push`.
create function private.on_event_published() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.notify_push(jsonb_build_object('type','follow','kind','organizer','event_id',new.id));
 return new;
end $$;
create trigger events_follow_push after insert on public.events
 for each row when (new.origin = 'community' and new.status = 'published' and new.companion_of is null)
 execute function private.on_event_published();
revoke all on function private.on_event_published() from public, anon, authenticated;

-- ---- Заклади: один пуш на людину зі всього нового. Повертає, скільком людям його поставлено.
-- Нове = з'явилось після підписки, ще не скінчилось і людині про нього ще не казали. Ліміт — раз на 24 години:
-- що не влізло, лишається «новим» і їде наступним прогоном. Людина без токена не витрачає ні ліміт, ні «нове»:
-- воно чекатиме на пристрій. Без адреси функції `push` (Vault) нічого не робимо з тієї ж причини: пуш нікуди не піде.
-- Правила дзеркалить FollowRules (core/domain), текст пуша складає функція `push`.
create function private.notify_place_follows() returns integer
language plpgsql security definer set search_path='' as $$
declare v_row record; v_sent integer := 0;
begin
 if (select e.url from private.push_endpoint() e) is null then return 0; end if;
 -- Годинний прогін і кінець дампу можуть збігтися: другий чекає й бачить уже записані мітки.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('notify_place_follows', 0));
 delete from private.follow_announced a using public.events e where e.id = a.event_id and e.ends_at < now() - interval '2 days';
 for v_row in
  with due as (
   select v.user_id, v.place_id, v.event_id, v.starts_at, lower(btrim(v.title)) as run
   from private.followed_events v
   left join private.follow_pushes p on p.user_id = v.user_id
   where v.target_kind = 'place' and v.event_created_at > v.followed_at
    and (p.sent_at is null or p.sent_at <= now() - interval '24 hours')
    and not exists (select 1 from private.follow_announced a where a.user_id = v.user_id and a.event_id = v.event_id)
    and exists (select 1 from public.push_tokens t where t.user_id = v.user_id)
  ), runs as (
   -- Прокат із кількох сеансів — одна подія.
   select distinct on (d.user_id, d.place_id, d.run) d.user_id, d.place_id, d.event_id, d.starts_at
   from due d order by d.user_id, d.place_id, d.run, d.starts_at, d.event_id
  ), by_place as (
   select u.user_id, u.place_id, count(*)::integer as n, min(u.starts_at) as first_at
   from runs u group by u.user_id, u.place_id
  )
  select g.user_id, count(*)::integer as total,
   (select count(*)::integer from by_place b where b.user_id = g.user_id) as place_count,
   (select jsonb_agg(jsonb_build_object('id', x.place_id, 'n', x.n) order by x.n desc, x.first_at, x.place_id)
    from (select b.* from by_place b where b.user_id = g.user_id order by b.n desc, b.first_at, b.place_id limit 5) x) as places,
   (select jsonb_agg(y.event_id order by y.starts_at, y.event_id)
    from (select r.* from runs r where r.user_id = g.user_id order by r.starts_at, r.event_id limit 3) y) as event_ids,
   -- Усе, що ввійшло в пуш, а не лише названі події: сеанси прокату теж «сказані».
   (select array_agg(d.event_id) from due d where d.user_id = g.user_id) as seen
  from runs g group by g.user_id
 loop
  insert into private.follow_pushes (user_id, sent_at) values (v_row.user_id, now())
   on conflict (user_id) do update set sent_at = excluded.sent_at;
  insert into private.follow_announced (user_id, event_id) select v_row.user_id, s from unnest(v_row.seen) s on conflict do nothing;
  perform private.notify_push(jsonb_build_object('type','follow','kind','place','user_id',v_row.user_id,
   'total',v_row.total,'place_count',v_row.place_count,'places',v_row.places,'event_ids',v_row.event_ids));
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $$;
revoke all on function private.notify_place_follows() from public, anon, authenticated;

-- Раз на годину, коли на проєкті є pg_cron: він доставляє те, що вчора не влізло в ліміт. Без нього
-- лишається виклик у кінці дампу конвеєра (tools/ingest/emit.py). Вмикається у Dashboard → Database → Extensions.
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('notify-place-follows', '7 * * * *', 'select private.notify_place_follows()')$cron$;
 end if;
end $$;

-- ---- Копія своїх даних: плюс підписки (тіло — з 20260923100000, додано один рядок).
create or replace function public.export_my_data() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'exported_at', now(),
  'email', (select u.email from auth.users u where u.id=auth.uid()),
  'profile', (select to_jsonb(p) from public.profiles p where p.id=auth.uid()),
  'account', (select to_jsonb(a) - 'status_note' from public.account_facts a where a.user_id=auth.uid()),
  'preferences', (select to_jsonb(u) from public.user_preferences u where u.user_id=auth.uid()),
  'events', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from public.events e where e.organizer_id=auth.uid()),
  'memberships', (select coalesce(jsonb_agg(to_jsonb(m)), '[]') from public.event_members m where m.user_id=auth.uid()),
  'saved', (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from public.saved_events s where s.user_id=auth.uid()),
  'waitlist', (select coalesce(jsonb_agg(to_jsonb(w)), '[]') from public.event_waitlist w where w.user_id=auth.uid()),
  'follows', (select coalesce(jsonb_agg(to_jsonb(f)), '[]') from public.follows f where f.user_id=auth.uid()),
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

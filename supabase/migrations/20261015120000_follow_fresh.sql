-- «Ви стежите»: скільки нових подій у тих, за ким стежать, ще не переглянуто (docs/follows.md).
--
-- Нове — з'явилось після підписки (як у пуші) і ще не було в списку, коли людина востаннє відкривала екран
-- «Ви стежите». Пам'ятаємо самі події, а не мітку часу відкриття: `created_at` — початок транзакції імпорту, а видно
-- рядок з коміту, тож подія довгого дампу, вставлена «до» відкриття, загубилась би (так само `follow_announced`).
-- Рахуємо так само, як `upcoming`: заклад — назви, артист — пари (назва, місце), організатор — події.

create table private.follow_seen (
 user_id uuid not null references public.profiles(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 primary key (user_id, event_id)
);
revoke all on private.follow_seen from public, anon, authenticated;

-- Лічильник стартує з релізу: те, що вже є в підписках, людина бачила в стрічці й пушах, і «12 нових» за два тижні
-- були б неправдою.
insert into private.follow_seen (user_id, event_id)
select distinct v.user_id, v.event_id from private.followed_events v on conflict do nothing;

create or replace function private.follows_seen() returns void
language sql security definer set search_path='' as $$
 -- Скінчилась подія — рядок зайвий: нею вона вже не стане. Чистимо за всіх, як `follow_announced`.
 delete from private.follow_seen s using public.events e where e.id = s.event_id and e.ends_at < now() - interval '2 days';
 insert into private.follow_seen (user_id, event_id)
 select distinct auth.uid(), v.event_id from private.followed_events v where v.user_id = auth.uid()
 on conflict do nothing;
$$;

create function public.follows_seen() returns void
language sql set search_path='' as $$ select private.follows_seen(); $$;

revoke all on function private.follows_seen(), public.follows_seen() from public, anon, authenticated;
grant execute on function private.follows_seen(), public.follows_seen() to authenticated;

-- Те саме, що в 20261008120000_series_counts.sql, плюс `fresh`. Нуль не віддаємо: клієнт за замовчуванням має 0.
create or replace function private.my_follows()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(t.item order by t.since desc, t.name), '[]'::jsonb) from (
  select f.created_at as since, p.name,
   jsonb_strip_nulls(jsonb_build_object('kind','place','id',p.id,'name',p.name,'city',p.city,'address',p.address,
    'latitude',p.latitude,'longitude',p.longitude,'since',f.created_at,
    'upcoming',(select count(distinct lower(btrim(v.title)))::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'place' and v.target_id = p.id),
    'fresh',nullif((select count(distinct lower(btrim(v.title)))::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'place' and v.target_id = p.id
                 and v.event_created_at > v.followed_at
                 and not exists (select 1 from private.follow_seen s where s.user_id = v.user_id and s.event_id = v.event_id)), 0))) as item
  from public.follows f join public.places p on p.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'place'
  union all
  select f.created_at, pr.display_name,
   jsonb_strip_nulls(jsonb_build_object('kind','organizer','id',pr.id,'name',pr.display_name,'avatar_url',pr.avatar_url,
    'since',f.created_at,
    'upcoming',(select count(*)::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'organizer' and v.target_id = pr.id),
    'fresh',nullif((select count(*)::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'organizer' and v.target_id = pr.id
                 and v.event_created_at > v.followed_at
                 and not exists (select 1 from private.follow_seen s where s.user_id = v.user_id and s.event_id = v.event_id)), 0)))
  from public.follows f join public.profiles pr on pr.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'organizer'
   and private.account_active(pr.id) and not private.blocked_between(f.user_id, pr.id)
  union all
  select f.created_at, a.name,
   jsonb_strip_nulls(jsonb_build_object('kind','artist','id',a.id,'name',a.name,'artist_kind',a.kind,
    'since',f.created_at,
    'upcoming',(select count(distinct (lower(btrim(v.title)), coalesce(v.place_id::text, '')))::integer
                from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'artist' and v.target_id = a.id),
    'fresh',nullif((select count(distinct (lower(btrim(v.title)), coalesce(v.place_id::text, '')))::integer
                from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'artist' and v.target_id = a.id
                 and v.event_created_at > v.followed_at
                 and not exists (select 1 from private.follow_seen s where s.user_id = v.user_id and s.event_id = v.event_id)), 0)))
  from public.follows f join public.artists a on a.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'artist'
 ) t;
$$;

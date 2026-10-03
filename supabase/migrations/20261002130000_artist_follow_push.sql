-- Пуш підписникам артистів: один пуш на людину зі всього нового (20261002120000_artists.sql, зразок —
-- notify_place_follows у 20260928160000_follows.sql).
--
-- Спільний ліміт із закладами: `private.follow_pushes` одна на людину, раз на 24 години, тож стежити за
-- артистом і за закладом не означає два пуші на добу. Артист іде першим: це особистіша підписка, а що не
-- влізло, лишається «новим» і їде наступним прогоном. Подію, про яку вже сказали, заклад вдруге не оголошує:
-- `private.follow_announced` ключується подією, а не підпискою.
--
-- «Нове» — подія з'явилась після підписки й людині про неї ще не казали. Артиста могли приписати старій події
-- вже після підписки (дозаповнення моделлю): `event_created_at` тоді давніший за підписку, і пуша не буде.
--
-- РОЗГОРТАННЯ: спершу функція `push` (вона вчить новий тип `follow/artist`), потім ця міграція. Функція базі
-- записує подію «оголошеною» ще до виклику `push`: невідомий тип дав би 400, а подія пропала б назавжди.

create function private.notify_artist_follows() returns integer
language plpgsql security definer set search_path='' as $$
declare v_row record; v_sent integer := 0;
begin
 if (select e.url from private.push_endpoint() e) is null then return 0; end if;
 -- Той самий замок, що в notify_place_follows: обидва читають і пишуть одну таблицю ліміту.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('notify_place_follows', 0));
 for v_row in
  with due as (
   select v.user_id, v.target_id as artist_id, v.event_id, v.starts_at, lower(btrim(v.title)) as run
   from private.followed_events v
   left join private.follow_pushes p on p.user_id = v.user_id
   where v.target_kind = 'artist' and v.event_created_at > v.followed_at
    and (p.sent_at is null or p.sent_at <= now() - interval '24 hours')
    and not exists (select 1 from private.follow_announced a where a.user_id = v.user_id and a.event_id = v.event_id)
    and exists (select 1 from public.push_tokens t where t.user_id = v.user_id)
  ), runs as (
   -- Прокат із кількох сеансів одного артиста — одна подія.
   select distinct on (d.user_id, d.artist_id, d.run) d.user_id, d.artist_id, d.event_id, d.starts_at, d.run
   from due d order by d.user_id, d.artist_id, d.run, d.starts_at, d.event_id
  ), by_artist as (
   select u.user_id, u.artist_id, count(*)::integer as n, min(u.starts_at) as first_at
   from runs u group by u.user_id, u.artist_id
  ), shows as (
   -- Подія з двома артистами, за якими стежать, одна: рахуємо за назвою, не за парою.
   select distinct on (r.user_id, r.run) r.user_id, r.event_id, r.starts_at
   from runs r order by r.user_id, r.run, r.starts_at, r.event_id
  )
  select g.user_id, count(*)::integer as total,
   (select count(*)::integer from by_artist b where b.user_id = g.user_id) as artist_count,
   (select jsonb_agg(jsonb_build_object('id', x.artist_id, 'n', x.n) order by x.n desc, x.first_at, x.artist_id)
    from (select b.* from by_artist b where b.user_id = g.user_id order by b.n desc, b.first_at, b.artist_id limit 5) x) as artists,
   (select jsonb_agg(y.event_id order by y.starts_at, y.event_id)
    from (select s.* from shows s where s.user_id = g.user_id order by s.starts_at, s.event_id limit 3) y) as event_ids,
   (select array_agg(d.event_id) from due d where d.user_id = g.user_id) as seen
  from shows g group by g.user_id
 loop
  insert into private.follow_pushes (user_id, sent_at) values (v_row.user_id, now())
   on conflict (user_id) do update set sent_at = excluded.sent_at;
  insert into private.follow_announced (user_id, event_id) select v_row.user_id, s from unnest(v_row.seen) s on conflict do nothing;
  perform private.notify_push(jsonb_build_object('type','follow','kind','artist','user_id',v_row.user_id,
   'total',v_row.total,'artist_count',v_row.artist_count,'artists',v_row.artists,'event_ids',v_row.event_ids));
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $$;
revoke all on function private.notify_artist_follows() from public, anon, authenticated;

-- Раз на годину, за п'ять хвилин до закладів: при ліміті раз на добу артист забирає слот першим.
do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('notify-artist-follows', '2 * * * *', 'select private.notify_artist_follows()')$cron$;
 end if;
end $$;

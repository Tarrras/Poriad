-- Аудит 2026-09-23, «Низько → Бекенд»: хто кого бачить, чужі URL, стоп-словник на імені й адресі,
-- лістинг бакета, підміна фото, блокування учасника, індекси на FK, план my_chat_unread.

-- 1. Профілі. Було USING(true): будь-хто після реєстрації перелічував усіх. Тепер — лише ті, з ким
-- є спільна подія. Список збігається з тим, що читають invoker-функції й клієнт:
--  сам себе; кого я заблокував (екран «Заблоковані» читає /rest/v1/profiles?id=in.(…));
--  учасники й запити моїх подій (event_attendees, event_requests, my_join_requests) та автори в їхніх чатах;
--  у подіях, де я учасник, — організатор, підтверджені учасники й автори чату (event_messages, my_chat_unread).
-- Імена організаторів для мапи й карток віддають definer-проєкції (event_rows, event_cards) — їх це не зачіпає.
create or replace function private.can_see_profile(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
  p_id = auth.uid()
  or exists(select 1 from public.user_blocks b where b.user_id=auth.uid() and b.blocked_id=p_id)
  or exists(select 1 from public.event_members m join public.events e on e.id=m.event_id
            where m.user_id=p_id and e.organizer_id=auth.uid())
  or exists(select 1 from public.event_messages x join public.events e on e.id=x.event_id
            where x.author_id=p_id and e.organizer_id=auth.uid())
  or exists(select 1 from public.event_members me where me.user_id=auth.uid() and (
      exists(select 1 from public.events e where e.id=me.event_id and e.organizer_id=p_id)
      or (me.status='approved' and (
       exists(select 1 from public.event_members o where o.event_id=me.event_id and o.user_id=p_id and o.status='approved')
       or exists(select 1 from public.event_messages x where x.event_id=me.event_id and x.author_id=p_id))))));
$$;
revoke all on function private.can_see_profile(uuid) from public, anon, authenticated;
grant execute on function private.can_see_profile(uuid) to authenticated;
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (private.can_see_profile(id));

-- 2. URL зображень — лише з бакета event-images власного проєкту. Проєкт беремо з iss токена
-- (https://<ref>.supabase.co/auth/v1): так dev і prod перевіряють кожен себе без захардкодженого ref.
-- Без JWT (SQL-консоль, service role) — запасний шаблон *.supabase.co; клієнтські виклики завжди з JWT.
create or replace function private.image_url_prefix() returns text
language sql stable set search_path='' as $$
 select '^' || coalesce(
  replace(substring(auth.jwt()->>'iss' from '^(https://[a-z0-9-]+\.supabase\.co)/auth/v1$'), '.', '\.'),
  'https://[a-z0-9-]+\.supabase\.co') || '/storage/v1/object/public/event-images/';
$$;
revoke all on function private.image_url_prefix() from public, anon, authenticated;

create or replace function private.assert_image_url(p_url text, p_user uuid, p_event uuid) returns void
language plpgsql stable set search_path='' as $$
begin
 if p_url is null then return; end if;
 if p_url !~ (private.image_url_prefix() || p_user::text || '/' || p_event::text || '/[^/?#[:space:]]+$') then
  raise exception 'INVALID_IMAGE_URL' using errcode='22023'; end if;
end $$;
revoke all on function private.assert_image_url(text,uuid,uuid) from public, anon, authenticated;

-- 3. Профіль пишеться клієнтом напряму (грант UPDATE на display_name, avatar_url), тож перевірка —
-- тригером. Ім'я йде в пуші й чат: стоп-словник. При реєстрації погане ім'я не валить signup,
-- а стає «Учасник». Аватар — лише файл власника у своєму бакеті: чужий https був трекінг-пікселем.
create or replace function private.on_profile_write() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  begin perform private.assert_clean_text(new.display_name);
  exception when sqlstate '22023' then new.display_name := 'Учасник'; end;
 elsif new.display_name is distinct from old.display_name then
  perform private.assert_clean_text(new.display_name);
 end if;
 if new.avatar_url is not null and (tg_op='INSERT' or new.avatar_url is distinct from old.avatar_url)
  and new.avatar_url !~ (private.image_url_prefix() || new.id::text || '/[^?#[:space:]]+$') then
  raise exception 'INVALID_IMAGE_URL' using errcode='22023'; end if;
 return new;
end $$;
revoke all on function private.on_profile_write() from public, anon, authenticated;
drop trigger if exists profiles_validate on public.profiles;
create trigger profiles_validate before insert or update of display_name, avatar_url on public.profiles
 for each row execute function private.on_profile_write();

-- 4. Storage. Публічний бакет віддає файл за /object/public/… без жодної політики SELECT; політика
-- лише давала anon перелічити всі файли всіх користувачів. Клієнт list не використовує.
-- UPDATE (upsert) дозволяв підмінити фото вже після модерації; клієнт завантажує лише POST без x-upsert.
drop policy if exists poruch_image_read on storage.objects;
drop policy if exists poruch_image_update on storage.objects;

-- 5. Організатор блокує учасника → учасник виходить з поточних і майбутніх подій організатора
-- (членство, запит, черга). Інакше заблокований далі читав би чат і ростер через can_view_members.
create or replace function private.on_user_blocked() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_event uuid;
begin
 for v_event in
  select e.id from public.events e where e.organizer_id=new.user_id and e.ends_at > now()
  and (exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=new.blocked_id)
    or exists(select 1 from public.event_waitlist w where w.event_id=e.id and w.user_id=new.blocked_id))
  order by e.id
 loop
  -- Той самий замок, що в join/leave: місткість і черга змінюються разом.
  perform 1 from public.events where id=v_event for update;
  delete from public.event_members where event_id=v_event and user_id=new.blocked_id;
  delete from public.event_waitlist where event_id=v_event and user_id=new.blocked_id;
  perform private.promote_waitlist(v_event);
 end loop;
 return new;
end $$;
revoke all on function private.on_user_blocked() from public, anon, authenticated;
drop trigger if exists user_blocks_evict on public.user_blocks;
create trigger user_blocks_evict after insert on public.user_blocks
 for each row execute function private.on_user_blocked();

-- Одноразово для вже наявних блокувань (без просування черги — воно станеться на наступному leave/update).
delete from public.event_members m using public.events e, public.user_blocks b
 where e.id=m.event_id and b.user_id=e.organizer_id and b.blocked_id=m.user_id and e.ends_at > now();
delete from public.event_waitlist w using public.events e, public.user_blocks b
 where e.id=w.event_id and b.user_id=e.organizer_id and b.blocked_id=w.user_id and e.ends_at > now();

-- 6. Індекси на FK: каскади видалення акаунта / події інакше сканують таблиці цілком.
create index if not exists reports_event_idx on public.reports(event_id);
create index if not exists reports_subject_user_idx on public.reports(subject_user_id);
create index if not exists reports_message_idx on public.reports(message_id);
create index if not exists event_waitlist_user_idx on public.event_waitlist(user_id);
create index if not exists chat_reads_event_idx on public.chat_reads(event_id);

-- 7. my_chat_unread стартує від моїх подій (індекси events_organizer_idx і event_members_user_idx),
-- а не від усіх подій тижня: на проді старий план — Seq Scan по events з RLS на кожен рядок.
create or replace function public.my_chat_unread() returns setof public.chat_unread_result
language sql stable security invoker set search_path='' as $$
 with mine as (
  select e.id, e.title from public.events e
  where e.organizer_id=auth.uid() and e.status='published' and e.ends_at > now()-interval '7 days'
  union
  select e.id, e.title from public.event_members mm join public.events e on e.id=mm.event_id
  where mm.user_id=auth.uid() and mm.status='approved' and e.status='published' and e.ends_at > now()-interval '7 days'
 )
 select e.id,e.title,u.unread,l.id,l.author_name,l.body,l.created_at
 from mine e
 left join public.chat_reads r on r.event_id=e.id and r.user_id=auth.uid()
 cross join lateral (
  select count(*)::integer as unread from public.event_messages m
  where m.event_id=e.id and m.author_id<>auth.uid() and m.created_at > coalesce(r.read_at,'-infinity'::timestamptz)
 ) u
 cross join lateral (
  select m.id,p.display_name as author_name,m.body,m.created_at
  from public.event_messages m join public.profiles p on p.id=m.author_id
  where m.event_id=e.id and m.author_id<>auth.uid()
  order by m.created_at desc,m.id desc limit 1
 ) l
 where auth.uid() is not null and u.unread>0
 order by l.created_at desc;
$$;

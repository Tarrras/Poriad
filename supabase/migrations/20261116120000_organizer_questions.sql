-- «Запитати організатора» (1.4): розмова на двох біля події від людей — той, хто питає, і організатор.
-- Людина ще вирішує, чи йти: у загальний чат (лише свої, can_view_members) її не пускає, а питати при всіх і не
-- хочеться. Розмова — ті самі повідомлення чату з `thread_user_id` = хто питає: той самий екран, ліміти, видалення,
-- скарга й блокування. Загальний чат — повідомлення з `thread_user_id is null`, і старі збірки бачать лише його.
-- Організатор першим не пише: відповідає в розмову, яку відкрив той, хто питає, — це не дірект поза подією.
-- ponytail: організатор на збірці до 1.4 питань не побачить (Android мовчки пропускає невідомий пуш, iOS покаже
-- текст, але відповісти нема де); подій від людей на prod 30.10 — 4. Стане багато — ховати кнопку, поки в
-- організатора нема токена з `questions` у push_tokens.features.

alter table public.event_messages add column thread_user_id uuid references public.profiles(id) on delete cascade;
create index event_messages_thread_idx on public.event_messages(event_id,thread_user_id,created_at) where thread_user_id is not null;
comment on column public.event_messages.thread_user_id is 'Розмова з організатором: хто питає. Null — загальний чат події.';

create function private.organizes(p_event_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.events e where e.id=p_event_id and e.organizer_id=auth.uid());
$$;
revoke all on function private.organizes(uuid) from public,anon,authenticated;
grant execute on function private.organizes(uuid) to authenticated;

-- ---- Читання: загальний чат — своїм людям події, розмова — лише двом.
drop policy if exists messages_read on public.event_messages;
create policy messages_read on public.event_messages for select to authenticated using (
 deleted_at is null and hidden_at is null
 and (case when thread_user_id is null then private.can_view_members(event_id)
      else (thread_user_id=(select auth.uid()) or private.organizes(event_id)) end)
 and (author_id = (select auth.uid()) or (private.account_active(author_id) and not private.blocked_between((select auth.uid()), author_id)))
);

-- Профілі: хто спитав, бачить організатора (інакше стрічка, що зʼєднує автора з profiles, губила б відповіді), а
-- учасники не бачать тих, хто лише питав, — з розмови, як і з чату, вони не автори «своєї» події.
create or replace function private.can_see_profile(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
  p_id = auth.uid()
  or exists(select 1 from public.user_blocks b where b.user_id=auth.uid() and b.blocked_id=p_id)
  or exists(select 1 from public.event_members m join public.events e on e.id=m.event_id
            where m.user_id=p_id and e.organizer_id=auth.uid())
  or exists(select 1 from public.event_messages x join public.events e on e.id=x.event_id
            where x.author_id=p_id and e.organizer_id=auth.uid())
  or exists(select 1 from public.event_messages x join public.events e on e.id=x.event_id
            where x.thread_user_id=auth.uid() and e.organizer_id=p_id)
  or exists(select 1 from public.event_members me where me.user_id=auth.uid() and (
      exists(select 1 from public.events e where e.id=me.event_id and e.organizer_id=p_id)
      or (me.status='approved' and (
       exists(select 1 from public.event_members o where o.event_id=me.event_id and o.user_id=p_id and o.status='approved')
       or exists(select 1 from public.event_messages x where x.event_id=me.event_id and x.author_id=p_id and x.thread_user_id is null))))));
$$;

-- ---- Стрічка: загальний чат або розмова [p_thread]. Старі збірки шлють три параметри — отримують загальний.
drop function public.event_messages(uuid,timestamptz,integer);
create function public.event_messages(p_event_id uuid,p_after timestamptz default null,p_limit integer default 100,p_thread uuid default null)
 returns setof public.message_result language sql stable security invoker set search_path='' as $$
 select * from (
  select m.id,m.event_id,m.author_id,p.display_name,p.avatar_url,m.body,m.created_at
  from public.event_messages m join public.profiles p on p.id=m.author_id
  where m.event_id=p_event_id and m.thread_user_id is not distinct from p_thread and (p_after is null or m.created_at > p_after)
  order by m.created_at desc,m.id desc limit greatest(1,least(coalesce(p_limit,100),200))
 ) tail order by created_at,id;
$$;

-- ---- Запис. Розмова: питає будь-хто з акаунтом, крім організатора; організатор лише відповідає в наявну.
drop function public.send_message(uuid,text);
drop function private.send_message(uuid,text);
create function private.send_message(p_event_id uuid, p_body text, p_thread uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_body text := btrim(p_body); v_id uuid;
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
  if v_user = v_event.organizer_id and not exists(
   select 1 from public.event_messages m where m.event_id=p_event_id and m.thread_user_id=p_thread and m.author_id=p_thread) then
   raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 -- Тиждень після кінця — щоб домовитись про фото й речі; далі чат закривається.
 if v_event.ends_at < now() - interval '7 days' then raise exception 'CHAT_CLOSED' using errcode='P0001'; end if;
 -- Двадцять на хвилину — розмова; більше — скрипт. Видалені й розмови теж рахуються.
 if (select count(*) from public.event_messages where author_id=v_user and created_at > now()-interval '1 minute') >= 20 then
  raise exception 'TOO_MANY_MESSAGES' using errcode='P0001'; end if;
 insert into public.event_messages(event_id,author_id,body,thread_user_id) values (p_event_id,v_user,v_body,p_thread) returning id into v_id;
 return v_id;
end $$;
create function public.send_message(p_event_id uuid,p_body text,p_thread uuid default null) returns uuid language sql security invoker set search_path='' as $$
 select private.send_message(p_event_id,p_body,p_thread);
$$;

-- ---- Прочитане в розмовах: окремо від chat_reads, ключ якої — подія.
create table public.question_reads (
 user_id uuid not null references public.profiles(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 thread_user_id uuid not null references public.profiles(id) on delete cascade,
 read_at timestamptz not null default now(),
 primary key (user_id,event_id,thread_user_id)
);
alter table public.question_reads enable row level security;
create policy question_reads_own on public.question_reads for select to authenticated using (user_id=(select auth.uid()));
revoke all on table public.question_reads from public,anon,authenticated;
grant select on table public.question_reads to authenticated;

drop function public.mark_chat_read(uuid);
drop function private.mark_chat_read(uuid);
create function private.mark_chat_read(p_event_id uuid, p_thread uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_thread is null then
  if not private.can_view_members(p_event_id) then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
  insert into public.chat_reads(user_id,event_id,read_at) values (v_user,p_event_id,now())
  on conflict (user_id,event_id) do update set read_at=excluded.read_at;
 else
  if v_user <> p_thread and not private.organizes(p_event_id) then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
  insert into public.question_reads(user_id,event_id,thread_user_id,read_at) values (v_user,p_event_id,p_thread,now())
  on conflict (user_id,event_id,thread_user_id) do update set read_at=excluded.read_at;
 end if;
end $$;
create function public.mark_chat_read(p_event_id uuid, p_thread uuid default null) returns void language sql security invoker set search_path='' as $$
 select private.mark_chat_read(p_event_id,p_thread);
$$;

-- ---- Бейдж загального чату не рахує питань: організатор їх бачить під RLS, але вони не про чат.
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
  where m.event_id=e.id and m.thread_user_id is null and m.author_id<>auth.uid() and m.created_at > coalesce(r.read_at,'-infinity'::timestamptz)
 ) u
 cross join lateral (
  select m.id,p.display_name as author_name,m.body,m.created_at
  from public.event_messages m join public.profiles p on p.id=m.author_id
  where m.event_id=e.id and m.thread_user_id is null and m.author_id<>auth.uid()
  order by m.created_at desc,m.id desc limit 1
 ) l
 where auth.uid() is not null and u.unread>0
 order by l.created_at desc;
$$;

-- ---- Розмови події: організатору — усі, тому, хто питав, — своя. Свіжіші першими, з непрочитаним.
-- Invoker: що кому видно, вирішує RLS повідомлень і профілів.
create type public.question_result as (
 thread_user_id uuid,asker_name text,asker_avatar text,last_body text,last_at timestamptz,last_mine boolean,unread integer
);
create function public.event_questions(p_event_id uuid) returns setof public.question_result
language sql stable security invoker set search_path='' as $$
 select t.thread_user_id,p.display_name,p.avatar_url,l.body,l.created_at,l.author_id=auth.uid(),u.unread
 from (select distinct m.thread_user_id from public.event_messages m where m.event_id=p_event_id and m.thread_user_id is not null) t
 join public.profiles p on p.id=t.thread_user_id
 left join public.question_reads r on r.user_id=auth.uid() and r.event_id=p_event_id and r.thread_user_id=t.thread_user_id
 cross join lateral (
  select m.body,m.created_at,m.author_id from public.event_messages m
  where m.event_id=p_event_id and m.thread_user_id=t.thread_user_id
  order by m.created_at desc,m.id desc limit 1
 ) l
 cross join lateral (
  select count(*)::integer as unread from public.event_messages m
  where m.event_id=p_event_id and m.thread_user_id=t.thread_user_id and m.author_id<>auth.uid()
  and m.created_at > coalesce(r.read_at,'-infinity'::timestamptz)
 ) u
 where auth.uid() is not null
 order by l.created_at desc;
$$;

revoke all on function public.event_messages(uuid,timestamptz,integer,uuid),private.send_message(uuid,text,uuid),public.send_message(uuid,text,uuid),
 private.mark_chat_read(uuid,uuid),public.mark_chat_read(uuid,uuid),public.event_questions(uuid) from public,anon,authenticated;
grant execute on function public.event_messages(uuid,timestamptz,integer,uuid),private.send_message(uuid,text,uuid),public.send_message(uuid,text,uuid),
 private.mark_chat_read(uuid,uuid),public.mark_chat_read(uuid,uuid),public.event_questions(uuid) to authenticated;

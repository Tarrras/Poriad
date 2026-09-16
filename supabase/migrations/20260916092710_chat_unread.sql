-- Непрочитане в чатах. Клієнт без пушів дізнається про нове лише коли перечитує сервер, тож
-- рахуємо на сервері: «до якого моменту прочитано» на акаунт і подію, а решта — непрочитане.

create table public.chat_reads (
 user_id uuid not null references public.profiles(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 read_at timestamptz not null default now(),
 primary key (user_id,event_id)
);
alter table public.chat_reads enable row level security;
create policy chat_reads_own on public.chat_reads for select to authenticated using (user_id=(select auth.uid()));
revoke all on table public.chat_reads from public,anon,authenticated;
grant select on table public.chat_reads to authenticated;

-- Прочитано до зараз. Definer, бо клієнти таблицю не пишуть; свої люди події — те саме правило, що для чату.
create function private.mark_chat_read(p_event_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.can_view_members(p_event_id) then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 insert into public.chat_reads(user_id,event_id,read_at) values (v_user,p_event_id,now())
 on conflict (user_id,event_id) do update set read_at=excluded.read_at;
end $$;
create function public.mark_chat_read(p_event_id uuid) returns void language sql security invoker set search_path='' as $$
 select private.mark_chat_read(p_event_id);
$$;

-- ---- Зведення: події з непрочитаним, свіжіші першими, з останнім чужим повідомленням для прев'ю.

create type public.chat_unread_result as (
 event_id uuid,event_title text,unread integer,
 last_message_id uuid,last_author_name text,last_body text,last_at timestamptz
);

-- Invoker: `event_messages` під RLS, тож заблоковані й обмежені автори не рахуються, як і в чаті.
-- Лише опубліковані події до тижня після кінця — поки чат відкритий на запис.
create function public.my_chat_unread() returns setof public.chat_unread_result language sql stable security invoker set search_path='' as $$
 select e.id,e.title,u.unread,l.id,l.author_name,l.body,l.created_at
 from public.events e
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
 where auth.uid() is not null and e.status='published' and e.ends_at > now()-interval '7 days'
 and (e.organizer_id=auth.uid()
      or exists(select 1 from public.event_members mm where mm.event_id=e.id and mm.user_id=auth.uid() and mm.status='approved'))
 and u.unread>0
 order by l.created_at desc;
$$;

revoke all on function private.mark_chat_read(uuid),public.mark_chat_read(uuid),public.my_chat_unread() from public,anon,authenticated;
grant execute on function private.mark_chat_read(uuid),public.mark_chat_read(uuid),public.my_chat_unread() to authenticated;

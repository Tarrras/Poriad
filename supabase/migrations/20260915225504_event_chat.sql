-- Чат події: організатор і підтверджені учасники пишуть одне одному всередині застосунку.
-- Без реального часу: клієнт перечитує хвіст, поки екран відкритий. Схема цього не знає, тож
-- Realtime можна додати пізніше без міграції.
--
-- Хто читає й пише — вирішує `private.can_view_members`, те саме правило, що для ростера.
-- Заблоковані одне одним не бачать повідомлень одне одного, як не бачать і подій.

create table public.event_messages (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.events(id) on delete cascade,
 author_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check (char_length(body) between 1 and 2000),
 created_at timestamptz not null default now()
);
create index event_messages_event_idx on public.event_messages(event_id,created_at,id);
create index event_messages_author_idx on public.event_messages(author_id,created_at);
alter table public.event_messages enable row level security;

-- Читання під RLS: свої люди події, окрім заблокованих і обмежених авторів (власні видно завжди).
create policy messages_read on public.event_messages for select to authenticated using (
 private.can_view_members(event_id)
 and (author_id=(select auth.uid())
      or (private.account_active(author_id) and not private.blocked_between((select auth.uid()),author_id)))
);
-- Запис лише через RPC: перевірки статусу події й темпу живуть там.
revoke all on table public.event_messages from public,anon,authenticated;
grant select on table public.event_messages to authenticated;

-- ---- Проєкція

create type public.message_result as (
 id uuid,event_id uuid,author_id uuid,author_name text,avatar_url text,body text,created_at timestamptz
);

-- Хвіст чату за часом. `p_after` — для дозавантаження нового: лише те, що пізніше за відоме.
-- Без `p_after` — останні `p_limit`, у тому ж порядку (старіші вгорі).
create function public.event_messages(p_event_id uuid,p_after timestamptz default null,p_limit integer default 100)
 returns setof public.message_result language sql stable security invoker set search_path='' as $$
 select * from (
  select m.id,m.event_id,m.author_id,p.display_name,p.avatar_url,m.body,m.created_at
  from public.event_messages m join public.profiles p on p.id=m.author_id
  where m.event_id=p_event_id and (p_after is null or m.created_at > p_after)
  order by m.created_at desc,m.id desc limit greatest(1,least(coalesce(p_limit,100),200))
 ) tail order by created_at,id;
$$;

-- ---- Запис

create function private.send_message(p_event_id uuid,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_body text := btrim(p_body); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 2000 then raise exception 'INVALID_MESSAGE' using errcode='22023'; end if;
 select * into v_event from public.events where id=p_event_id;
 if not found or not private.can_view_members(p_event_id) then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 -- Запит без відповіді ще не всередині: can_view_members пускає його до ростера, але не до чату.
 if v_event.organizer_id <> v_user and not exists(
  select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=v_user and m.status='approved') then
  raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 -- Тиждень після кінця — щоб домовитись про фото й речі; далі чат закривається.
 if v_event.ends_at < now() - interval '7 days' then raise exception 'CHAT_CLOSED' using errcode='P0001'; end if;
 -- Двадцять на хвилину — розмова; більше — скрипт.
 if (select count(*) from public.event_messages where author_id=v_user and created_at > now()-interval '1 minute') >= 20 then
  raise exception 'TOO_MANY_MESSAGES' using errcode='P0001'; end if;
 insert into public.event_messages(event_id,author_id,body) values (p_event_id,v_user,v_body) returning id into v_id;
 return v_id;
end $$;

-- Автор прибирає своє, організатор — будь-що у своїй події. Чужого не існує: тиша, а не відмова.
create function private.delete_message(p_message_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 delete from public.event_messages m using public.events e
 where m.id=p_message_id and e.id=m.event_id and (m.author_id=v_user or e.organizer_id=v_user);
end $$;

create function public.send_message(p_event_id uuid,p_body text) returns uuid language sql security invoker set search_path='' as $$
 select private.send_message(p_event_id,p_body);
$$;
create function public.delete_message(p_message_id uuid) returns void language sql security invoker set search_path='' as $$
 select private.delete_message(p_message_id);
$$;

-- ---- Скарга на повідомлення: на автора, з подією і текстом, щоб модерація бачила контекст.

alter table public.reports add column message_id uuid references public.event_messages(id) on delete set null;

-- Definer лише для запису в `reports`: клієнти таблицю не пишуть. Скаржник перевіряється ще раз.
create function private.attach_report_message(p_report uuid,p_message uuid) returns void language sql security definer set search_path='' as $$
 update public.reports set message_id=p_message where id=p_report and reporter_id=auth.uid() and message_id is null;
$$;

create function public.report_message(p_message_id uuid,p_reason text,p_details text default null) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_message public.event_messages; v_id uuid;
begin
 -- Під RLS: чуже повідомлення для скаржника не існує.
 select * into v_message from public.event_messages where id=p_message_id;
 if not found then raise exception 'MESSAGE_NOT_FOUND' using errcode='P0002'; end if;
 v_id := private.file_report('user',v_message.event_id,v_message.author_id,p_reason,
  concat_ws(E'\n',nullif(btrim(p_details),''),'Повідомлення: '||left(v_message.body,500)));
 perform private.attach_report_message(v_id,p_message_id);
 return v_id;
end $$;

revoke all on function
 public.event_messages(uuid,timestamptz,integer),private.send_message(uuid,text),public.send_message(uuid,text),
 private.delete_message(uuid),public.delete_message(uuid),private.attach_report_message(uuid,uuid),public.report_message(uuid,text,text)
 from public,anon,authenticated;
grant execute on function
 public.event_messages(uuid,timestamptz,integer),private.send_message(uuid,text),public.send_message(uuid,text),
 private.delete_message(uuid),public.delete_message(uuid),private.attach_report_message(uuid,uuid),public.report_message(uuid,text,text)
 to authenticated;

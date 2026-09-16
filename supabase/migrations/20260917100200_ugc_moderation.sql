-- Аудит 2026-09-16, K5 і V2. App Store 1.2 вимагає фільтр небажаного контенту, реакцію на скарги
-- й можливість прибирати UGC; Play — те саме через UGC policy. До цього модерувати можна було лише
-- SQL-ем під service role. Тут три шари:
--  1. стоп-словник на вході (назва й опис події, повідомлення чату) — OBJECTIONABLE_CONTENT;
--  2. автоприховування: три незалежні скарги на подію чи повідомлення ховають їх до розгляду;
--  3. модератори (private.moderators) працюють через RPC зі свого акаунта: черга, приховати,
--     повернути, скасувати, обмежити акаунт, закрити скаргу.
-- Повідомлення більше не видаляються фізично (deleted_at): лічильник 20/хв рахує все, що
-- надіслано, і обхід «надіслав → видалив → надіслав» більше не працює (V2).

-- 1. Стоп-словник. Збіг — по межах слова, без урахування регістру; корені покривають відмінки.
create table if not exists private.banned_terms (
 term text primary key check (char_length(term) between 2 and 60),
 note text
);
insert into private.banned_terms(term) values
 ('хуй'),('хуя'),('хує'),('хуї'),('пизд'),('їбат'),('їбан'),('ебат'),('ебан'),('єбат'),('блядь'),('бляд'),('сука'),('суки'),('гандон'),('підар'),('пидор'),('підор'),('хохол'),('хохли'),('москал'),('жид'),('чурк'),('нігер'),('ніггер'),('nigger'),('faggot'),('fuck'),('shit'),('bitch'),('cunt'),
 ('наркот'),('гашиш'),('амфетамін'),('кокаїн'),('героїн'),('закладк'),('эскорт'),('ескорт'),('інтим за'),('интим за'),('казино онлайн'),('ставки на спорт')
on conflict do nothing;
revoke all on table private.banned_terms from public, anon, authenticated;

create or replace function private.assert_clean_text(p_text text) returns void
language plpgsql stable set search_path='' as $$
declare v_term text;
begin
 if p_text is null then return; end if;
 select t.term into v_term from private.banned_terms t
 where lower(p_text) ~ ('(^|[^[:alnum:]_])' || regexp_replace(lower(t.term), '([][(){}.*+?^$|\\])', '\\\1', 'g') || '([^[:alnum:]_]|$)')
    or (char_length(t.term) >= 4 and position(lower(t.term) in lower(p_text)) > 0)
 limit 1;
 if v_term is not null then raise exception 'OBJECTIONABLE_CONTENT' using errcode='22023'; end if;
end $$;
revoke all on function private.assert_clean_text(text) from public, anon, authenticated;

-- 2. Стан прихованого: подія — окремий статус, повідомлення — позначки часу.
alter table public.events drop constraint if exists events_status_check;
alter table public.events add constraint events_status_check check (status in ('published','cancelled','hidden'));
alter table public.event_messages add column if not exists deleted_at timestamptz;
alter table public.event_messages add column if not exists hidden_at timestamptz;

-- Читання чату: видалене й приховане не існує ні для кого, крім модерації (яка ходить через definer).
drop policy if exists messages_read on public.event_messages;
create policy messages_read on public.event_messages for select to authenticated using (
 deleted_at is null and hidden_at is null
 and private.can_view_members(event_id)
 and (author_id = (select auth.uid()) or (private.account_active(author_id) and not private.blocked_between((select auth.uid()), author_id)))
);

create or replace function private.send_message(p_event_id uuid, p_body text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_body text := btrim(p_body); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 2000 then raise exception 'INVALID_MESSAGE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_body);
 select * into v_event from public.events where id=p_event_id;
 if not found or not private.can_view_members(p_event_id) then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 -- Запит без відповіді ще не всередині: can_view_members пускає його до ростера, але не до чату.
 if v_event.organizer_id is distinct from v_user and not exists(
  select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=v_user and m.status='approved') then
  raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 -- Тиждень після кінця — щоб домовитись про фото й речі; далі чат закривається.
 if v_event.ends_at < now() - interval '7 days' then raise exception 'CHAT_CLOSED' using errcode='P0001'; end if;
 -- Двадцять на хвилину — розмова; більше — скрипт. Видалені теж рахуються.
 if (select count(*) from public.event_messages where author_id=v_user and created_at > now()-interval '1 minute') >= 20 then
  raise exception 'TOO_MANY_MESSAGES' using errcode='P0001'; end if;
 insert into public.event_messages(event_id,author_id,body) values (p_event_id,v_user,v_body) returning id into v_id;
 return v_id;
end $$;

create or replace function private.delete_message(p_message_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 update public.event_messages m set deleted_at=now() from public.events e
 where m.id=p_message_id and e.id=m.event_id and m.deleted_at is null and (m.author_id=v_user or e.organizer_id=v_user);
end $$;

-- 3. Автоприховування: три різні скаржники на одну подію або одне повідомлення — ховаємо до розгляду.
create or replace function private.on_report_filed() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
 if new.subject_type='event' and new.event_id is not null then
  select count(distinct reporter_id) into v_count from public.reports
   where subject_type='event' and event_id=new.event_id and status in ('new','reviewing');
  if v_count >= 3 then
   update public.events set status='hidden', updated_at=now() where id=new.event_id and status='published';
  end if;
 elsif new.message_id is not null then
  select count(distinct reporter_id) into v_count from public.reports
   where message_id=new.message_id and status in ('new','reviewing');
  if v_count >= 3 then
   update public.event_messages set hidden_at=now() where id=new.message_id and hidden_at is null;
  end if;
 end if;
 return new;
end $$;
drop trigger if exists reports_auto_hide on public.reports;
create trigger reports_auto_hide after insert or update of message_id on public.reports
 for each row execute function private.on_report_filed();

-- 4. Модератори. Таблиця без грантів: керується лише з SQL-консолі, як і має бути для ролей.
create table if not exists private.moderators (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 added_at timestamptz not null default now()
);
revoke all on table private.moderators from public, anon, authenticated;

create or replace function private.assert_moderator() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not exists(select 1 from private.moderators m where m.user_id=v_user) then raise exception 'NOT_MODERATOR' using errcode='42501'; end if;
 return v_user;
end $$;
revoke all on function private.assert_moderator() from public, anon, authenticated;

-- Черга: відкриті скарги з контекстом, свіжіші першими.
drop type if exists public.moderation_item cascade;
create type public.moderation_item as (
 report_id uuid, created_at timestamptz, status text, reason text, details text, subject_type text,
 reporter_name text, event_id uuid, event_title text, event_status text,
 subject_user_id uuid, subject_user_name text, subject_user_status text,
 message_id uuid, message_body text, message_hidden boolean
);
create or replace function public.moderation_queue(p_limit integer default 50) returns setof public.moderation_item
language plpgsql stable security definer set search_path='' as $$
begin
 perform private.assert_moderator();
 return query
  select r.id, r.created_at, r.status, r.reason, r.details, r.subject_type,
   rp.display_name, e.id, e.title, e.status,
   su.id, su.display_name, coalesce(sf.status,'active'),
   m.id, m.body, m.hidden_at is not null
  from public.reports r
  left join public.profiles rp on rp.id=r.reporter_id
  left join public.events e on e.id=r.event_id
  left join public.profiles su on su.id=r.subject_user_id
  left join public.account_facts sf on sf.user_id=r.subject_user_id
  left join public.event_messages m on m.id=r.message_id
  where r.status in ('new','reviewing')
  order by r.created_at desc limit greatest(1, least(coalesce(p_limit,50), 200));
end $$;

-- Подія: hide / unhide / cancel.
create or replace function public.moderate_event(p_event_id uuid, p_action text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.assert_moderator();
 if p_action='hide' then update public.events set status='hidden', updated_at=now() where id=p_event_id and status='published';
 elsif p_action='unhide' then update public.events set status='published', updated_at=now() where id=p_event_id and status='hidden';
 elsif p_action='cancel' then update public.events set status='cancelled', updated_at=now() where id=p_event_id and status<>'cancelled';
 else raise exception 'INVALID_ACTION' using errcode='22023'; end if;
end $$;

-- Повідомлення: hide / unhide / delete.
create or replace function public.moderate_message(p_message_id uuid, p_action text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.assert_moderator();
 if p_action='hide' then update public.event_messages set hidden_at=now() where id=p_message_id and hidden_at is null;
 elsif p_action='unhide' then update public.event_messages set hidden_at=null where id=p_message_id;
 elsif p_action='delete' then update public.event_messages set deleted_at=coalesce(deleted_at,now()) where id=p_message_id;
 else raise exception 'INVALID_ACTION' using errcode='22023'; end if;
end $$;

-- Акаунт: active / limited / banned з нотаткою для колег.
create or replace function public.moderate_user(p_user_id uuid, p_status text, p_note text default null) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.assert_moderator();
 if p_status not in ('active','limited','banned') then raise exception 'INVALID_STATUS' using errcode='22023'; end if;
 insert into public.account_facts(user_id, status, status_note, updated_at) values (p_user_id, p_status, left(p_note,500), now())
 on conflict (user_id) do update set status=excluded.status, status_note=excluded.status_note, updated_at=now();
end $$;

-- Скарга: actioned / dismissed. Закриття останньої відкритої скарги не повертає приховане само —
-- це рішення модератора через moderate_event/moderate_message.
create or replace function public.resolve_report(p_report_id uuid, p_status text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.assert_moderator();
 if p_status not in ('reviewing','actioned','dismissed') then raise exception 'INVALID_STATUS' using errcode='22023'; end if;
 update public.reports set status=p_status where id=p_report_id;
end $$;

revoke all on function public.moderation_queue(integer), public.moderate_event(uuid,text), public.moderate_message(uuid,text),
 public.moderate_user(uuid,text,text), public.resolve_report(uuid,text) from public, anon, authenticated;
grant execute on function public.moderation_queue(integer), public.moderate_event(uuid,text), public.moderate_message(uuid,text),
 public.moderate_user(uuid,text,text), public.resolve_report(uuid,text) to authenticated;

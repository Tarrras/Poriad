-- Правки з рев'ю W1-fn (docs/organizers-1.5.md, 1.2 і 1.4) поверх 20261119120000 і 20261120120000:
-- - організатор заблокував того, хто просився: це не «не прийняв запит», і заблокованому ми не пишемо;
-- - ліміт «Вставити анонс»: IPv6 рахуємо за мережею /64 (одна людина має їх мільярди), і загальна стеля 1000 на годину,
--   щоб ботнет не з'їв рахунок Anthropic;
-- - лист організатору про питання — не частіше за раз на годину на розмову (функція `push`, `question_mail_due`).

-- Тіло — з 20261119120000, додано блокування.
create or replace function private.on_member_decided() returns trigger language plpgsql security definer set search_path='' as $$
declare v_kind text; v_event uuid; v_user uuid;
begin
 if current_setting('poruch.company_match', true) = 'on' then return null; end if;
 if tg_op = 'UPDATE' then
  v_kind := 'approved'; v_event := new.event_id; v_user := new.user_id;
 elsif tg_op = 'DELETE' then
  if not exists(select 1 from public.events e where e.id = old.event_id and e.organizer_id = auth.uid())
   or private.blocked_between(old.user_id, auth.uid()) then return null; end if;
  v_kind := 'declined'; v_event := old.event_id; v_user := old.user_id;
 elsif current_setting('poruch.left_waitlist', true) = new.event_id::text || ':' || new.user_id::text then
  v_kind := 'promoted'; v_event := new.event_id; v_user := new.user_id;
 else
  return null;
 end if;
 perform private.notify_push(jsonb_build_object('type', 'decision', 'kind', v_kind, 'event_id', v_event, 'user_id', v_user));
 return null;
end $$;

-- Тіло — з 20261120120000: мережа /64 для IPv6 і стеля на всіх.
create or replace function private.announce_call(p_ip text) returns boolean language plpgsql security definer set search_path='' as $$
declare v_ip inet := p_ip::inet; v_net inet;
begin
 v_net := case when pg_catalog.family(v_ip) = 6 then pg_catalog.set_masklen(v_ip::cidr, 64)::inet else pg_catalog.host(v_ip)::inet end;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('announce:' || v_net::text, 0));
 if (select count(*) from private.announce_calls where ip = v_net and at > now() - interval '1 hour') >= 20 then return false; end if;
 -- ponytail: стеля без спільного замка — два запити на 999-му можуть пройти обидва; на 1000 це не важить.
 if (select count(*) from private.announce_calls where at > now() - interval '1 hour') >= 1000 then return false; end if;
 insert into private.announce_calls(ip) values (v_net);
 return true;
end $$;

-- Коли організатору востаннє писали про розмову з людиною: одна розмова — один лист на годину.
-- ponytail: рядків стільки, скільки розмов з листом, і вони йдуть разом з подією чи людиною — прибирати не треба.
create table private.question_mails (
 event_id uuid not null references public.events(id) on delete cascade,
 thread_user_id uuid not null references public.profiles(id) on delete cascade,
 sent_at timestamptz not null default now(),
 primary key (event_id, thread_user_id)
);
revoke all on private.question_mails from public, anon, authenticated;

-- Перевірити й записати одним викликом: true — лист можна слати.
create function private.question_mail_due(p_event uuid, p_thread uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_due boolean;
begin
 insert into private.question_mails as q (event_id, thread_user_id) values (p_event, p_thread)
 on conflict (event_id, thread_user_id) do update set sent_at = now() where q.sent_at <= now() - interval '1 hour'
 returning true into v_due;
 return coalesce(v_due, false);
end $$;
create function public.question_mail_due(p_event uuid, p_thread uuid) returns boolean
language sql security invoker set search_path='' as $$ select private.question_mail_due(p_event, p_thread); $$;
revoke all on function private.question_mail_due(uuid, uuid), public.question_mail_due(uuid, uuid) from public, anon, authenticated;
-- Лише функція `push` ключем service role.
grant execute on function private.question_mail_due(uuid, uuid), public.question_mail_due(uuid, uuid) to service_role;

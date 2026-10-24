-- «Покликати з собою» (docs/invites.md): особисте посилання `poriad.app/e/{id}?by=<токен>`. Токен — 128 випадкових біт,
-- а не id людини: за ним сторінка події й застосунок показують лише ім'я й фото того, хто кличе.

-- Один токен на людину й подію: повторне «Покликати» дає те саме посилання, а таблиця не росте від кожного тапу.
-- ponytail: рядки минулих подій лишаються (сотні байтів на запрошення); прибирати разом з іншими нічними
-- чистками, коли їх стане десятки тисяч.
create table private.invites (
 token text primary key,
 user_id uuid not null references public.profiles(id) on delete cascade,
 event_id uuid not null references public.events(id) on delete cascade,
 created_at timestamptz not null default now(),
 unique (user_id, event_id)
);
revoke all on private.invites from public, anon, authenticated;

-- Кликати можна на подію, яку видно й яка ще не скінчилась. Нових запрошень — не більше 30 на годину: кожне —
-- рядок у базі, а звичайній людині стільки різних подій за годину не треба.
create function private.create_invite(p_event_id uuid) returns text
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event uuid := private.live_event_id(p_event_id); v_token text;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED'; end if;
 if not exists(select 1 from public.events e where e.id = v_event and e.status = 'published' and e.ends_at > now()
   and (e.organizer_id is null or e.organizer_id = v_user
        or (private.account_active(e.organizer_id) and not private.blocked_between(v_user, e.organizer_id)))) then
  raise exception 'EVENT_NOT_FOUND';
 end if;
 select i.token into v_token from private.invites i where i.user_id = v_user and i.event_id = v_event;
 if found then return v_token; end if;
 if (select count(*) from private.invites i where i.user_id = v_user and i.created_at > now() - interval '1 hour') >= 30 then
  raise exception 'TOO_MANY_INVITES';
 end if;
 -- base64url без вирівнювання: 22 знаки, які не треба кодувати в адресі.
 v_token := translate(encode(extensions.gen_random_bytes(16), 'base64'), '+/=', '-_');
 -- Подвійний тап: друга транзакція бере токен першої.
 insert into private.invites(token, user_id, event_id) values (v_token, v_user, v_event) on conflict (user_id, event_id) do nothing;
 return (select i.token from private.invites i where i.user_id = v_user and i.event_id = v_event);
end $$;
create function public.create_invite(p_event_id uuid) returns text
language sql security invoker set search_path='' as $$ select private.create_invite(p_event_id); $$;
revoke all on function private.create_invite(uuid), public.create_invite(uuid) from public, anon, authenticated;
grant execute on function private.create_invite(uuid), public.create_invite(uuid) to authenticated;

-- Хто кличе: перше слово імені й фото, без id. Порожньо, якщо токен чужий для цієї події, подія прихована, скасована
-- чи скінчилась, хтось когось заблокував або акаунт обмежено: тоді сторінка й застосунок показують звичайну подію.
-- Без входу (worker, гість) — теж, як `event_details`. Себе не кличуть, а «Учасник» — ім'я-заглушка, а не людина.
create function private.invite_inviter(p_token text, p_event_id uuid) returns table(name text, avatar_url text)
language sql stable security definer set search_path='' as $$
 select split_part(btrim(p.display_name), ' ', 1), p.avatar_url
 from private.invites i
 join public.profiles p on p.id = i.user_id
 join public.events e on e.id = private.live_event_id(i.event_id)
 where p_token ~ '^[A-Za-z0-9_-]{22}$' and i.token = p_token
  and e.id = private.live_event_id(p_event_id)
  and e.status = 'published' and e.ends_at > now()
  and p.display_name <> 'Учасник'
  and i.user_id is distinct from auth.uid()
  and private.account_active(i.user_id) and not private.blocked_between(auth.uid(), i.user_id)
  and (e.organizer_id is null or e.organizer_id = auth.uid()
       or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)
           and not private.blocked_between(i.user_id, e.organizer_id)));
$$;
create function public.invite_inviter(p_token text, p_event_id uuid) returns table(name text, avatar_url text)
language sql stable security invoker set search_path='' as $$ select * from private.invite_inviter(p_token, p_event_id); $$;
revoke all on function private.invite_inviter(text, uuid), public.invite_inviter(text, uuid) from public, anon, authenticated;
grant execute on function private.invite_inviter(text, uuid), public.invite_inviter(text, uuid) to anon, authenticated;

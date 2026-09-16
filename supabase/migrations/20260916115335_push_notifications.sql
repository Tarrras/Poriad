-- Пуші. Пристрій реєструє свій токен FCM (Android) чи APNs (iOS); тригери на нове повідомлення
-- й новий запит на участь кличуть Edge Function `push`, а вона вирішує, кому й що слати.
-- База не знає ні ключів FCM, ні APNs: лише адресу функції та спільний секрет у Vault.

create extension if not exists pg_net with schema extensions;

-- ---- Токени

create table public.push_tokens (
 token text primary key,
 user_id uuid not null references public.profiles(id) on delete cascade,
 platform text not null check (platform in ('android','ios')),
 updated_at timestamptz not null default now()
);
create index push_tokens_user_idx on public.push_tokens(user_id);
-- Без політик: клієнт ходить лише через RPC, функція — через service role.
alter table public.push_tokens enable row level security;
revoke all on table public.push_tokens from public,anon,authenticated;

-- Той самий токен після перелогіну переходить до нового акаунта: телефон один, людей може бути дві.
create function private.register_push_token(p_token text,p_platform text) returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_token is null or length(p_token) < 16 or length(p_token) > 4096 then raise exception 'INVALID_TOKEN' using errcode='22023'; end if;
 if p_platform not in ('android','ios') then raise exception 'INVALID_PLATFORM' using errcode='22023'; end if;
 insert into public.push_tokens(token,user_id,platform) values (p_token,v_user,p_platform)
 on conflict (token) do update set user_id=excluded.user_id,platform=excluded.platform,updated_at=now();
end $$;
create function private.unregister_push_token(p_token text) returns void language sql security definer set search_path='' as $$
 delete from public.push_tokens where token=p_token and user_id=auth.uid();
$$;
create function public.register_push_token(p_token text,p_platform text) returns void language sql security invoker set search_path='' as $$
 select private.register_push_token(p_token,p_platform);
$$;
create function public.unregister_push_token(p_token text) returns void language sql security invoker set search_path='' as $$
 select private.unregister_push_token(p_token);
$$;
revoke all on function private.register_push_token(text,text),private.unregister_push_token(text),public.register_push_token(text,text),public.unregister_push_token(text) from public,anon,authenticated;
grant execute on function private.register_push_token(text,text),private.unregister_push_token(text),public.register_push_token(text,text),public.unregister_push_token(text) to authenticated;

-- ---- Доставка: тригер → pg_net → Edge Function

-- Адреса й секрет живуть у Vault під іменами `push_function_url` і `push_function_secret`.
-- Поки їх нема, тригери мовчать: чат і запити працюють без пушів.
create function private.push_endpoint(out url text,out secret text) language sql stable security definer set search_path='' as $$
 select (select decrypted_secret from vault.decrypted_secrets where name='push_function_url' limit 1),
        (select decrypted_secret from vault.decrypted_secrets where name='push_function_secret' limit 1);
$$;

create function private.notify_push(p_payload jsonb) returns void language plpgsql security definer set search_path='' as $$
declare v_url text; v_secret text;
begin
 select url,secret into v_url,v_secret from private.push_endpoint();
 if v_url is null or v_secret is null then return; end if;
 -- Асинхронно: відповідь функції транзакцію не тримає.
 perform net.http_post(
  url:=v_url,
  body:=p_payload,
  headers:=jsonb_build_object('Content-Type','application/json','x-push-secret',v_secret),
  timeout_milliseconds:=5000
 );
exception when others then
 -- Пуш — доповнення: збій доставки не має зламати запис повідомлення чи запиту.
 raise warning 'push notify failed: %', sqlerrm;
end $$;

create function private.on_message_inserted() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.notify_push(jsonb_build_object('type','message','message_id',new.id,'event_id',new.event_id));
 return new;
end $$;
create trigger event_messages_push after insert on public.event_messages
 for each row execute function private.on_message_inserted();

create function private.on_member_requested() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.notify_push(jsonb_build_object('type','request','event_id',new.event_id,'user_id',new.user_id));
 return new;
end $$;
create trigger event_members_push after insert on public.event_members
 for each row when (new.status='requested') execute function private.on_member_requested();

revoke all on function private.push_endpoint(),private.notify_push(jsonb),private.on_message_inserted(),private.on_member_requested() from public,anon,authenticated;

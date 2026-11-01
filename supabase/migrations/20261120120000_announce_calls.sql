-- «Вставити анонс» (docs/organizers-1.5.md, 1.4): функція `parse-announcement` відкрита й для гостя, тож не більше 20
-- викликів на годину з однієї адреси. Тексту анонсу тут нема: лише адреса й час, і лише на годину — далі прибирає cron.

create table private.announce_calls (
 ip inet not null,
 at timestamptz not null default now()
);
create index announce_calls_ip_at_idx on private.announce_calls (ip, at);
revoke all on private.announce_calls from public, anon, authenticated;

-- Перевірити й записати одним викликом: true — можна кликати модель, false — ліміт. Замок на адресу, щоб 20
-- паралельних запитів не пройшли всі разом.
create function private.announce_call(p_ip text) returns boolean language plpgsql security definer set search_path='' as $$
declare v_ip inet := p_ip::inet;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('announce:' || host(v_ip), 0));
 if (select count(*) from private.announce_calls where ip = v_ip and at > now() - interval '1 hour') >= 20 then return false; end if;
 insert into private.announce_calls(ip) values (v_ip);
 return true;
end $$;
create function public.announce_call(p_ip text) returns boolean language sql security invoker set search_path='' as $$
 select private.announce_call(p_ip);
$$;
revoke all on function private.announce_call(text), public.announce_call(text) from public, anon, authenticated;
-- Лише функція `parse-announcement` ключем service role.
grant execute on function private.announce_call(text), public.announce_call(text) to service_role;

create function private.forget_announce_calls() returns integer language sql security definer set search_path='' as $$
 with gone as (delete from private.announce_calls where at < now() - interval '1 hour' returning 1)
 select count(*)::integer from gone;
$$;
revoke all on function private.forget_announce_calls() from public, anon, authenticated;

do $$ begin
 if exists (select 1 from pg_extension where extname = 'pg_cron') then
  execute $cron$select cron.schedule('forget-announce-calls', '23 * * * *', 'select private.forget_announce_calls()')$cron$;
 end if;
end $$;

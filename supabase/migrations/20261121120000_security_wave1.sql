-- Аудит безпеки хвилі 1 (docs/organizers-1.5.md, «Аудит безпеки хвилі 1», 02.11), до пілоту:
-- - видалення акаунта прибирає й відео (бакет event-videos), не лише фото; RPC `delete_my_account` клієнтам закрито:
--   він видаляє рядки без файлів у Storage і без повторного входу, а застосунки й сайт з 23.09 (v1.3.1) ходять у
--   функцію `delete-account`;
-- - у теці події `<uid>/<event>/` не більше 12 файлів у event-images і 11 у event-videos: 5 медіа, їхні постери й
--   обкладинка з запасом на заміну, але не безкінечне сховище за наш рахунок;
-- - «Вставити анонс»: загальна стеля 300 викликів на годину замість 1000.
-- Посилання з назв і імен у листах прибирає функція `push` (mail.ts), а не заборона в базі.

-- Тіло — з 20260923100000, додано event-videos.
create or replace function private.delete_my_account() returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.set_config('storage.allow_delete_query','true',true);
 delete from storage.objects where bucket_id in ('event-images','event-videos') and name like v_user::text || '/%';
 delete from auth.users where id=v_user;
end $$;
revoke execute on function public.delete_my_account(), private.delete_my_account() from public, anon, authenticated;

-- Ліміт файлів у теці події. Тригер на кожну вставку, зокрема Storage copy («Повторити») і upsert: той самий файл
-- удруге не рахуємо. Аватари (`<uid>/avatar/…`) не чіпаємо: застосунок кладе кожен під новою назвою.
-- Відео 11 = 2×5+1: клієнти спершу вантажать нові файли й лише після update_event видаляють замінені, тож на мить у
-- теці лежать і старі, і нові. ponytail: аватари без ліміту.
create function private.limit_event_files() returns trigger language plpgsql security definer set search_path='' as $$
declare v_max integer := case new.bucket_id when 'event-images' then 12 when 'event-videos' then 11 end; v_prefix text;
begin
 if v_max is null or split_part(new.name, '/', 3) = '' or split_part(new.name, '/', 2) = 'avatar' then return new; end if;
 v_prefix := split_part(new.name, '/', 1) || '/' || split_part(new.name, '/', 2) || '/';
 -- Замок на теку: паралельні вивантаження не проскочать ліміт разом.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.bucket_id || ':' || v_prefix, 0));
 if (select count(*) from storage.objects o where o.bucket_id = new.bucket_id and o.name <> new.name
     and o.name like replace(replace(replace(v_prefix, '\', '\\'), '%', '\%'), '_', '\_') || '%') >= v_max then
  raise exception 'TOO_MANY_FILES' using errcode='P0001';
 end if;
 return new;
end $$;
revoke all on function private.limit_event_files() from public, anon, authenticated;
create trigger poruch_event_files_limit before insert on storage.objects
 for each row execute function private.limit_event_files();

-- Тіло — з 20261120130000, стеля 300 і лічильник у журнал (без адрес).
create or replace function private.announce_call(p_ip text) returns boolean language plpgsql security definer set search_path='' as $$
declare v_ip inet := p_ip::inet; v_net inet; v_total integer;
begin
 v_net := case when pg_catalog.family(v_ip) = 6 then pg_catalog.set_masklen(v_ip::cidr, 64)::inet else pg_catalog.host(v_ip)::inet end;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('announce:' || v_net::text, 0));
 if (select count(*) from private.announce_calls where ip = v_net and at > now() - interval '1 hour') >= 20 then return false; end if;
 -- ponytail: стеля без спільного замка — два запити на 299-му можуть пройти обидва; Turnstile чи анонімний вхід —
 -- коли з'явиться зловживання.
 select count(*) into v_total from private.announce_calls where at > now() - interval '1 hour';
 if v_total >= 300 then
  raise log 'announce_call: ceiling reached, % calls in the last hour', v_total;
  return false;
 end if;
 insert into private.announce_calls(ip) values (v_net);
 return true;
end $$;

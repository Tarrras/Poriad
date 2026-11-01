-- Аудит безпеки хвилі 1 (docs/organizers-1.5.md, «Аудит безпеки хвилі 1», 02.11), до пілоту:
-- - видалення акаунта прибирає й відео (бакет event-videos), не лише фото;
-- - у теці події `<uid>/<event>/` не більше 12 файлів у event-images і 6 у event-videos: 5 медіа, їхні постери й
--   обкладинка з запасом на повтор, але не безкінечне сховище за наш рахунок;
-- - «Вставити анонс»: загальна стеля 300 викликів на годину замість 1000;
-- - назва спільнотної події без посилань і доменів: поштові клієнти роблять з них лінк у листі від noreply@poriad.app.

-- Тіло — з 20260923100000, додано event-videos.
create or replace function private.delete_my_account() returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.set_config('storage.allow_delete_query','true',true);
 delete from storage.objects where bucket_id in ('event-images','event-videos') and name like v_user::text || '/%';
 delete from auth.users where id=v_user;
end $$;

-- Ліміт файлів у теці події. Тригер на кожну вставку, зокрема Storage copy («Повторити») і upsert: той самий файл
-- удруге не рахуємо. Аватари (`<uid>/avatar/…`) не чіпаємо: застосунок кладе кожен під новою назвою.
-- ponytail: аватари без ліміту, а заміна медіа в події кладе нові файли поруч зі старими — 12/6 вистачає на одну
-- повну заміну; якщо організатори впиратимуться, клієнти мають видаляти замінені файли.
create function private.limit_event_files() returns trigger language plpgsql security definer set search_path='' as $$
declare v_max integer := case new.bucket_id when 'event-images' then 12 when 'event-videos' then 6 end; v_prefix text;
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

-- Тіло — з 20260923140000, додано посилання в назві. Лише спільнотна подія (супутник бере назву афіші) і лише нова
-- чи змінена назва: старі події редагуються як були.
create or replace function private.check_event_text() returns trigger language plpgsql set search_path='' as $$
begin
 if new.organizer_id is null then return new; end if;
 if (tg_op='INSERT' or new.title is distinct from old.title)
    and char_length(btrim(new.title)) not between 3 and 120 then
  raise exception 'INVALID_TITLE' using errcode='22023';
 end if;
 if (tg_op='INSERT' or new.title is distinct from old.title) and new.companion_of is null
    and new.title ~* '(https?://|www\.|[[:alnum:]_-]\.(com|net|org|ua|app|io|me|ru|su|info|xyz|top|link|site|online|store|shop|biz|club|live|pro|tv|cc|gg|ly|to|co|eu|pl|de|uk|рф|укр)\y)' then
  raise exception 'INVALID_TITLE' using errcode='22023';
 end if;
 if (tg_op='INSERT' or new.description is distinct from old.description)
    and char_length(btrim(new.description)) not between 10 and 5000 then
  raise exception 'INVALID_DESCRIPTION' using errcode='22023';
 end if;
 return new;
end $$;

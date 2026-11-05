-- Скріншот оплати в розмові з організатором (docs/organizer-events.md, «Платна подія»): людина платить онлайн і
-- надсилає організатору скрін переказу, а той звіряє з банком і тисне «Оплату отримано». На скріні — імена, частина
-- картки й сума, тож бакет приватний: файл бачать лише двоє — хто надіслав і організатор події.
--
-- - Надсилає лише людина у своїй розмові з організатором події з оплатою онлайн, де вона записалась (є рядок
--   учасника: заявка чи місце). Організатор картинок не надсилає: реквізити картинкою обійшли б перевірку
--   `has_payment_details` і застереження під ними.
-- - Файл — `<uid>/<подія>/<uuid>.jpg` (клієнт перекодовує в JPEG, як фото події): власник — перша тека, тож
--   `delete-account` прибирає його разом з рештою файлів людини. До 5 МБ і 20 файлів на добу.
-- - Повідомлення з картинкою має й текст (клієнт ставить «Скріншот оплати», якщо людина нічого не написала): старі
--   застосунки картинки не покажуть, але скажуть, що вона була.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('payment-proofs','payment-proofs',false,5242880,array['image/jpeg']);

-- Один розбір шляху на всі перевірки (політики, колонка, send_message): `<власник>/<подія>/<uuid>.jpg` → власник і
-- подія; інший шлях — null.
create function private.proof_owner(p_name text) returns uuid
language sql immutable set search_path='' as $$
 select case when p_name ~ '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/){2}[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
  then split_part(p_name,'/',1)::uuid end;
$$;
create function private.proof_event(p_name text) returns uuid
language sql immutable set search_path='' as $$
 select case when private.proof_owner(p_name) is not null then split_part(p_name,'/',2)::uuid end;
$$;

create function private.can_upload_proof(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
  and private.proof_owner(p_name) = auth.uid()
  and exists(select 1 from public.events e join public.event_members m on m.event_id=e.id and m.user_id=auth.uid()
   where e.id = private.proof_event(p_name) and e.pay_online and e.status='published'
   and e.ends_at > now() - interval '7 days' and not private.blocked_between(auth.uid(), e.organizer_id))
  -- Тека людини — діапазоном імені (байтово «/» < «0»), а не split_part: індекс (bucket_id, name collate "C") Storage
  -- читає лише її файли, а не весь бакет.
  and (select count(*) from storage.objects o where o.bucket_id='payment-proofs'
   and o.name collate "C" >= auth.uid()::text || '/' and o.name collate "C" < auth.uid()::text || '0'
   and o.created_at > now() - interval '1 day') < 20;
$$;
create function private.can_read_proof(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.proof_owner(p_name) = auth.uid()
  or exists(select 1 from public.events e where e.id = private.proof_event(p_name) and e.organizer_id = auth.uid()));
$$;
revoke all on function private.proof_owner(text), private.proof_event(text), private.can_upload_proof(text), private.can_read_proof(text)
 from public, anon, authenticated;
grant execute on function private.proof_owner(text), private.proof_event(text), private.can_upload_proof(text), private.can_read_proof(text)
 to authenticated;

create policy poruch_proof_insert on storage.objects for insert to authenticated
 with check (bucket_id='payment-proofs' and private.can_upload_proof(name));
-- Storage читає щойно вставлений рядок, тож і власнику — SELECT (як 20260923100300).
create policy poruch_proof_read on storage.objects for select to authenticated
 using (bucket_id='payment-proofs' and private.can_read_proof(name));
create policy poruch_proof_delete on storage.objects for delete to authenticated
 using (bucket_id='payment-proofs' and split_part(name,'/',1)=(select auth.uid())::text);

-- ───── Повідомлення з картинкою
alter table public.event_messages add column image text check (image is null or private.proof_owner(image) is not null);

-- Старі сигнатури зникають: PostgREST не має вибирати між двома, а старий клієнт (без `p_image`) потрапляє в нову.
drop function if exists public.send_message(uuid,text,uuid);
drop function if exists private.send_message(uuid,text,uuid);

-- Тіло — з 20261125120000, додано: `p_image` (скріншот оплати).
create function private.send_message(p_event_id uuid, p_body text, p_thread uuid default null, p_image text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_body text := btrim(p_body); v_id uuid; v_details boolean;
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
  -- Організатор першим пише лише тому, хто вже питав, записався, подав заявку чи стоїть у черзі.
  if v_user = v_event.organizer_id
     and not exists(select 1 from public.event_messages m where m.event_id=p_event_id and m.thread_user_id=p_thread and m.author_id=p_thread)
     and not exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=p_thread)
     and not exists(select 1 from public.event_waitlist w where w.event_id=p_event_id and w.user_id=p_thread) then
   raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 -- Тиждень після кінця — щоб домовитись про фото й речі; далі чат закривається.
 if v_event.ends_at < now() - interval '7 days' then raise exception 'CHAT_CLOSED' using errcode='P0001'; end if;
 -- Реквізити — лише вдвох і лише там, де оплата онлайн: у загальному чаті їх бачать усі, а «на місці» — без передоплати.
 v_details := private.has_payment_details(v_body);
 if v_details and not (v_event.pay_online and p_thread is not null) then raise exception 'PAYMENT_DETAILS' using errcode='22023'; end if;
 -- Скріншот оплати — лише від людини в її розмові онлайн-події і лише свій уже вивантажений файл цієї події.
 if p_image is not null and (p_thread is null or v_user <> p_thread or not v_event.pay_online
     or private.proof_owner(p_image) is distinct from v_user or private.proof_event(p_image) is distinct from p_event_id
     or not exists(select 1 from storage.objects o where o.bucket_id='payment-proofs' and o.name=p_image)) then
  raise exception 'INVALID_IMAGE' using errcode='22023'; end if;
 -- Двадцять на хвилину — розмова; більше — скрипт. Видалені й розмови теж рахуються.
 if (select count(*) from public.event_messages where author_id=v_user and created_at > now()-interval '1 minute') >= 20 then
  raise exception 'TOO_MANY_MESSAGES' using errcode='P0001'; end if;
 insert into public.event_messages(event_id,author_id,body,thread_user_id,payment_details,image)
 values (p_event_id,v_user,v_body,p_thread,v_details,p_image) returning id into v_id;
 return v_id;
end $$;
create function public.send_message(p_event_id uuid,p_body text,p_thread uuid default null,p_image text default null) returns uuid
language sql security invoker set search_path='' as $$ select private.send_message(p_event_id,p_body,p_thread,p_image); $$;
revoke all on function private.send_message(uuid,text,uuid,text),public.send_message(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function private.send_message(uuid,text,uuid,text),public.send_message(uuid,text,uuid,text) to authenticated;

-- Стрічка віддає й шлях картинки: клієнт завантажує її з приватного бакета з токеном людини.
alter type public.message_result add attribute image text;
-- Тіло — з 20261125120000, додано: `m.image`.
create or replace function public.event_messages(p_event_id uuid,p_after timestamptz default null,p_limit integer default 100,p_thread uuid default null)
 returns setof public.message_result language sql stable security invoker set search_path='' as $$
 select * from (
  select m.id,m.event_id,m.author_id,p.display_name,p.avatar_url,m.body,m.created_at,m.payment_details,m.image
  from public.event_messages m join public.profiles p on p.id=m.author_id
  where m.event_id=p_event_id and m.thread_user_id is not distinct from p_thread and (p_after is null or m.created_at > p_after)
  order by m.created_at desc,m.id desc limit greatest(1,least(coalesce(p_limit,100),200))
 ) tail order by created_at,id;
$$;

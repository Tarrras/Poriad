-- Вимикач оплати онлайн без нової збірки (власник 05.11: «цей функціонал ризиковий»). Реквізити в розмові — головний
-- ризик шахрайства, тож оплата онлайн працює, лише коли ввімкнено прапорець `pay_online` (private.flags). За
-- замовчуванням вимкнено: після накочування на prod оплати онлайн нема, доки власник її не ввімкне.
--
--   update private.flags set enabled = true,  changed_at = now() where name = 'pay_online';   -- увімкнути
--   update private.flags set enabled = false, changed_at = now() where name = 'pay_online';   -- вимкнути
--
-- Вимкнено:
-- - усі бачать події як «оплата на місці»: event_rows віддає pay_online лише з прапорцем, і застосунки, кабінет і
--   /e/{id} малюють від цього (сторінка події в кеші воркера — до 5 хвилин);
-- - подія не стає онлайн (тригер на events, PAY_ONLINE_OFF), а кабінет без прапорця «Онлайн» і не пропонує
--   (`pay_online_enabled`);
-- - реквізитів і скріншотів у розмовах не приймаємо (тригер на event_messages, can_upload_proof).
-- Колонку events.pay_online не чіпаємо: увімкнули знову — події, що були онлайн, знову онлайн. Уже надіслані
-- реквізити й скріншоти лишаються в розмовах.

insert into private.flags (name) values ('pay_online') on conflict (name) do nothing;

-- Подія не стає онлайн, поки вимкнено. Та, що вже онлайн, такою й лишається в базі: вимикач оборотний.
create function private.guard_pay_online() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.pay_online and not private.flag('pay_online') and (tg_op = 'INSERT' or not old.pay_online) then
  raise exception 'PAY_ONLINE_OFF' using errcode='P0001';
 end if;
 return new;
end $$;
create trigger events_pay_online before insert or update of pay_online on public.events
 for each row execute function private.guard_pay_online();

-- Реквізити й скріншоти оплати — лише з прапорцем. send_message позначає їх (payment_details, image) і пускає лише в
-- розмові онлайн-події; тут — останнє слово вимикача, які б функції не писали в розмову.
create function private.guard_payment_messages() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if (new.payment_details or new.image is not null) and not private.flag('pay_online') then
  raise exception '%', case when new.image is not null then 'INVALID_IMAGE' else 'PAYMENT_DETAILS' end using errcode='22023';
 end if;
 return new;
end $$;
create trigger event_messages_pay_online before insert on public.event_messages
 for each row execute function private.guard_payment_messages();

-- Тіло — з 20261125130000, додано: прапорець. Файл без повідомлення не лишається висіти в бакеті.
create or replace function private.can_upload_proof(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
  and private.proof_owner(p_name) = auth.uid()
  and exists(select 1 from public.events e join public.event_members m on m.event_id=e.id and m.user_id=auth.uid()
   where e.id = private.proof_event(p_name) and e.pay_online and private.flag('pay_online') and e.status='published'
   and e.ends_at > now() - interval '7 days' and not private.blocked_between(auth.uid(), e.organizer_id))
  -- Тека людини — діапазоном імені (байтово «/» < «0»), а не split_part: індекс (bucket_id, name collate "C") Storage
  -- читає лише її файли, а не весь бакет.
  and (select count(*) from storage.objects o where o.bucket_id='payment-proofs'
   and o.name collate "C" >= auth.uid()::text || '/' and o.name collate "C" < auth.uid()::text || '0'
   and o.created_at > now() - interval '1 day') < 20;
$$;

-- Тіло — з 20261125120000, змінено лише pay_online.
create or replace function private.event_rows(p_ids uuid[])
returns setof public.event_result language sql stable security definer set search_path='' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,
 coalesce(p.display_name, s.name),
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
 e.origin,s.name,e.canonical_url,e.import_status,e.price_min,e.is_free,
 -- Чат — лише своїм: організатору й підтвердженим. Запит і черга ще не всередині.
 case when e.organizer_id=auth.uid()
       or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved')
      then e.contact_url end,
 e.companion_of,
 pe.title,
 cs.state, cs.previous_starts_at, cs.checked_at,
 case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end,
 -- R7а: питання до організатора збору бачать усі, кому видно збір (учасникам — «Організатор вирішує»).
 case when e.status = 'published' then d.proposed_at end,
 case when e.status = 'published' then d.decide_by end,
 pe.starts_at,
 e.media,
 -- Вимкнено — усі бачать «на місці»: застосунки, кабінет і /e/{id} малюють від цього значення.
 e.pay_online and private.flag('pay_online')
 from public.events e
 left join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 left join public.events pe on pe.id=e.companion_of
 left join private.companion_decisions d on d.companion_id=e.id
 cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
 where e.id=any(p_ids) and private.has_event_access(e.id)
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$$;

-- Кабінету: показувати «Онлайн» у «Як платять» чи ні.
create function public.pay_online_enabled() returns boolean
language sql stable security definer set search_path='' as $$ select private.flag('pay_online'); $$;

revoke all on function private.guard_pay_online(), private.guard_payment_messages() from public, anon, authenticated;
revoke all on function public.pay_online_enabled() from public;
grant execute on function public.pay_online_enabled() to anon, authenticated;

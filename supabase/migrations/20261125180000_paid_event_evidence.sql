-- Безпека платних подій без оплати онлайн (власник 05.11): гроші й реквізити — поза «Поряд», у чаті учасників
-- організатора, тож лишаємо два запобіжники.
-- 1. «Новий організатор»: платна подія від людей, а організатор ще не провів жодної з учасниками (events_held) —
--    сторінка й застосунки кажуть про це до того, як людина домовлятиметься про передоплату.
-- 2. Знімок платної події при видаленні акаунта організатора: подія, організатор (імʼя, пошта, з якого часу), посилання
--    на його чат і скільки записалось — 180 днів після події в private.payment_evidence, для скарг і запитів
--    правоохоронців (Політика конфіденційності, розділ 5). Видаляє той самий крон purge-payment-evidence.

alter type public.event_result add attribute organizer_new boolean;

-- Тіло — з 20261125170000, додано: organizer_new.
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
 -- Вимкнено (усім чи цьому організатору) — усі бачать «на місці»; правила повернення — лише в онлайн-події.
 e.pay_online and private.pay_online_allowed(e.organizer_id),
 case when e.pay_online and private.pay_online_allowed(e.organizer_id) then e.refund_policy end,
 -- Платна подія від людей, а організатор ще не провів жодної з учасниками: «Новий організатор» на сторінці.
 case when e.origin='community' and coalesce(e.price_min,0) > 0 and e.organizer_id is not null then private.events_held(e.organizer_id) = 0 end
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

-- Тіло — з 20261125170000, додано: знімок платних подій.
create or replace function private.prepare_account_deletion(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.events e where e.organizer_id=p_user and e.pay_online and e.status='published' and e.ends_at > now()
   and exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id<>p_user)) then
  raise exception 'PAID_EVENTS_ACTIVE' using errcode='P0001'; end if;
 insert into private.payment_evidence(event_id, organizer_id, deleted_user_id, snapshot, purge_after)
 select e.id, e.organizer_id, p_user, jsonb_build_object(
   'event', jsonb_build_object('title', e.title, 'starts_at', e.starts_at, 'status', e.status, 'price', e.price_min, 'refund_policy', e.refund_policy),
   'organizer', (select jsonb_build_object('name', p.display_name, 'email', u.email) from public.profiles p join auth.users u on u.id=p.id where p.id=e.organizer_id),
   'payer', (select jsonb_build_object('id', p.id, 'name', p.display_name, 'email', u.email) from public.profiles p join auth.users u on u.id=p.id where p.id=t.thread_user_id),
   'messages', (select jsonb_agg(jsonb_build_object('author', m.author_id, 'body', m.body, 'at', m.created_at, 'payment_details', m.payment_details,
      'image', m.image, 'deleted_at', m.deleted_at) order by m.created_at) from public.event_messages m where m.event_id=e.id and m.thread_user_id=t.thread_user_id),
   'consents', (select jsonb_agg(jsonb_build_object('user', c.user_id, 'role', c.role, 'version', c.version, 'at', c.accepted_at))
      from private.pay_consents c where (c.user_id=e.organizer_id and c.role='organizer') or (c.user_id=t.thread_user_id and c.event_id=e.id))),
  greatest(e.ends_at, now()) + interval '180 days'
 from public.events e
 join (select distinct m.event_id, m.thread_user_id from public.event_messages m where m.thread_user_id is not null) t on t.event_id=e.id
 where e.pay_online and (e.organizer_id=p_user or t.thread_user_id=p_user) and e.ends_at > now() - interval '180 days'
 and exists(select 1 from public.event_messages m where m.event_id=e.id and m.thread_user_id=t.thread_user_id and (m.payment_details or m.image is not null));
 -- Платні події організатора (оплата на місці чи напряму поза «Поряд», 05.11): хто, що, коли й де шукати його чат.
 -- Переписка про гроші — у його Telegram, а без цього знімка подія зникла б разом з акаунтом.
 insert into private.payment_evidence(event_id, organizer_id, deleted_user_id, snapshot, purge_after)
 select e.id, e.organizer_id, p_user, jsonb_build_object(
   'kind', 'paid_event',
   'event', jsonb_build_object('title', e.title, 'starts_at', e.starts_at, 'ends_at', e.ends_at, 'status', e.status, 'price', e.price_min,
     'city', e.city, 'address', e.address, 'contact_url', e.contact_url, 'pay_online', e.pay_online, 'created_at', e.created_at),
   'organizer', (select jsonb_build_object('name', p.display_name, 'email', u.email, 'since', u.created_at) from public.profiles p join auth.users u on u.id=p.id where p.id=e.organizer_id),
   'members', (select count(*) from public.event_members m where m.event_id=e.id and m.user_id<>e.organizer_id)),
  greatest(e.ends_at, now()) + interval '180 days'
 from public.events e
 where e.organizer_id=p_user and e.origin='community' and coalesce(e.price_min,0) > 0 and e.ends_at > now() - interval '180 days';
end $$;

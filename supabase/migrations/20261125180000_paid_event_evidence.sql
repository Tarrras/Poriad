-- Знімок платних подій при видаленні акаунта організатора (власник 05.11). Оплата тепер поза «Поряд» — на місці чи
-- напряму в чаті учасників організатора, — тож без цього знімка подія зникла б разом з акаунтом, а людям, які
-- заплатили, не було б на що послатися. Подія, організатор (імʼя, пошта, з якого часу), посилання на його чат і
-- скільки записалось — 180 днів після події в private.payment_evidence, для скарг і запитів правоохоронців (Політика
-- конфіденційності, розділ 5). Видаляє той самий крон purge-payment-evidence.

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

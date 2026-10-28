-- Опис, що чіпляє (docs/return-hooks.md): два речення агента імпорту під «що це» у стосі «Ваш тиждень». Чужий
-- опис продавця можна показати лише першими 200 знаками й він часто SEO-вступ; цей — наш текст, лише з фактів
-- картки. Пише конвеєр окремим оновленням (emit.pitches_sql); порожньо, коли в тексті нема нічого понад «що це».
-- Старі клієнти поле не читають.
alter table public.events add column if not exists pitch text
 constraint events_pitch_length check (pitch is null or char_length(pitch) between 1 and 240);

-- Як у 20261109120000, плюс 'pitch'.
create or replace function private.event_cards(p_ids uuid[])
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(card order by starts_at, id), '[]'::jsonb) from (
  select e.starts_at, e.id, jsonb_strip_nulls(jsonb_build_object(
    'id', e.id, 'title', e.title, 'blurb', e.blurb, 'pitch', e.pitch, 'description', nullif(e.description,''), 'category', e.category,
    'city', e.city, 'address', e.address,
    'place_id', e.place_id, 'place_name', pl.name,
    'starts_at', e.starts_at, 'ends_at', e.ends_at, 'time_zone', e.time_zone, 'status', e.status,
    'latitude', e.latitude, 'longitude', e.longitude, 'image_url', e.image_url,
    'organizer_id', e.organizer_id, 'organizer_name', coalesce(p.display_name, s.name),
    'capacity', e.capacity,
    'attendee_count', case when e.origin='community' then
      (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved') end,
    'joined', case when e.origin='community' and auth.uid() is not null then
      exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved') end,
    'membership', case when e.origin='community' and auth.uid() is not null then
      (select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()) end,
    'min_age', nullif(e.min_age, private.min_signup_age()), 'max_age', e.max_age,
    'approval_required', case when e.approval_required then true end,
    'origin', e.origin, 'source_name', s.name, 'canonical_url', e.canonical_url,
    'import_status', e.import_status, 'price_min', e.price_min, 'is_free', e.is_free,
    'state', cs.state, 'previous_starts_at', cs.previous_starts_at, 'checked_at', cs.checked_at,
    'offers', case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end,
    'artists', (select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'kind', a.kind, 'role', ea.role)
                                 order by ea.position, a.name)
                from public.event_artists ea join public.artists a on a.id = ea.artist_id
                where ea.event_id = e.id))) as card
  from public.events e
  left join public.profiles p on p.id = e.organizer_id
  left join public.event_sources s on s.id = e.source_id
  left join public.places pl on pl.id = e.place_id
  cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
  where e.id = any(p_ids) and private.has_event_access(e.id)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
 ) t;
$$;

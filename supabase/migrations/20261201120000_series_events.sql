-- Серія в кабінеті (docs/creation-platform-plan-2026-11.md, «Склад і серія»): «Серія: N подій» на екрані події,
-- «Скасувати цю й наступні» і правка «цієї й наступних». Скасування й правка — ті самі `cancel_event`,
-- `update_event`, `set_event_lineup` по одній події; тут — лише список: кабінет читає події через `event_result`,
-- а той `series_id` не несе.

-- Події серії, до якої належить `p_event`, за початком — лише її організаторові. Не в серії чи чужа — порожньо.
-- `image_url` — щоб правка «й наступних» не перетерла обкладинку: `update_event` без `p_media` ставить `p_image_url`.
create function private.series_events(p_event uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'starts_at', s.starts_at, 'ends_at', s.ends_at,
   'time_zone', s.time_zone, 'status', s.status, 'image_url', s.image_url) order by s.starts_at, s.id), '[]'::jsonb)
 from public.events e join public.events s on s.series_id = e.series_id and s.organizer_id = e.organizer_id
 where e.id = p_event and e.organizer_id = auth.uid();
$$;

create function public.series_events(p_event uuid) returns jsonb
language sql stable set search_path='' as $$ select private.series_events(p_event); $$;

revoke all on function private.series_events(uuid), public.series_events(uuid) from public, anon, authenticated;
grant execute on function private.series_events(uuid), public.series_events(uuid) to authenticated;

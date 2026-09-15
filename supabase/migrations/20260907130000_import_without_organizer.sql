-- Імпортована подія без організатора. Синтетичний профіль джерела означав би фантомні
-- записи в auth.users, які довелося б виключати з пошуку, блокувань і скарг. Натомість на
-- картці стоїть назва джерела.

alter table public.events alter column organizer_id drop not null;

-- Обов'язковий організатор лише у спільнотної події.
alter table public.events add constraint events_community_has_organizer_ck
 check (origin <> 'community' or organizer_id is not null);

-- Проєкція: без організатора ім'я бере джерело. Склад полів той самий, тому лише функція.
create or replace function private.event_rows(p_ids uuid[]) returns setof public.event_result language sql stable security definer set search_path = '' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,
 coalesce(p.display_name, s.name),
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
 e.origin,s.name,e.canonical_url,e.import_status,e.price_min,e.is_free
 from public.events e
 left join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 where e.id=any(p_ids) and private.has_event_access(e.id)
 -- Блокування й обмеження стосуються лише подій із живим організатором.
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$$;

-- has_event_access при null organizer_id дає «не свій», що і треба.

-- Джерело більше не потребує акаунта.
alter table public.event_sources alter column organizer_id drop not null;
comment on column public.event_sources.organizer_id is
 'Необов''язково. Заповнюється лише для партнерських джерел, які ведуть події від імені справжнього акаунта.';

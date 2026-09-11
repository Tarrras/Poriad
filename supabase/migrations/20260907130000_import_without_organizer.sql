-- Імпортована подія не має організатора — і не повинна його вигадувати.
--
-- Попередня міграція вимагала для кожного джерела «синтетичний профіль». Оскільки
-- public.profiles.id посилається на auth.users.id, це означало б заводити фантомні облікові
-- записи в таблиці автентифікації заради рядків, які ніколи не входять у застосунок. Ціна цього
-- не лише косметична: такий акаунт має бути виключений з пошуку людей, з блокувань, зі скарг і з
-- відновлення пароля — тобто з усього, що вважає рядок у auth.users живою людиною.
--
-- Чесніша модель: у імпортованої події організатора немає, а на картці стоїть назва джерела.
-- Саме це й показує UI («Афіша · <джерело>»), тож модель тепер збігається з тим, що бачить око.

alter table public.events alter column organizer_id drop not null;

-- Натомість обов'язковість переїжджає туди, де вона справді потрібна: подія, до якої можна
-- приєднатися, зобов'язана мати живого організатора, бо саме він відповідає за кімнату.
alter table public.events add constraint events_community_has_organizer_ck
 check (origin <> 'community' or organizer_id is not null);

-- Проєкція: організатор може бути відсутній, і тоді ім'я бере джерело. Зміна типу не потрібна —
-- склад полів той самий, тож перебудовуємо лише саму функцію.
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
 -- Приховування за блокуванням і обмеженням акаунта стосується лише подій із живим організатором:
 -- у імпорту його немає, тож і ховати немає за ким.
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$$;

-- has_event_access читає organizer_id для приватного доступу; при null порівняння дає null, тобто
-- «не свій», що і є правильною відповіддю. Окремої правки не потребує.

-- Джерело більше не потребує акаунта.
alter table public.event_sources alter column organizer_id drop not null;
comment on column public.event_sources.organizer_id is
 'Необов''язково. Заповнюється лише для партнерських джерел, які ведуть події від імені справжнього акаунта.';

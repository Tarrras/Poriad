-- Лише перегляд: що сховає hide_user_events_before_review.sql, і чи знайдено демо-подію.
select e.id, e.title, e.starts_at, e.ends_at, p.display_name as organizer,
  (e.title like 'Демо для перевірки застосунку%' and u.email = 'vtaras15@gmail.com') as keep_demo
from public.events e
join public.profiles p on p.id = e.organizer_id
join auth.users u on u.id = e.organizer_id
where e.origin = 'community' and e.status = 'published' and e.ends_at > now()
order by keep_demo desc, e.starts_at;

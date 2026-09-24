-- Ховає на час рев'ю App Store майбутні й поточні спільнотні події, крім демо-події для рецензента.
-- Завершені не чіпає. Приховування = status 'hidden', як у модерації: подія зникає з мапи й пошуку,
-- пушів немає. Відкат — UPDATE з id, які повертає цей запит (див. кінець файлу).
with demo as (
  select e.id from public.events e join auth.users u on u.id = e.organizer_id
  where u.email = 'vtaras15@gmail.com' and e.title like 'Демо для перевірки застосунку%'
)
update public.events e set status = 'hidden', updated_at = now()
where e.origin = 'community' and e.status = 'published' and e.ends_at > now()
  and e.id not in (select id from demo)
returning e.id, e.title, e.starts_at;

-- Відкат (підставити id з результату):
-- update public.events set status='published', updated_at=now() where status='hidden' and id in ('…','…');

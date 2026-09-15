-- Категорія comedy: стендап падав в `art` разом із театром, а це головна пропозиція для
-- аудиторії 22–35. Перелік категорій зашитий ще в домені й клієнтах: без їхніх правок категорія
-- буде без значка. Спершу розширюємо CHECK, потім backfill.

alter table public.events drop constraint events_category_check;
alter table public.events add constraint events_category_check
 check (category in ('music','sport','art','food','games','outdoors','social','comedy'));

-- Уподобання зберігають ті самі мітки: перелік має збігатися.
alter table public.user_preferences drop constraint user_preferences_categories_check;
alter table public.user_preferences add constraint user_preferences_categories_check
 check (categories <@ array['music','sport','art','food','games','outdoors','social','comedy']::text[]);

-- Backfill лише для `import` і лише за явними словами в заголовку: спільнотні події обрали категорію самі.
update public.events
set category = 'comedy', updated_at = now()
where origin = 'import'
  and category = 'art'
  and (
    title ~* '(стендап|стенд-ап|stand.?up|імпровіз|импровиз|відкритий мікрофон|open mic)'
    or title ~* '(комік|comedy|гумористичн|жарт)'
  );

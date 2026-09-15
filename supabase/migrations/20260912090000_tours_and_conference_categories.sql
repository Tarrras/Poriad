-- Категорії tours і conference, знайдені звітом `tools/ingest/report.category_gaps`: екскурсії
-- займали половину `outdoors` і ховались у `social`, конференції (`BusinessEvent`,
-- `EducationEvent`) лежали поруч із побаченнями. Backfill не потрібен: наступний обхід перезапише
-- категорію через `on conflict ... do update`.

alter table public.events drop constraint events_category_check;
alter table public.events add constraint events_category_check
 check (category in ('music','sport','art','food','games','outdoors','social','comedy','kids',
                     'tours','conference'));

alter table public.user_preferences drop constraint user_preferences_categories_check;
alter table public.user_preferences add constraint user_preferences_categories_check
 check (categories <@ array['music','sport','art','food','games','outdoors','social','comedy','kids',
                           'tours','conference']::text[]);

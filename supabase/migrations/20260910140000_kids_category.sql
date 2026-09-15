-- Категорія kids: знайдена звітом `tools/ingest/report.category_gaps` за типом schema.org
-- (`ChildrensEvent` — 15% кошика `art`). Backfill не потрібен: наступний обхід перезапише
-- категорію через `on conflict ... do update`.

alter table public.events drop constraint events_category_check;
alter table public.events add constraint events_category_check
 check (category in ('music','sport','art','food','games','outdoors','social','comedy','kids'));

alter table public.user_preferences drop constraint user_preferences_categories_check;
alter table public.user_preferences add constraint user_preferences_categories_check
 check (categories <@ array['music','sport','art','food','games','outdoors','social','comedy','kids']::text[]);

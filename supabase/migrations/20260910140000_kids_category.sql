-- Девʼята категорія: kids.
--
-- Знайдено не на око, а звітом `tools/ingest/report.category_gaps`: `ChildrensEvent` дає 91 подію
-- по пʼятьох містах — 15% кошика `art`. Дитяча програма сиділа поруч із драмою рівно так, як
-- стендап сидів там до виділення.
--
-- Сигнал спрацював на рівні ТИПУ schema.org, а не слів у заголовку. Це важливо: перевірка
-- показала, що за словами стендап НЕ знаходився — заголовки надто різні («Батя 2», «Просмажка
-- Раміни»). Тип знаходить обидва випадки, тому саме він у звіті головний.
--
-- Backfill не потрібен: наявні рядки перезапишуться наступним обходом через
-- `on conflict (source_id, source_uid) do update set category = excluded.category`.

alter table public.events drop constraint events_category_check;
alter table public.events add constraint events_category_check
 check (category in ('music','sport','art','food','games','outdoors','social','comedy','kids'));

alter table public.user_preferences drop constraint user_preferences_categories_check;
alter table public.user_preferences add constraint user_preferences_categories_check
 check (categories <@ array['music','sport','art','food','games','outdoors','social','comedy','kids']::text[]);

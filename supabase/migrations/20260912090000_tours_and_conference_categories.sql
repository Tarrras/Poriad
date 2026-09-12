-- Десята й одинадцята категорії: tours (Екскурсії) і conference (Конференції).
--
-- Обидві знайдені звітом `tools/ingest/report.category_gaps` на обході пʼяти міст 2026-09-11, а не
-- на око.
--
-- `tours` — 42 події. Детектор показав це найпрямішим чином: слово «екскурсія» займало 50% кошика
-- `outdoors`, тобто кошик «природа» насправді був кошиком екскурсій із домішкою походів. Решта
-- ховалась у `social`: 39 подій від lviv.travel — «Вілла Айва», «Дім Людкевича», «Вежа Латинської
-- катедри». Це прогулянки з гідом по місту, і ні «природа», ні «зустрічі» їх не описують.
--
-- `conference` — 14 подій. Тип `BusinessEvent` і `EducationEvent` раніше йшли в `social`, тобто в
-- той самий кошик, де лежать побачення наосліп. Людина, яка шукає «E-COMMERCE CONFERENCE», і
-- людина, яка шукає знайомства, дивляться в одне місце — і жодна з них не знаходить свого.
--
-- Чому саме ці дві, а не одна «освіта» чи «культура»: у кожної своя аудиторія і свій спосіб
-- пошуку. Екскурсію обирають за містом і вихідним днем, конференцію — за темою й наперед.
--
-- Backfill не потрібен: наявні рядки перезапишуться наступним обходом через
-- `on conflict (source_id, source_uid) do update set category = excluded.category`.

alter table public.events drop constraint events_category_check;
alter table public.events add constraint events_category_check
 check (category in ('music','sport','art','food','games','outdoors','social','comedy','kids',
                     'tours','conference'));

alter table public.user_preferences drop constraint user_preferences_categories_check;
alter table public.user_preferences add constraint user_preferences_categories_check
 check (categories <@ array['music','sport','art','food','games','outdoors','social','comedy','kids',
                           'tours','conference']::text[]);

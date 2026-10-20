# Знімок поточної схеми Supabase

[`current.sql`](current.sql) — зліпок бази **для читання**: композитні типи, 30 таблиць (стовпці, обмеження, індекси, RLS, політики, тригери, гранти), представлення та всі 130 функцій схем `public` і `private`. Навіщо: щоб знайти чинне визначення RPC, не перечитуючи 55 міграцій. Наприклад, `private.update_event` і `public.search_events_in_view` оголошені в 7 міграціях кожна, `private.event_rows` і `private.create_event` — у 6; тут — рівно та версія, що працює в базі.

**Це не міграція й не джерело правди.** Джерело правди — [`../migrations/`](../migrations/): схему змінюють лише новою міграцією, `current.sql` руками не редагують і не виконують. Знімок лише показує, що вийшло після всіх міграцій.

## Звідки і коли

| | |
|---|---|
| Знято | 2026-10-20 (перший знімок — 2026-10-19) |
| Джерело | prod `tzdogzdvctlumsqlqskr` (`EventOrganiztor`), лише `SELECT` до каталогу Postgres (`pg_get_functiondef`, `pg_get_constraintdef`, `pg_indexes`, `pg_policies`, `pg_get_triggerdef`, ACL) через Supabase MCP. Жодного DDL/DML, рядків даних і секретів у файлі немає |
| Міграції | у реєстрі prod 55, у `supabase/migrations` 55 файлів, назви збігаються; остання — `20261020120000_push_quiet_hours` |
| Звірка з dev | 2026-10-20 dev теж має всі 55; звірку відбитків нижче не повторювали. Станом на 2026-10-19 dev `ojadoyxeahepycpmjuvf` мав усі 54. Таблиці, стовпці, обмеження, індекси, RLS, політики й тригери на dev і prod ідентичні (порівняно md5 відбитків), функцій по 128. Тіла чотирьох функцій різняться **лише коментарями**: на prod немає коментарів у `discover_events` і `private.decide_member`, на dev — у `event_safety` і `private.follow`. У файлах міграцій коментарі є в усіх чотирьох, тож у знімку з prod двох коментарів не буде |

Знімок беремо з prod: це те, що бачать користувачі. Поки міграція застосована лише на dev, знімок відстає — це очікувано.

## Що в `current.sql`

Дев'ять розділів, відділених двома порожніми рядками:

1. Шапка з умовностями.
2. Розширення (`pg_cron`, `pg_net`, `postgis` у схемі `gis`, `supabase_vault`, …) — коментарями.
3. Композитні типи, якими RPC повертають результат (`event_result`, `message_result`, …).
4. 21 таблиця `public`: стовпці, обмеження, індекси (крім тих, що стоять за обмеженнями), RLS, політики, тригери, гранти.
5. 8 таблиць `private`.
6. Представлення (`private.followed_events`).
7. Створене проєктом у схемах Supabase: тригер на `auth.users` (`private.handle_new_user`), бакет `event-images` і політики на `storage.objects`. Решта `auth`, `storage`, `extensions`, `realtime` не знімалась.
8. Заплановані завдання `pg_cron`.
9. Функції: спершу `public` (RPC для клієнтів і тонкі обгортки над `private`), потім `private` (реалізації, перевірки, тригерні функції); тексти дослівно з `pg_get_functiondef`.

Умовності:

- Назви без схеми в `REFERENCES` і представленні — це `public` (так їх друкує Postgres).
- `GRANT` показано лише для `anon`, `authenticated` і `PUBLIC`; відсутній `GRANT` = привілеїв у цих ролей немає. `service_role` і `postgres` не перелічені.
- Рядок `-- execute:` перед функцією — хто з `anon` / `authenticated` має `EXECUTE` фактично (з урахуванням `PUBLIC`); `—` = нікому.
- Таблиці позначені рядком `-- table: схема.назва`, функції — рядком `-- execute:`: за ними зручно шукати.

```bash
grep -n "FUNCTION private.update_event" supabase/schema/current.sql   # чинне визначення
grep -n -A12 "^-- table: public.events$" supabase/schema/current.sql  # таблиця з обмеженнями й політиками
```

## Як перегенерувати

Увесь файл будує один `SELECT` — [`snapshot.sql`](snapshot.sql). Потрібен `psycopg[binary]` (як для `tools/apply_sql.py`) і рядок зʼєднання prod; транзакція `READ ONLY`, тож записати щось неможливо:

```bash
python3 - <<'PY'
import os, pathlib, psycopg
with psycopg.connect(os.environ["SUPABASE_DB_URL"]) as conn:   # prod; рядок із Dashboard → Connect
    conn.read_only = True
    text = conn.execute(pathlib.Path("supabase/schema/snapshot.sql").read_text("utf-8")).fetchone()[0]
pathlib.Path("supabase/schema/current.sql").write_text(text + "\n", encoding="utf-8")
PY
python3 supabase/schema/function_map.py   # таблиця нижче; вставити замість старої
git diff --stat supabase/schema           # у diff — лише те, що змінила схема, і дата в шапці
```

Робити після того, як нова міграція застосована на prod, і класти в той самий коміт. Той самий `SELECT` можна виконати й через Supabase MCP `execute_sql`, але відповідь — понад 140 КБ, тож зручніше напряму.

## Мапа «функція → міграція»

Остання міграція, яка оголошує функцію з **чинною сигнатурою** (`create or replace function` / `create function` у `supabase/migrations`; пізніший файл перекриває ранішій). «Міграцій» — у скількох файлах оголошено функцію з такою назвою, включно зі старими сигнатурами, які вже замінені: `create_event` / `update_event` мали іншу сигнатуру до `p_min_age`, потім до `p_contact_url`, `rate_event` — до `p_tags`, `private.is_listed` — до `p_title`. Таких замінених сигнатур одинадцять, у базі їх немає. Чинні функції всі 128 знайшлись у міграціях. Перевантажених назв зараз немає, тому параметри в таблиці не показано.

Таблицю друкує `python3 supabase/schema/function_map.py`; станом на 2026-10-20:

### Схема `public` (56)

| Функція | Остання міграція | Міграцій | EXECUTE |
|---|---|---:|---|
| `approve_member` | `20260906195750_safety_age_and_reports.sql` | 1 | authenticated |
| `artist_events` | `20261006130000_drop_in_fairs.sql` | 3 | anon, authenticated |
| `cancel_event` | `20260905101755_poruch_initial.sql` | 1 | authenticated |
| `companions` | `20260928140000_companions.sql` | 1 | anon, authenticated |
| `create_companion` | `20260928140000_companions.sql` | 1 | authenticated |
| `create_event` | `20260915223806_contact_link_and_request_feed.sql` | 3 | authenticated |
| `decline_member` | `20260906195750_safety_age_and_reports.sql` | 1 | authenticated |
| `delete_message` | `20260915225504_event_chat.sql` | 1 | authenticated |
| `delete_my_account` | `20260917100100_delete_my_account.sql` | 1 | authenticated |
| `discover_events` | `20260911070031_discovery_index_and_cards.sql` | 1 | anon, authenticated |
| `event_attendees` | `20260906195750_safety_age_and_reports.sql` | 2 | authenticated |
| `event_cards_by_ids` | `20260911070031_discovery_index_and_cards.sql` | 1 | anon, authenticated |
| `event_details` | `20260907120000_event_ingestion.sql` | 3 | anon, authenticated |
| `event_messages` | `20260915225504_event_chat.sql` | 1 | authenticated |
| `event_ratings` | `20260926120000_rating_tags.sql` | 2 | authenticated |
| `event_requests` | `20260906200401_event_requests_invoker.sql` | 2 | authenticated |
| `event_safety` | `20260928100000_shelters.sql` | 1 | anon, authenticated |
| `events_in_view` | `20260907120000_event_ingestion.sql` | 3 | anon, authenticated |
| `export_my_data` | `20260928160000_follows.sql` | 3 | authenticated |
| `follow` | `20260928160000_follows.sql` | 1 | authenticated |
| `follow_events` | `20260928160000_follows.sql` | 1 | authenticated |
| `follows_seen` | `20261015120000_follow_fresh.sql` | 1 | authenticated |
| `join_event` | `20260905101755_poruch_initial.sql` | 1 | authenticated |
| `join_waitlist` | `20260905221357_event_waitlist.sql` | 1 | authenticated |
| `leave_event` | `20260905101755_poruch_initial.sql` | 1 | authenticated |
| `leave_waitlist` | `20260905221357_event_waitlist.sql` | 1 | authenticated |
| `mark_chat_read` | `20260916092710_chat_unread.sql` | 1 | authenticated |
| `moderate_event` | `20260917100200_ugc_moderation.sql` | 1 | authenticated |
| `moderate_message` | `20260917100200_ugc_moderation.sql` | 1 | authenticated |
| `moderate_profile` | `20260924100000_profiles.sql` | 1 | authenticated |
| `moderate_rating` | `20260923100100_ugc_ratings_and_limits.sql` | 1 | authenticated |
| `moderate_user` | `20260917100200_ugc_moderation.sql` | 1 | authenticated |
| `moderation_queue` | `20260923100100_ugc_ratings_and_limits.sql` | 2 | authenticated |
| `my_chat_unread` | `20260923100200_read_exposure_hardening.sql` | 2 | authenticated |
| `my_events` | `20260926100000_my_events_waitlist_and_ratings.sql` | 4 | authenticated |
| `my_follows` | `20260928160000_follows.sql` | 1 | authenticated |
| `my_join_requests` | `20260915223806_contact_link_and_request_feed.sql` | 1 | authenticated |
| `my_ratings` | `20260926100000_my_events_waitlist_and_ratings.sql` | 1 | authenticated |
| `my_waitlist` | `20260905221357_event_waitlist.sql` | 1 | authenticated |
| `place_events` | `20261006130000_drop_in_fairs.sql` | 3 | anon, authenticated |
| `profile_card` | `20260924100000_profiles.sql` | 1 | authenticated |
| `rate_event` | `20260926120000_rating_tags.sql` | 2 | authenticated |
| `register_push_token` | `20260916115335_push_notifications.sql` | 1 | authenticated |
| `report_event` | `20260906195750_safety_age_and_reports.sql` | 1 | authenticated |
| `report_message` | `20260917110000_abuse_limits.sql` | 2 | authenticated |
| `report_rating` | `20260923100100_ugc_ratings_and_limits.sql` | 1 | authenticated |
| `report_user` | `20260906195750_safety_age_and_reports.sql` | 1 | authenticated |
| `resolve_report` | `20260917100200_ugc_moderation.sql` | 1 | authenticated |
| `search_artists` | `20261008120000_series_counts.sql` | 5 | anon, authenticated |
| `search_events_in_view` | `20261006130000_drop_in_fairs.sql` | 7 | anon, authenticated |
| `search_places` | `20261008120000_series_counts.sql` | 4 | anon, authenticated |
| `send_message` | `20260915225504_event_chat.sql` | 1 | authenticated |
| `set_birth_date` | `20260906195750_safety_age_and_reports.sql` | 1 | authenticated |
| `unfollow` | `20260928160000_follows.sql` | 1 | authenticated |
| `unregister_push_token` | `20260916115335_push_notifications.sql` | 1 | authenticated |
| `update_event` | `20260915223806_contact_link_and_request_feed.sql` | 3 | authenticated |

### Схема `private` (74)

| Функція | Остання міграція | Міграцій | EXECUTE |
|---|---|---:|---|
| `account_active` | `20260906195750_safety_age_and_reports.sql` | 1 | anon, authenticated |
| `age_of` | `20260906195750_safety_age_and_reports.sql` | 1 | — |
| `age_years` | `20260906195750_safety_age_and_reports.sql` | 1 | — |
| `artist_source_rank` | `20261002120000_artists.sql` | 1 | anon, authenticated |
| `assert_age_limits` | `20260906195750_safety_age_and_reports.sql` | 1 | — |
| `assert_can_join` | `20260907120000_event_ingestion.sql` | 2 | — |
| `assert_clean_text` | `20260917100200_ugc_moderation.sql` | 2 | — |
| `assert_contact_url` | `20260915223806_contact_link_and_request_feed.sql` | 1 | — |
| `assert_event_editable` | `20260907120000_event_ingestion.sql` | 1 | — |
| `assert_image_url` | `20260923100200_read_exposure_hardening.sql` | 2 | — |
| `assert_join_rate` | `20260923100000_account_deletion.sql` | 2 | — |
| `assert_moderator` | `20260917100200_ugc_moderation.sql` | 1 | — |
| `assert_organizer` | `20260917100000_organizer_null_guard.sql` | 1 | — |
| `attach_report_message` | `20260915225504_event_chat.sql` | 1 | authenticated |
| `blocked_between` | `20260906195750_safety_age_and_reports.sql` | 1 | anon, authenticated |
| `can_see_profile` | `20260923100200_read_exposure_hardening.sql` | 1 | authenticated |
| `can_view_members` | `20260906195750_safety_age_and_reports.sql` | 2 | authenticated |
| `cancel_event` | `20260917100000_organizer_null_guard.sql` | 2 | authenticated |
| `check_event_text` | `20260923140000_event_text_lengths.sql` | 1 | — |
| `create_companion` | `20261008130000_companion_live_parent.sql` | 2 | authenticated |
| `create_event` | `20260923100100_ugc_ratings_and_limits.sql` | 6 | authenticated |
| `decide_member` | `20260917100000_organizer_null_guard.sql` | 2 | authenticated |
| `delete_message` | `20260923100000_account_deletion.sql` | 3 | authenticated |
| `delete_my_account` | `20260923100000_account_deletion.sql` | 2 | authenticated |
| `discover_index` | `20261006130000_drop_in_fairs.sql` | 4 | anon, authenticated |
| `event_cards` | `20261002120000_artists.sql` | 3 | anon, authenticated |
| `event_has_space` | `20260911070031_discovery_index_and_cards.sql` | 3 | anon, authenticated |
| `event_ratings` | `20260926120000_rating_tags.sql` | 3 | authenticated |
| `event_rows` | `20260928140000_companions.sql` | 6 | anon, authenticated |
| `file_report` | `20260923100000_account_deletion.sql` | 2 | authenticated |
| `file_report_message` | `20260923100000_account_deletion.sql` | 2 | authenticated |
| `flush_deferred_pushes` | `20261020120000_push_quiet_hours.sql` | 1 | — |
| `follow` | `20261002120000_artists.sql` | 2 | authenticated |
| `follow_events` | `20261008120000_series_counts.sql` | 3 | authenticated |
| `follows_seen` | `20261015120000_follow_fresh.sql` | 1 | authenticated |
| `guard_companion` | `20260928140000_companions.sql` | 1 | — |
| `handle_new_user` | `20261007120000_oauth_display_name.sql` | 3 | — |
| `has_event_access` | `20260905101755_poruch_initial.sql` | 1 | anon, authenticated |
| `image_url_prefix` | `20260923100200_read_exposure_hardening.sql` | 1 | — |
| `is_discoverable` | `20260907120000_event_ingestion.sql` | 1 | anon, authenticated |
| `is_listed` | `20261006130000_drop_in_fairs.sql` | 2 | anon, authenticated |
| `join_event` | `20260917110000_abuse_limits.sql` | 4 | authenticated |
| `join_waitlist` | `20260917110000_abuse_limits.sql` | 3 | authenticated |
| `leave_event` | `20260905221357_event_waitlist.sql` | 2 | authenticated |
| `leave_waitlist` | `20260905221357_event_waitlist.sql` | 1 | authenticated |
| `mark_chat_read` | `20260916092710_chat_unread.sql` | 1 | authenticated |
| `min_signup_age` | `20260906195750_safety_age_and_reports.sql` | 1 | — |
| `my_follows` | `20261015120000_follow_fresh.sql` | 4 | authenticated |
| `my_ratings` | `20260926100000_my_events_waitlist_and_ratings.sql` | 1 | authenticated |
| `notify_artist_follows` | `20261008120000_series_counts.sql` | 2 | — |
| `notify_place_follows` | `20260928160000_follows.sql` | 1 | — |
| `notify_push` | `20261020120000_push_quiet_hours.sql` | 2 | — |
| `on_event_changed` | `20260928120000_event_change_push.sql` | 1 | — |
| `on_event_published` | `20260928160000_follows.sql` | 1 | — |
| `on_member_requested` | `20260923130000_push_on_join.sql` | 2 | — |
| `on_message_inserted` | `20260916115335_push_notifications.sql` | 1 | — |
| `on_profile_write` | `20260924100000_profiles.sql` | 2 | — |
| `on_report_filed` | `20260923100100_ugc_ratings_and_limits.sql` | 2 | — |
| `on_user_blocked` | `20260923100200_read_exposure_hardening.sql` | 1 | — |
| `owns_image_path` | `20260924100000_profiles.sql` | 2 | authenticated |
| `place_source_rank` | `20260925120000_places.sql` | 1 | anon, authenticated |
| `profile_card` | `20260924100000_profiles.sql` | 1 | authenticated |
| `promote_waitlist` | `20260907150000_listing_has_no_capacity.sql` | 3 | — |
| `push_endpoint` | `20260916115335_push_notifications.sql` | 1 | — |
| `quiet_hours` | `20261020120000_push_quiet_hours.sql` | 1 | — |
| `rate_event` | `20260927100000_rating_tags_by_category.sql` | 4 | authenticated |
| `register_push_token` | `20260917110000_abuse_limits.sql` | 2 | authenticated |
| `report_rating` | `20260923100100_ugc_ratings_and_limits.sql` | 1 | authenticated |
| `retire_finished_imports` | `20260915120000_stale_finished_imports.sql` | 1 | — |
| `send_message` | `20260923100100_ugc_ratings_and_limits.sql` | 3 | authenticated |
| `set_birth_date` | `20260906195750_safety_age_and_reports.sql` | 1 | authenticated |
| `unfollow` | `20260928160000_follows.sql` | 1 | authenticated |
| `unregister_push_token` | `20260916115335_push_notifications.sql` | 1 | authenticated |
| `update_event` | `20260923100100_ugc_ratings_and_limits.sql` | 7 | authenticated |

## Що видно зі знімка

- `public.artists` і `public.places`: таблицям видано **усі** привілеї (`INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, …) для `anon` і `authenticated`. Запис неможливий лише тому, що RLS має єдину політику `SELECT`; решта таблиць (`events`, `profiles`, `event_sources`, …) має вузькі гранти на потрібні стовпці. Знімок цього не змінює — звужувати варто окремою міграцією.

-- Статистика прогонів імпорту для аналізу агентом: рядок на пару джерело+місто і всі елементи
-- прогону з тим, як їх розібрано. Таблиці з 20260907120000 досі пустували; дамп tools.ingest
-- тепер пише в них наприкінці, у тій самій транзакції, що й дані. Тримаємо STATS_KEEP_DAYS
-- (emit.py) — старіше дамп видаляє сам.

alter table private.ingest_runs
  add column if not exists run_id uuid,      -- спільний для всього обходу, = events.ingest_run_id
  add column if not exists city text,        -- null — для перевірки статусів Karabas (без міста)
  add column if not exists report jsonb;     -- повний запис звіту джерела (report.json → sources[])

create index if not exists ingest_runs_run_idx on private.ingest_runs(run_id);
create index if not exists ingest_runs_finished_idx on private.ingest_runs(finished_at desc);

-- Конвеєр позначає злиті копії як duplicate; 'deduped' лишається для сумісності.
alter table private.ingest_items drop constraint if exists ingest_items_stage_check;
alter table private.ingest_items add constraint ingest_items_stage_check check (stage in
  ('fetched','parsed','normalized','geocoded','deduped','duplicate','published','rejected','review'));

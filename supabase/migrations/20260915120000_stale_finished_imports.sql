-- Завершені імпортовані події лишались `live` назавжди: видача їх ховала умовою `ends_at > now()`,
-- але таблиця росла на ~50 рядків на день, а статус брехав. Позначаємо `stale`, не видаляємо:
-- збережена подія лишається з чесною позначкою (docs/event-ingestion.md, S7).
--
-- Тиждень запасу: перенесені сеанси джерело часто публікує під тим самим ключем із новою датою,
-- і наступний дамп повертає такий рядок у `live` через upsert. Спільнотні події не чіпаємо:
-- їхнього `import_status` немає, а історія участі — власність організатора.

create or replace function private.retire_finished_imports(p_grace interval default interval '7 days')
returns integer language sql security definer set search_path='' as $$
 with done as (
  update public.events set import_status='stale', updated_at=now()
  where origin <> 'community' and import_status='live' and ends_at < now() - p_grace
  returning 1)
 select count(*)::integer from done;
$$;
revoke all on function private.retire_finished_imports(interval) from public, anon, authenticated;

comment on function private.retire_finished_imports(interval) is
 'Імпортовані події, що закінчились понад p_grace тому → stale. Викликається наприкінці кожного дампу tools.ingest.';

-- Дамп 2026-09-15 ще не мав цього кроку: приберемо накопичене одразу.
select private.retire_finished_imports();

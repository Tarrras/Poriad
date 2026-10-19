-- Генерує весь supabase/schema/current.sql одним текстовим значенням (без кінцевого \n).
-- Лише SELECT до каталогу Postgres: ні DDL, ні DML, ні рядків даних. Запуск — у supabase/schema/README.md.
with
policy_fmt as (
  select p.schemaname, p.tablename, p.policyname,
         format(E'CREATE POLICY %s ON %s.%s AS %s FOR %s TO %s', quote_ident(p.policyname), p.schemaname, p.tablename,
                p.permissive, p.cmd, array_to_string(p.roles, ', '))
         || coalesce(E'\n  USING (' || p.qual || ')', '')
         || coalesce(E'\n  WITH CHECK (' || p.with_check || ')', '') || ';' as ddl
  from pg_policies p
),
tbl as (
  select c.oid, n.nspname s, c.relname r, c.relrowsecurity rls
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private') and c.relkind = 'r'
),
tbl_ddl as (
  select s, '-- table: ' || s || '.' || r || E'\n'
    || 'CREATE TABLE ' || s || '.' || r || E' (\n'
    || (select string_agg('  ' || quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod)
          || case when a.attgenerated = 's' then ' GENERATED ALWAYS AS (' || pg_get_expr(d.adbin, d.adrelid) || ') STORED'
                  when a.attidentity in ('a', 'd') then ' GENERATED ' || case a.attidentity when 'a' then 'ALWAYS' else 'BY DEFAULT' end || ' AS IDENTITY'
                  when d.adbin is not null then ' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid) else '' end
          || case when a.attnotnull then ' NOT NULL' else '' end, E',\n' order by a.attnum)
        from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
        where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped)
    || coalesce(E',\n' || (select string_agg('  CONSTRAINT ' || quote_ident(k.conname) || ' ' || pg_get_constraintdef(k.oid), E',\n'
          order by case k.contype when 'p' then 0 when 'u' then 1 when 'f' then 2 else 3 end, k.conname::text collate "C")
        from pg_constraint k where k.conrelid = t.oid), '')
    || E'\n);'
    || coalesce(E'\n' || (select string_agg(pg_get_indexdef(i.indexrelid) || ';', E'\n' order by c2.relname::text collate "C")
        from pg_index i join pg_class c2 on c2.oid = i.indexrelid
        where i.indrelid = t.oid and not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid and k.conrelid = t.oid)), '')
    || case when t.rls then E'\nALTER TABLE ' || s || '.' || r || ' ENABLE ROW LEVEL SECURITY;' else '' end
    || coalesce(E'\n' || (select string_agg(f.ddl, E'\n' order by f.policyname collate "C") from policy_fmt f where f.schemaname = s and f.tablename = r), '')
    || coalesce(E'\n' || (select string_agg(pg_get_triggerdef(g.oid) || ';', E'\n' order by g.tgname::text collate "C")
        from pg_trigger g where g.tgrelid = t.oid and not g.tgisinternal), '')
    || coalesce(E'\n' || (select string_agg(format('GRANT %s ON %s.%s TO %s;', q.privs, s, r, q.grantee), E'\n' order by q.grantee)
        from (select case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end grantee,
                     string_agg(x.privilege_type, ', ' order by x.privilege_type) privs
              from aclexplode((select relacl from pg_class where oid = t.oid)) x group by 1) q
        where q.grantee in ('anon', 'authenticated', 'PUBLIC')), '')
    || coalesce(E'\n' || (select string_agg(format('GRANT %s (%s) ON %s.%s TO %s;', q.privilege_type, q.cols, s, r, q.grantee), E'\n' order by q.grantee, q.privilege_type)
        from (select case when x.grantee = 0 then 'PUBLIC' else x.grantee::regrole::text end grantee, x.privilege_type,
                     string_agg(a.attname, ', ' order by a.attnum) cols
              from pg_attribute a, aclexplode(a.attacl) x where a.attrelid = t.oid and a.attacl is not null group by 1, 2) q
        where q.grantee in ('anon', 'authenticated', 'PUBLIC')), '') as ddl,
    r
  from tbl t
),
fn as (
  select n.nspname s, p.proname, p.oid::regprocedure::text sig,
         '-- execute: ' || coalesce((select string_agg(r, ', ' order by r) from unnest(array['anon', 'authenticated']) r
                                     where has_function_privilege(r, p.oid, 'execute')), '-') || E'\n'
         || rtrim(pg_get_functiondef(p.oid), E'\n') || ';' as ddl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prokind in ('f', 'p')
),
secs(ord, txt) as (
  select 1, $h$-- =============================================================================
-- Поряд / Poruch — знімок поточної схеми Supabase (public + private)
--
-- Лише для читання. Це НЕ міграція і не призначений для виконання: джерело правди —
-- supabase/migrations/*.sql, а цей файл показує, що вийшло в базі після всіх міграцій.
-- Опис, мапа «функція → міграція» і спосіб перегенерації — у supabase/schema/README.md.
--
$h$ || format(E'-- Знято: %s; у реєстрі міграцій бази — %s, остання %s.\n', current_date,
              (select count(*) from supabase_migrations.schema_migrations),
              (select version || '_' || name from supabase_migrations.schema_migrations order by version desc limit 1))
  || $h$-- Лише SELECT-запити до каталогу (pg_get_functiondef, pg_get_constraintdef, pg_indexes,
-- pg_policies, pg_get_triggerdef, ACL). Рядків даних і секретів тут немає.
--
-- Умовності:
--   * назви без схеми в REFERENCES / представленнях — це схема public (так друкує pg_get_*);
--   * GRANT показано лише для ролей anon, authenticated і PUBLIC; відсутній GRANT = привілеїв
--     у цих ролей немає (service_role і postgres обходять RLS і тут не перелічені);
--   * рядок `-- execute:` перед функцією — хто з anon / authenticated має EXECUTE фактично
--     (враховує PUBLIC); `-` = нікому з них;
--   * схеми, якими керує Supabase (auth, storage, extensions, realtime), не знімались, окрім
--     створеного проєктом тригера на auth.users і політик на storage.objects.
-- =============================================================================$h$
  union all
  select 2, E'-- ===== Розширення (CREATE EXTENSION у міграціях / Dashboard) =================\n'
    || (select string_agg(format('--   %s %s (%s)', extname, extversion, extnamespace::regnamespace), E'\n' order by extname::text collate "C")
        from pg_extension where extname <> 'plpgsql')
  union all
  select 3, E'-- ===== Композитні типи (результати RPC) ======================================\n\n'
    || (select string_agg(format('CREATE TYPE %s.%s AS (%s);', n.nspname, t.typname,
          (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum)
           from pg_attribute a where a.attrelid = t.typrelid and a.attnum > 0 and not a.attisdropped)),
          E'\n\n' order by n.nspname::text collate "C", t.typname::text collate "C")
        from pg_type t join pg_namespace n on n.oid = t.typnamespace join pg_class c on c.oid = t.typrelid
        where n.nspname in ('public', 'private') and t.typtype = 'c' and c.relkind = 'c')
  union all
  select 4, format(E'-- ===== Таблиці схеми public (%s) =============================================\n', count(*))
    || E'-- Для кожної: стовпці, обмеження, індекси (крім тих, що стоять за обмеженнями), RLS,\n'
    || E'-- політики, тригери, GRANT.\n\n' || string_agg(ddl, E'\n\n' order by r::text collate "C")
  from tbl_ddl where s = 'public'
  union all
  select 5, format(E'-- ===== Таблиці схеми private (%s) =============================================\n', count(*))
    || E'-- Схема private не відкрита через Data API; доступ — з definer-функцій (власник postgres).\n\n'
    || string_agg(ddl, E'\n\n' order by r::text collate "C")
  from tbl_ddl where s = 'private'
  union all
  select 6, E'-- ===== Представлення =========================================================\n\n'
    || (select string_agg('CREATE OR REPLACE VIEW ' || n.nspname || '.' || c.relname || ' AS ' || pg_get_viewdef(c.oid, true),
          E'\n\n' order by n.nspname::text collate "C", c.relname::text collate "C")
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname in ('public', 'private') and c.relkind = 'v')
  union all
  select 7, E'-- ===== Створене проєктом у схемах, якими керує Supabase ======================\n\n'
    || E'-- Тригер на auth.users (єдиний, створений проєктом): профіль, налаштування й account_facts.\n'
    || (select string_agg(pg_get_triggerdef(g.oid) || ';', E'\n' order by g.tgname::text collate "C")
        from pg_trigger g join pg_class c on c.oid = g.tgrelid join pg_namespace n on n.oid = c.relnamespace
        join pg_proc p on p.oid = g.tgfoid
        where n.nspname = 'auth' and c.relname = 'users' and not g.tgisinternal and p.pronamespace = 'private'::regnamespace)
    || E'\n\n'
    || (select string_agg(format('-- Бакет Storage: %s — %s, ліміт %s байтів, MIME %s.', b.id,
          case when b.public then 'public' else 'private' end, b.file_size_limit, array_to_string(b.allowed_mime_types, ', ')),
          E'\n' order by b.id collate "C") from storage.buckets b)
    || E'\n-- Політики на storage.objects (шлях `<user-id>/<event-id або avatar>/<файл>`, див. private.owns_image_path):\n'
    || (select string_agg(f.ddl, E'\n' order by f.policyname collate "C") from policy_fmt f
        where f.schemaname = 'storage' and f.tablename = 'objects')
  union all
  select 8, E'-- ===== Заплановані завдання (pg_cron) =========================================\n'
    || (select string_agg(format('--   %s   %s   %s%s', j.jobname, j.schedule, j.command, case when j.active then '' else ' (вимкнено)' end),
          E'\n' order by j.jobname collate "C") from cron.job j)
  union all
  select 9, E'-- ===== Функції (public, потім private; за назвою) ============================\n'
    || format(E'-- %s функцій: %s у public (RPC для клієнтів і тонкі обгортки над private), %s у private\n',
              count(*), count(*) filter (where s = 'public'), count(*) filter (where s = 'private'))
    || E'-- (реалізації, перевірки, тригерні функції). Тексти — дослівно з pg_get_functiondef.\n\n'
    || string_agg(ddl, E'\n\n' order by (s = 'private'), proname::text collate "C", sig collate "C")
  from fn
)
select string_agg(txt, E'\n\n\n' order by ord) from secs;

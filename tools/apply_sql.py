"""Застосування SQL до Supabase прямим зʼєднанням з Postgres, без SQL Editor і без MCP.

    python3 tools/apply_sql.py migrations                 # що з supabase/migrations ще не застосовано
    python3 tools/apply_sql.py migrations --apply         # застосувати й записати в реєстр CLI
    python3 tools/apply_sql.py dump out.sql               # перевірити файл дампу конвеєра
    python3 tools/apply_sql.py dump out.sql --apply       # застосувати
    python3 tools/apply_sql.py dump out/ --apply          # усі *.sql у теці, за маніфестом або за іменем
    python3 tools/apply_sql.py dump out.manifest.json --apply
    python3 tools/apply_sql.py all out/ --apply           # міграції, потім усі poruch-events-N.sql по черзі
    python3 tools/apply_sql.py run --apply                # згенерувати SQL у теку, застосувати, теку прибрати
    python3 tools/apply_sql.py run --apply -- --city Київ --agent   # усе після «--» іде в tools.ingest

Зʼєднання — з `SUPABASE_DB_URL` (або `DATABASE_URL`) у середовищі чи в `.env`. Беріть рядок
"Session pooler" або прямий з Dashboard → Connect: transaction pooler не тримає стан сесії,
а дампи й міграції — це довгі багатокомандні транзакції. Потрібен `psycopg[binary]`:

    python3 -m pip install "psycopg[binary]"

Без `--apply` скрипт лише читає: перевіряє файли, контрольні суми маніфесту й реєстр міграцій.
Реєстр — той самий, що в Supabase CLI: `supabase_migrations.schema_migrations`, тож CLI і цей
скрипт бачать одну історію. Міграцію вважаємо застосованою, якщо в реєстрі є її версія АБО
її назва: частину міграцій цього проєкту застосовано з Dashboard під іншими штампами часу.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = ROOT / "supabase" / "migrations"
ENV_FILE = ROOT / ".env"
URL_VARS = ("SUPABASE_DB_URL", "DATABASE_URL")

_MIGRATION_NAME = re.compile(r"^(\d{14})_(.+)\.sql$")
_COMMENT = re.compile(r"(--[^\n]*\n)|(/\*.*?\*/)", re.S)
_OWN_TRANSACTION = re.compile(r"^\s*(begin|start\s+transaction)\b", re.I)


# ---------------------------------------------------------------- зʼєднання

def _read_env_file(path: pathlib.Path) -> dict:
    """Мінімальний розбір .env: KEY=VALUE, лапки й коментарі. Без залежності від python-dotenv."""
    values = {}
    if not path.exists():
        return values
    for line in path.read_text("utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if value[:1] in "\"'" and value[-1:] == value[:1]:
            value = value[1:-1]
        values[key.strip()] = value
    return values


def database_url(explicit: str | None) -> str:
    if explicit:
        return explicit
    env = dict(_read_env_file(ENV_FILE))
    env.update(os.environ)
    for var in URL_VARS:
        if env.get(var):
            return env[var]
        if env.get(f"TEST_{var}") and var == "DATABASE_URL":
            return env[f"TEST_{var}"]
    raise SystemExit("Немає рядка зʼєднання: задайте SUPABASE_DB_URL у середовищі чи в .env, "
                     "або передайте --db-url. Dashboard → Connect → Session pooler.")


def connect(url: str, statement_timeout: str):
    try:
        import psycopg
    except ImportError:
        raise SystemExit('Потрібен драйвер: python3 -m pip install "psycopg[binary]"')
    try:
        conn = psycopg.connect(url, connect_timeout=15, autocommit=True,
                               application_name="poruch.apply_sql")
    except psycopg.OperationalError as exc:
        raise SystemExit(f"Не вдалося зʼєднатися: {str(exc).strip()}")
    # Не «0»: дамп великого міста йде хвилину-дві, але завислий запит не має тримати базу вічно.
    # SET не приймає параметрів запиту, тому set_config.
    conn.execute("select set_config('statement_timeout', %s, false)", (statement_timeout,))
    conn.execute("set lock_timeout = '30s'")
    return conn


def _redact(url: str) -> str:
    return re.sub(r"://([^:/@]+):[^@]*@", r"://\1:***@", url)


# ------------------------------------------------------------------- виконання

def has_own_transaction(sql: str) -> bool:
    """Чи файл сам відкриває транзакцію (дампи конвеєра — так, міграції — ні)."""
    return bool(_OWN_TRANSACTION.match(_COMMENT.sub("\n", sql)))


def run_sql(conn, sql: str, label: str) -> float:
    """Виконує файл цілком, однією транзакцією. Повертає тривалість у секундах.

    psycopg без параметрів шле текст простим протоколом, тож багато команд в одному виклику —
    штатний режим, як `psql -f`. Файл із власними begin/commit виконується в autocommit і сам
    керує межами транзакції; решту загортаємо ми, щоб половина міграції не лишилась у базі.
    """
    import psycopg
    started = time.monotonic()
    try:
        if has_own_transaction(sql):
            conn.execute(sql)
        else:
            with conn.transaction():
                conn.execute(sql)
    except psycopg.Error as exc:
        diag = exc.diag
        where = f" (рядок {diag.internal_position})" if diag.internal_position else ""
        detail = f"\n  {diag.message_detail}" if diag.message_detail else ""
        hint = f"\n  підказка: {diag.message_hint}" if diag.message_hint else ""
        raise SystemExit(f"✗ {label}: {diag.message_primary or exc}{where}{detail}{hint}\n"
                         "  Транзакцію відкочено; база в стані до цього файлу.")
    return time.monotonic() - started


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_sql(path: pathlib.Path) -> str:
    try:
        return path.read_text("utf-8")
    except UnicodeDecodeError as exc:
        raise SystemExit(f"✗ {path.name}: не UTF-8 (байт {exc.start}) — файл обрізано чи пошкоджено")


# -------------------------------------------------------------------- міграції

def ensure_ledger(conn) -> None:
    """Реєстр міграцій у форматі Supabase CLI. У живому проєкті вже є; у новому — створюємо."""
    conn.execute("create schema if not exists supabase_migrations")
    conn.execute("""create table if not exists supabase_migrations.schema_migrations (
        version text primary key, statements text[], name text)""")


def applied_migrations(conn) -> list[tuple[str, str]]:
    rows = conn.execute("select version, coalesce(name, '') from supabase_migrations.schema_migrations "
                        "order by version").fetchall()
    return [(v, n) for v, n in rows]


def local_migrations() -> list[tuple[str, str, pathlib.Path]]:
    found = []
    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        m = _MIGRATION_NAME.match(path.name)
        if not m:
            print(f"  пропускаю {path.name}: імʼя не у форматі <14 цифр>_<назва>.sql", file=sys.stderr)
            continue
        found.append((m.group(1), m.group(2), path))
    return found


def cmd_migrations(args) -> int:
    conn = connect(database_url(args.db_url), args.statement_timeout)
    if args.mark_applied:
        return mark_applied(conn, args.mark_applied)
    return apply_migrations(conn, apply=args.apply, only=args.only)


def mark_applied(conn, needle: str) -> int:
    """Записати міграцію в реєстр без виконання: для тих, що вже зроблені з Dashboard вручну."""
    ensure_ledger(conn)
    applied = applied_migrations(conn)
    versions = {v for v, _ in applied}
    names = {n for _, n in applied if n}
    hits = [(v, n, p) for v, n, p in local_migrations()
            if (needle in v or needle in n) and v not in versions and n not in names]
    if len(hits) != 1:
        raise SystemExit(f"--mark-applied {needle!r}: збігів серед незастосованих {len(hits)}, потрібен рівно один")
    version, name, path = hits[0]
    conn.execute("insert into supabase_migrations.schema_migrations (version, name, statements) "
                 "values (%s, %s, %s)", (version, name, [read_sql(path)]))
    print(f"  ✓ {path.name} записано в реєстр як застосовану (SQL не виконувався)")
    return 0


def apply_migrations(conn, *, apply: bool, only: str | None = None) -> int:
    ensure_ledger(conn)
    applied = applied_migrations(conn)
    by_version = {v: n for v, n in applied}
    by_name = {n: v for v, n in applied if n}
    pending = []
    print(f"База: {_redact(conn.info.dsn) if hasattr(conn.info, 'dsn') else 'підключено'}")
    print(f"У реєстрі {len(applied)} міграцій, локально {len(local_migrations())} файлів.\n")
    for version, name, path in local_migrations():
        if version in by_version:
            mark, note = "✓", ""
        elif name in by_name:
            mark, note = "✓", f"  (у реєстрі як {by_name[name]})"
        else:
            mark, note = "·", "  ← не застосовано"
            pending.append((version, name, path))
        print(f"  {mark} {version}_{name}{note}")
    ledger_only = [(v, n) for v, n in applied
                   if v not in {m[0] for m in local_migrations()} and n not in {m[1] for m in local_migrations()}]
    if ledger_only:
        print("\n  У реєстрі, але без файлу в репозиторії (зроблено з Dashboard):")
        for v, n in ledger_only:
            print(f"    {v}_{n}")

    if not pending:
        print("\nУсе застосовано.")
        return 0
    if not apply:
        print(f"\nДо застосування: {len(pending)}. Повторіть із --apply.")
        return 0
    if only:
        pending = [p for p in pending if only in p[0] or only in p[1]]
        if not pending:
            raise SystemExit(f"--only {only!r} не збігається з жодною незастосованою міграцією")
    print()
    for version, name, path in pending:
        sql = read_sql(path)
        seconds = run_sql(conn, sql, path.name)
        # Один запис — одна міграція, як робить CLI. statements CLI ріже по командах; нам досить
        # цілого файлу: реєстр потрібен, щоб не застосувати двічі, а не щоб відтворити файл.
        conn.execute("insert into supabase_migrations.schema_migrations (version, name, statements) "
                     "values (%s, %s, %s)", (version, name, [sql]))
        print(f"  ✓ {path.name}  ({seconds:.1f} с)")
    print(f"\nЗастосовано {len(pending)}.")
    return 0


# ------------------------------------------------------------------------ дампи

def _natural(path: pathlib.Path) -> list:
    """poruch-events-2 перед poruch-events-10: числа порівнюємо як числа, а не як текст."""
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", path.name)]


JOURNAL = ".applied_sql.json"


def _journal_path(files: list[pathlib.Path]) -> pathlib.Path:
    return files[0].parent / JOURNAL


def _journal_read(files: list[pathlib.Path]) -> dict:
    path = _journal_path(files)
    return json.loads(path.read_text("utf-8")) if path.exists() else {}


def _journal_mark(files: list[pathlib.Path], name: str, digest: str) -> None:
    """Журнал поруч із файлами: після збою на девʼятому файлі повтор починається з девʼятого."""
    path = _journal_path(files)
    data = _journal_read(files)
    data[name] = {"sha256": digest, "applied_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), "utf-8")


def _dump_files(target: pathlib.Path) -> tuple[list[pathlib.Path], dict | None]:
    """Файли до застосування, по порядку, і маніфест, якщо він є.

    Конвеєр пише `<name>.manifest.json` поруч із SQL, а з `--sql-max-bytes` — частини
    `<name>.01.sql`, `<name>.02.sql`, які застосовують лише по порядку. Маніфест і є цим порядком.
    """
    if target.is_dir():
        manifests = sorted(target.glob("*.manifest.json"))
        if manifests:
            files, merged = [], {"files": [], "run_ids": []}
            for m in manifests:
                f, data = _dump_files(m)
                files += f
                merged["files"] += data["files"]
                merged["run_ids"].append(data.get("run_id"))
            return files, merged
        return sorted(target.glob("*.sql"), key=_natural), None
    if target.suffix == ".json":
        data = json.loads(target.read_text("utf-8"))
        return [target.with_name(f["name"]) for f in data["files"]], data
    # `Київ.sql` → `Київ.manifest.json`; частина `Київ.02.sql` → теж `Київ.manifest.json`.
    stem = re.sub(r"\.\d{2}$", "", target.stem)
    manifest = target.with_name(stem + ".manifest.json")
    if target.suffix == ".sql" and manifest.exists():
        data = json.loads(manifest.read_text("utf-8"))
        listed = [target.with_name(f["name"]) for f in data["files"]]
        # Один файл без частин: маніфест описує саме його. З частинами — застосовуємо всі,
        # бо половина дампу лишить події одного джерела без другого.
        return (listed if target in listed else [target]), data
    return [target], None


def _verify_manifest(files: list[pathlib.Path], manifest: dict | None) -> None:
    if not manifest:
        return
    expected = {f["name"]: f for f in manifest["files"]}
    for path in files:
        meta = expected.get(path.name)
        if not meta:
            continue
        actual = _sha256(path.read_bytes())
        if actual != meta["sha256"]:
            raise SystemExit(f"✗ {path.name}: sha256 не збігається з маніфестом — файл змінено після "
                             "генерації. Перегенеруйте або застосовуйте без маніфесту свідомо.")


def _run_id(sql: str) -> str | None:
    m = re.search(r"run_id=([0-9a-f-]{36})", sql)
    return m.group(1) if m else None


def cmd_dump(args) -> int:
    files, manifest = _dump_files(args.path)
    if not files:
        raise SystemExit(f"Немає SQL у {args.path}")
    missing = [f for f in files if not f.exists()]
    if missing:
        raise SystemExit("Немає файлів із маніфесту: " + ", ".join(m.name for m in missing))
    _verify_manifest(files, manifest)

    total = sum(f.stat().st_size for f in files)
    print(f"Файлів: {len(files)}, {total / 1024:.0f} КіБ"
          + (", маніфест перевірено" if manifest else ", маніфесту немає"))
    for f in files:
        sql = read_sql(f)
        wrapped = "власна транзакція" if has_own_transaction(sql) else "загорнемо в транзакцію"
        print(f"  {f.name}  run_id={_run_id(sql) or '—'}  {wrapped}")
    if not args.apply:
        print("\nПеревірка. Повторіть із --apply, щоб записати в базу.")
        return 0

    conn = connect(database_url(args.db_url), args.statement_timeout)
    return apply_dump_files(conn, files, force=args.force)


def apply_dump_files(conn, files: list[pathlib.Path], *, force: bool = False) -> int:
    journal = {} if force else _journal_read(files)
    print()
    before = _event_count(conn)
    done = skipped = 0
    for f in files:
        sql = read_sql(f)
        digest = _sha256(sql.encode("utf-8"))
        if journal.get(f.name, {}).get("sha256") == digest:
            print(f"  = {f.name}  вже застосовано (журнал {JOURNAL}); --force, щоб повторити")
            skipped += 1
            continue
        seconds = run_sql(conn, sql, f.name)
        _journal_mark(files, f.name, digest)
        done += 1
        print(f"  ✓ {f.name}  ({seconds:.1f} с)")
    after = _event_count(conn)
    print(f"\nЗастосовано {done}, пропущено {skipped}.")
    if before is not None and after is not None:
        print(f"Імпортованих подій у базі: було {before}, стало {after}.")
    return 0


def _event_count(conn) -> int | None:
    try:
        return conn.execute("select count(*) from public.events where origin <> 'community'").fetchone()[0]
    except Exception:  # noqa: BLE001 — лічильник довідковий, без нього дамп усе одно застосовано
        return None


def cmd_all(args) -> int:
    """Один прогін дня: спершу схема, потім дані. Дамп, згенерований під нову схему, без
    міграції впаде на першій новій колонці, тому порядок не є налаштуванням."""
    files, manifest = _dump_files(args.path)
    if args.pattern:
        files = [f for f in files if f.match(args.pattern)]
    if not files:
        raise SystemExit(f"Немає SQL у {args.path}" + (f" за шаблоном {args.pattern}" if args.pattern else ""))
    _verify_manifest(files, manifest)
    print(f"Файлів даних: {len(files)} — {files[0].name} … {files[-1].name}\n")
    conn = connect(database_url(args.db_url), args.statement_timeout)
    print("── Міграції")
    apply_migrations(conn, apply=args.apply)
    print("\n── Дані")
    if not args.apply:
        for f in files:
            print(f"  · {f.name}")
        print("\nПеревірка. Повторіть із --apply, щоб записати в базу.")
        return 0
    return apply_dump_files(conn, files, force=args.force)


# ------------------------------------------------------------------- повний цикл

def _failed_sources(report: pathlib.Path) -> list[str]:
    try:
        data = json.loads(report.read_text("utf-8"))
    except (OSError, ValueError):
        return []
    return sorted({f"{r.get('city', '')}/{r.get('source', '')}: {r['error']}".strip("/")
                   for r in data.get("sources", []) if r.get("error")})


def cmd_run(args) -> int:
    """Створити файли → застосувати → прибрати. Тека лишається лише після збою, як доказ.

    Міграції з `supabase/migrations` копіюються в теку, щоб партія була самодостатньою й видимою,
    але джерело правди — репозиторій: прибираємо копії, а не оригінали. Дані генерує сам
    конвеєр `tools.ingest`; його аргументи передаються після «--».
    """
    import shutil
    import subprocess

    stamp = time.strftime("%Y-%m-%d_%H%M%S")
    workdir = (args.dir or ROOT / "out" / f"sql-{stamp}").resolve()
    if workdir.exists() and any(workdir.iterdir()):
        raise SystemExit(f"Тека {workdir} не порожня: залишок минулого збою. Розберіться з нею або вкажіть --dir.")
    workdir.mkdir(parents=True, exist_ok=True)
    print(f"Тека партії: {workdir}")

    # 1. Копії нових міграцій — щоб бачити, що саме поїде разом із даними.
    conn = connect(database_url(args.db_url), args.statement_timeout)
    ensure_ledger(conn)
    applied = applied_migrations(conn)
    versions = {v for v, _ in applied}
    names = {n for _, n in applied if n}
    pending = [(v, n, path) for v, n, path in local_migrations() if v not in versions and n not in names]
    for _, _, path in pending:
        shutil.copy2(path, workdir / path.name)
    print(f"Міграцій до застосування: {len(pending)}" + (": " + ", ".join(p.name for *_, p in pending) if pending else ""))

    # 2. Дані — конвеєром. Один файл на обхід = одна транзакція; --split-bytes ріже на частини.
    data_file = workdir / "poruch-events.sql"
    cmd = [sys.executable, "-m", "tools.ingest", "--sql", str(data_file),
           "--report", str(workdir / "report.json")]
    if args.split_bytes:
        cmd += ["--sql-max-bytes", str(args.split_bytes)]
    cmd += args.ingest_args
    print("\n── Генерація: " + " ".join(cmd[1:]) + "\n")
    result = subprocess.run(cmd, cwd=ROOT)
    data_files = sorted(workdir.glob("poruch-events*.sql"), key=_natural)
    if result.returncode not in (0, 1) or not data_files:
        raise SystemExit(f"\n✗ Конвеєр завершився з кодом {result.returncode}, SQL не створено. Тека лишена: {workdir}")
    if result.returncode == 1:
        # Джерело, що не обійшлось, конвеєр сам виключає зі зняття зниклих подій (див.
        # `_may_retire`), тож дамп лишається безпечним. Помилка — привід глянути на джерело, не
        # причина тримати місто без свіжих подій. --strict повертає зупинку.
        failed = _failed_sources(workdir / "report.json")
        print(f"\n⚠ Не обійшлись: {', '.join(failed) or 'див. report.json'}. Їхні події не знімаються.")
        if args.strict:
            raise SystemExit(f"✗ --strict: дамп створено, але не застосовано. Тека лишена: {workdir}"
                             f"\n  Застосувати вручну: apply_sql.py all {workdir} --apply")
    _verify_manifest(data_files, _dump_files(data_file)[1])
    print(f"\nФайлів даних: {len(data_files)} — " + ", ".join(f.name for f in data_files))

    if not args.apply:
        print(f"\nПеревірка: файли створено в {workdir}, у базу нічого не писано і тека лишена."
              "\nПовторіть із --apply або застосуйте пізніше: apply_sql.py all <тека> --apply.")
        return 0

    # 3. Застосування: схема, потім дані. Збій лишає теку з журналом для повтору через `all`.
    print("\n── Міграції")
    apply_migrations(conn, apply=True)
    print("\n── Дані")
    apply_dump_files(conn, data_files)

    # 4. Прибирання — лише коли все вище пройшло; будь-який SystemExit раніше сюди не дійде.
    if args.keep:
        print(f"\nТеку лишено за --keep: {workdir}")
    else:
        shutil.rmtree(workdir)
        print(f"\nУсе застосовано, теку {workdir.name} прибрано.")
    return 0


# -------------------------------------------------------------------------- CLI

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="tools/apply_sql.py",
                                 description="SQL до Supabase прямим зʼєднанням")
    ap.add_argument("--db-url", help="рядок зʼєднання; інакше SUPABASE_DB_URL / DATABASE_URL із середовища чи .env")
    ap.add_argument("--statement-timeout", default="10min",
                    help="statement_timeout сесії (типово 10min)")
    sub = ap.add_subparsers(dest="command", required=True)

    m = sub.add_parser("migrations", help="застосувати незастосовані supabase/migrations/*.sql")
    m.add_argument("--apply", action="store_true", help="справді виконати; без прапорця — лише список")
    m.add_argument("--only", help="лише міграції, у версії чи назві яких є цей підрядок")
    m.add_argument("--mark-applied", metavar="ПІДРЯДОК",
                   help="записати міграцію в реєстр без виконання (вже застосована вручну)")
    m.set_defaults(func=cmd_migrations)

    d = sub.add_parser("dump", help="застосувати SQL, згенерований tools.ingest")
    d.add_argument("path", type=pathlib.Path, help="файл .sql, .manifest.json або тека з ними")
    d.add_argument("--apply", action="store_true", help="справді виконати; без прапорця — лише перевірка")
    d.add_argument("--force", action="store_true", help="повторити файли, що вже є в журналі")
    d.set_defaults(func=cmd_dump)

    a = sub.add_parser("all", help="незастосовані міграції, потім усі файли даних по черзі")
    a.add_argument("path", type=pathlib.Path, help="тека з poruch-events-N.sql (або файл чи маніфест)")
    a.add_argument("--pattern", default="poruch-events*.sql",
                   help="які файли з теки брати (типово poruch-events*.sql); '*.sql' — усі")
    a.add_argument("--apply", action="store_true", help="справді виконати; без прапорця — лише план")
    a.add_argument("--force", action="store_true", help="повторити файли, що вже є в журналі")
    a.set_defaults(func=cmd_all)

    r = sub.add_parser("run", help="згенерувати SQL конвеєром, застосувати міграції й дані, прибрати теку")
    r.add_argument("--dir", type=pathlib.Path, help="робоча тека (типово out/sql-<дата>)")
    r.add_argument("--split-bytes", type=int, default=0,
                   help="різати дамп на poruch-events.NN.sql не більші за N байтів; 0 — один файл")
    r.add_argument("--apply", action="store_true", help="справді виконати; без прапорця — лише згенерувати")
    r.add_argument("--keep", action="store_true", help="не видаляти теку після успіху")
    r.add_argument("--strict", action="store_true",
                   help="не застосовувати, якщо хоч одне джерело не обійшлось (типово — лише попередити)")
    r.add_argument("ingest_args", nargs=argparse.REMAINDER,
                   help="аргументи tools.ingest після «--», напр. -- --city Київ --agent")
    r.set_defaults(func=cmd_run)

    args = ap.parse_args(argv)
    if getattr(args, "ingest_args", None) and args.ingest_args[0] == "--":
        args.ingest_args = args.ingest_args[1:]
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

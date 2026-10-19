"""Мапа «функція → остання міграція» для supabase/schema/README.md: друкує markdown-таблиці в stdout.

    python3 supabase/schema/function_map.py

Функції беруться з current.sql, визначення — з supabase/migrations/*.sql (останній файл виграє).
Співставлення за схемою, назвою й іменами параметрів, тож старі перевантаження (create_event до
p_contact_url тощо) не плутаються з поточними. Колонка «Міграцій» — у скількох файлах функція з
такою назвою оголошена (з усіма сигнатурами). Функція без жодного збігу — помилка.
"""
import collections
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
HEADER = re.compile(r"create\s+(?:or\s+replace\s+)?function\s+([\w.\"]+)\s*\(", re.I)
LIVE = re.compile(r"^-- execute: (.*)\nCREATE OR REPLACE FUNCTION (\S+?)\((.*)\)\n", re.M)


def arg_names(args: str) -> tuple:
    """Імена параметрів: розбір по комах верхнього рівня (типи на кшталт numeric(3,2), DEFAULT '…,…')."""
    parts, depth, quote, cur = [], 0, False, ""
    for ch in args:
        quote ^= ch == "'"
        if not quote:
            depth += ch in "([" ; depth -= ch in ")]"
            if ch == "," and depth == 0:
                parts.append(cur); cur = ""; continue
        cur += ch
    parts.append(cur)
    names = []
    for part in filter(str.strip, parts):
        tokens = part.split()
        while tokens[0].lower() in ("in", "out", "inout", "variadic"):
            tokens = tokens[1:]
        names.append(tokens[0].strip('"').lower())
    return tuple(names)


def migration_defs() -> dict:
    defs = collections.defaultdict(list)
    for path in sorted((HERE.parent / "migrations").glob("*.sql")):
        sql = re.sub(r"--[^\n]*", "", re.sub(r"/\*.*?\*/", "", path.read_text("utf-8"), flags=re.S))
        for m in HEADER.finditer(sql):
            i, depth, quote = m.end(), 1, False
            while depth:
                quote ^= sql[i] == "'"
                if not quote:
                    depth += (sql[i] == "(") - (sql[i] == ")")
                i += 1
            name = m.group(1).replace('"', '').lower()
            defs[(name if "." in name else "public." + name, arg_names(sql[m.end():i - 1]))].append(path.name)
    return defs


def main() -> int:
    defs = migration_defs()
    by_name = collections.defaultdict(set)
    for (name, _), files in defs.items():
        by_name[name].update(files)
    live = [(name.lower(), arg_names(args), acl) for acl, name, args in LIVE.findall((HERE / "current.sql").read_text("utf-8"))]
    missing = [f"{n}({', '.join(a)})" for n, a, _ in live if (n, a) not in defs]
    if missing:
        print("Немає в міграціях:", *missing, sep="\n  ", file=sys.stderr)
        return 1
    counts = collections.Counter(n for n, _, _ in live)
    for schema in ("public", "private"):
        rows = sorted(r for r in live if r[0].startswith(schema + "."))
        print(f"### Схема `{schema}` ({len(rows)})\n\n| Функція | Остання міграція | Міграцій | EXECUTE |\n|---|---|---:|---|")
        for name, params, acl in rows:
            label = name.split(".")[1] + (f"({', '.join(params)})" if counts[name] > 1 else "")  # параметри — лише для перевантажень
            print(f"| `{label}` | `{defs[(name, params)][-1]}` | {len(by_name[name])} | {'—' if acl == '-' else acl} |")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

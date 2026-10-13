#!/usr/bin/env python3
"""Копірайт iOS з Android `strings.xml`: одне джерело правди для текстів обох платформ.

    python3 tools/generate_copy.py

Читає `androidApp/src/main/res/values/strings.xml` і пише `iosApp/Poruch/App/Copy.swift`:
`enum Copy` зі `static let` на кожен рядок без аргументів і `static func` на рядок з `%1$s`/`%d`
(аргументи — рядки, як у Swift-інтерполяції, тож `Int32` з Kotlin не ламає формат). Множини
(`<plurals>`) стають функціями від числа через `ukrainianPlural`.

Застосунок одномовний, тому локалізація не потрібна: екрани беруть `Copy.key` напряму, а ключ
збігається з `R.string.key` на Android — одне ім'я в обох кодових базах і в обговореннях.
Рядок, якого нема в `strings.xml`, лишається літералом у view; додавати його сюди — додаючи в XML.
"""

from __future__ import annotations

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "androidApp/src/main/res/values/strings.xml"
TARGET = ROOT / "iosApp/Poruch/App/Copy.swift"

PLACEHOLDER = re.compile(r"%(\d+)?\$?([sd])")
# Ключ, що збігається зі словом Swift, оголошуємо в зворотних лапках; звертання `Copy.where` працює й без них.
SWIFT_KEYWORDS = {"where", "in", "is", "as", "for", "if", "else", "do", "try", "return", "default", "case", "import", "self", "init", "func", "var", "let", "class", "struct", "enum", "protocol", "extension", "repeat", "while", "switch", "break", "continue", "throw", "throws", "true", "false", "nil", "static", "public", "private", "internal", "open", "any", "some"}


def ident(name: str) -> str:
    return f"`{name}`" if name in SWIFT_KEYWORDS else name


def unescape_android(value: str) -> str:
    value = html.unescape(value)
    value = value.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n").replace("\\@", "@")
    return value.strip()


def swift_literal(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def swift_template(value: str) -> tuple[str, int]:
    """Шаблон з `%1$s` → інтерполяція `\\(a0)`; повертає рядок і кількість аргументів."""
    count = 0
    positions: list[int] = []

    def sub(match: re.Match) -> str:
        nonlocal count
        position = int(match.group(1)) - 1 if match.group(1) else len(positions)
        positions.append(position)
        count = max(count, position + 1)
        return "\0%d\0" % position

    templated = PLACEHOLDER.sub(sub, value)
    literal = swift_literal(templated)
    for index in range(count):
        literal = literal.replace("\0%d\0" % index, "\\(a%d)" % index)
    return literal, count


def read_strings() -> tuple[list[tuple[str, str]], list[tuple[str, dict[str, str]]]]:
    xml = SOURCE.read_text()
    strings = [
        (name, unescape_android(value))
        for name, value in re.findall(r'<string name="([^"]+)"[^>]*>(.*?)</string>', xml, re.S)
    ]
    plurals = []
    for name, body in re.findall(r'<plurals name="([^"]+)">(.*?)</plurals>', xml, re.S):
        items = {q: unescape_android(v) for q, v in re.findall(r'<item quantity="(\w+)">(.*?)</item>', body, re.S)}
        plurals.append((name, items))
    return strings, plurals


def write_swift() -> None:
    strings, plurals = read_strings()
    lines = [
        "import Foundation",
        "",
        "/// Тексти інтерфейсу. ЗГЕНЕРОВАНО tools/generate_copy.py з androidApp/src/main/res/values/strings.xml:",
        "/// правити там, ключ той самий, що `R.string.<key>` на Android. Аргументи форматних рядків — рядки,",
        "/// як у Swift-інтерполяції. Множини рахує `ukrainianPlural`.",
        "enum Copy {",
    ]
    for name, value in strings:
        literal, count = swift_template(value)
        if count == 0:
            lines.append(f"    static let {ident(name)} = {literal}")
        else:
            params = ", ".join(f"_ a{i}: String" for i in range(count))
            lines.append(f"    static func {ident(name)}({params}) -> String {{ {literal} }}")
    lines.append("")
    lines.append("    // ---- Множини: `one` / `few` / `many` за українським правилом, число підставляється замість %d.")
    for name, items in plurals:
        forms = [items.get(q, items.get("other", "")) for q in ("one", "few", "many")]
        forms_swift = ", ".join(swift_literal(PLACEHOLDER.sub("\0", f)).replace("\0", "\\(n)") for f in forms)
        lines.append(f"    static func {ident(name)}(_ n: Int) -> String {{ ukrainianPlural(n, {forms_swift}) }}")
    lines.append("}")
    TARGET.write_text("\n".join(lines) + "\n")
    print(f"{len(strings)} рядків + {len(plurals)} множин → {TARGET.relative_to(ROOT)}")


if __name__ == "__main__":
    write_swift()

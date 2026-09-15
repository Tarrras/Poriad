#!/usr/bin/env python3
"""Перезаписує список Swift-файлів таргета Xcode з того, що є на диску.

Проєкт старіший за синхронізовані теки Xcode, тож кожен файл згадується в project.pbxproj тричі.
Скрипт робить це з обходу теки. Лише Swift-файли; ресурси й налаштування не чіпає. Ідентифікатори
виводяться зі шляху, тому повторний запуск дає той самий файл.

    python3 tools/sync_xcode_sources.py
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "iosApp/Poruch"
PROJECT = ROOT / "iosApp/Poruch.xcodeproj/project.pbxproj"
# PBXGroup, що дзеркалить iosApp/Poruch.
GROUP_ID = "80E6A3A99B37879F3465DB7C"


def uid(seed: str) -> str:
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()


def replace_section(text: str, start: str, end: str, keep) -> str:
    a, b = text.index(start), text.index(end)
    return text[:a] + "\n".join(line for line in text[a:b].split("\n") if keep(line)) + text[b:]


def replace_list(text: str, anchor: str, opener: str, keep, entries: list[str]) -> str:
    start = text.index(opener, text.index(anchor))
    end = text.index(");", start)
    kept = [line for line in text[start:end].split("\n") if keep(line)]
    return text[:start] + "\n".join(kept) + "\n".join([""] + entries) + "\n\t\t\t" + text[end:]


def main() -> None:
    files = sorted(
        str(Path(directory, name).relative_to(SOURCES))
        for directory, _, names in os.walk(SOURCES)
        for name in names
        if name.endswith(".swift")
    )

    build, refs, children, sources = [], [], [], []
    for path in files:
        name = Path(path).name
        file_ref, build_ref = uid("ref:" + path), uid("build:" + path)
        build.append(f"\t\t{build_ref} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {name} */; }};")
        refs.append(
            f"\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; includeInIndex = 1; "
            f'lastKnownFileType = sourcecode.swift; name = {name}; path = {path}; sourceTree = "<group>"; }};'
        )
        children.append(f"\t\t\t\t{file_ref} /* {name} */,")
        sources.append(f"\t\t\t\t{build_ref} /* {name} in Sources */,")

    text = PROJECT.read_text(encoding="utf-8")
    text = replace_section(
        text, "/* Begin PBXBuildFile section */", "/* End PBXBuildFile section */",
        lambda line: ".swift in Sources" not in line,
    ).replace("/* Begin PBXBuildFile section */", "/* Begin PBXBuildFile section */\n" + "\n".join(build), 1)
    text = replace_section(
        text, "/* Begin PBXFileReference section */", "/* End PBXFileReference section */",
        lambda line: "sourcecode.swift" not in line,
    ).replace("/* Begin PBXFileReference section */", "/* Begin PBXFileReference section */\n" + "\n".join(refs), 1)
    text = replace_list(text, GROUP_ID + " /* Poruch */", "children = (", lambda line: ".swift" not in line, children)
    text = replace_list(
        text, "/* Begin PBXSourcesBuildPhase section */", "files = (",
        lambda line: ".swift in Sources" not in line, sources,
    )
    PROJECT.write_text(text, encoding="utf-8")
    print(f"{len(files)} Swift sources listed")


if __name__ == "__main__":
    main()

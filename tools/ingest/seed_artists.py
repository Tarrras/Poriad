"""Насіння словника артистів: імена з каталогу Concert.ua (/uk/talent/list).

    python3 -m tools.ingest.seed_artists

Беремо лише імена: біографії й фото — чужий контент (docs/event-ingestion.md, розділ 8).
Файл `artists_seed.json` — похідний, перезаписується; ручна вивірка живе в `artists.json`.
"""
from __future__ import annotations

import json
import re
import sys

from .artists import SEED_PATH
from .fetch import get
from .normalize import clean_text

URL = "https://concert.ua/uk/talent/list"
_NAME = re.compile(r'class="performer-item[^"]*"\s+href="/uk/talent/[^"]+"[^>]*>.*?'
                   r'<span class="title[^"]*">([^<]+)</span>', re.S)


def main() -> int:
    page = get(URL, delay=2.0)
    if page.status != 200 or not page.body:
        print(f"{URL}: HTTP {page.status}", file=sys.stderr)
        return 1
    names = sorted({clean_text(n) for n in _NAME.findall(page.body)} - {""})
    SEED_PATH.write_text(json.dumps({"source": URL, "names": names}, ensure_ascii=False, indent=0), "utf-8")
    print(f"{len(names)} імен -> {SEED_PATH.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

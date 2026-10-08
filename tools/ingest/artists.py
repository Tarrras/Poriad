"""Артисти події: хто виступає, а не де.

Щаблі 1-3 з docs/artists-discovery-2026-10.md: структуровані дані джерела, словник, правила
на назві й описі. Без БД і моделі. Три правила, виміряні на живих даних, а не припущені:

1. Karabas ставить у `performer` назву події (66 з 66), тож там він нічого не каже. Concert.ua
   `workPerformed` не читаємо взагалі: там теж копія назви.
2. Тип schema.org (`Person`/`Organization`/`PerformingGroup`) ігноруємо: Badseller віддає
   `PerformingGroup` і гурту, і театру, Concert.ua плутає Person і Organization.
3. Майданчик не артист. «Театр на Подолі» — зал, де виступають інші; МУР — трупа, що їздить
   по залах. Відрізняємо за місцем: виконавець, що збігається з майданчиком чи організатором-залом,
   відкидається одразу; назву з театральним словом, яка за весь прогін зустрілась в одному
   місці, відкидає `settle`. Те, що правило вирішує хибно, виправляє `artists.json` (`kind`).
"""
from __future__ import annotations

import collections
import dataclasses
import hashlib
import json
import pathlib
import re

from .artist_prompt import BATCH_FORMAT, BODY
from .normalize import clean_text, normalize_name

DICT_PATH = pathlib.Path(__file__).resolve().parent / "artists.json"
SEED_PATH = DICT_PATH.with_name("artists_seed.json")

# Види сутності в словнику. `venue` і `promoter` — майданчик чи
# промоутер, що назвався виконавцем: не артист.
KINDS = ("person", "group", "company", "show", "venue", "promoter")

# Джерела, де `performer` — копія назви події, а не відповідь про виконавця.
TITLE_COPY_SOURCES = frozenset({"karabas"})
# Джерела, де `organizer` — зал, а не промоутер (Badseller: `/zal/{slug}`).
ORGANIZER_IS_VENUE = frozenset({"badseller"})

# Слова, за якими назва скидається на майданчик. Лише привід перевірити місце, не вирок.
_VENUE_WORD = re.compile(r"театр|опер[аиі]|оперет|філармон|палац|будинок культури|\bдк\b|\bцентр")
# Оркестр чи хор при філармонії — виконавець, хоч у назві є слово майданчика.
_ENSEMBLE = re.compile(r"оркестр|\bхор\b|ансамбл|квартет|тріо|capella|капела|orchestra|band")
# Промоутер, не виконавець («Кайф Продакшн» замість коміка «Ван Панч»).
_PROMOTER = re.compile(r"продакшн|production|agency|агенц|\bтов\b|\bфоп\b")
_MERGED = re.compile(r"\s(?:та|і|&|\+)\s|,")
_GROUP_PREFIX = re.compile(r"^(гурт|група|ансамбль)\s+", re.I)
MAX_NAME = 80


@dataclasses.dataclass(frozen=True)
class Artist:
    name: str
    role: str = "headliner"
    how: str = "source"          # source | lineup (опис) | dictionary | rules (назва) | llm
    confidence: float = 0.9
    kind: str | None = None      # person|group|company|show: лише з ручного словника


_PAREN = re.compile(r"\s*\([^)]*\)")


def key(name: str) -> str:
    """Ключ зіставлення: регістр, апострофи, лапки, «Гурт», дужки й зайві пробіли прибрані. Дужки не
    розрізняють: «Крістін Мілворд (Kristine Milward)» і «Крістін Мілворд» — одна людина."""
    return normalize_name(_GROUP_PREFIX.sub("", _PAREN.sub(" ", clean_text(name))))


def display(name: str) -> str:
    """Ім'я для показу: без «Гурт» на початку й без дужок (переклад, уточнення)."""
    return _GROUP_PREFIX.sub("", _PAREN.sub("", clean_text(name))).strip()


def split_pair(name: str) -> list[str]:
    """«Алла Волкова та Анастасія Ткаченко» — це двоє людей, а не один артист. Ділимо лише коли обидві
    половини схожі на імʼя людини: «Бампер і Сус» чи «Жадан і Собаки» — колективи, їх не чіпаємо."""
    parts = re.split(r"\s+(?:та|і|&)\s+", name)
    return parts if len(parts) == 2 and all(_PERSON_SHAPE.match(p) for p in parts) else [name]


def has_proper(name: str) -> bool:
    """Назва без жодної великої літери («заслужена працівниця») — уривок фрази, а не артист."""
    return any(c.isupper() for c in name)


def _is_venue_word(name: str) -> bool:
    k = key(name)
    return bool(_VENUE_WORD.search(k)) and not _ENSEMBLE.search(k)


def _slug(url) -> str:
    return str(url or "").rstrip("/").rsplit("/", 1)[-1]


def _as_list(value) -> list:
    if isinstance(value, list):
        return value
    return [] if value is None else [value]


def from_source(raw: dict, title: str, venue_names: list[str], source_slug: str = "") -> list[Artist]:
    """Артисти з розмітки події. Порожній список — «джерело не знає», а не «артиста немає»."""
    place = raw.get("location")
    place = next((p for p in _as_list(place) if isinstance(p, dict)), {})
    venue_keys = {key(n) for n in venue_names if n}
    venue_slugs = set()
    if source_slug in ORGANIZER_IS_VENUE:
        for org in _as_list(raw.get("organizer")):
            if isinstance(org, dict):
                venue_keys.add(key(org.get("name") or ""))
                venue_slugs.add(_slug(org.get("url")))
    venue_keys.add(key(place.get("name") or ""))
    venue_keys.discard("")
    venue_slugs.discard("")

    marked = {key(m.group(1)) for seg in _SEGMENTS.split(_NOISE.sub(" ", clean_text(title)))
              for m in [_GROUP_MARK.match(seg.strip())] if m}
    out: list[Artist] = []
    seen: set[str] = set()
    for p in _as_list(raw.get("performer")):
        raw_name = display(p.get("name") if isinstance(p, dict) else p)
        for name in split_pair(raw_name):
            k = key(name)
            if not name or len(name) > MAX_NAME or k in seen or not has_proper(name):
                continue
            if source_slug in TITLE_COPY_SOURCES and k == key(title):
                continue
            if _PROMOTER.search(k):
                continue
            if _THEME.search(title) and k in key(title) and k not in marked:
                continue                # «Музика при свічках: Ейнауді та Тірсен» — тема, не виконавець
            if k in venue_keys or (isinstance(p, dict) and _slug(p.get("url")) in venue_slugs):
                continue
            seen.add(k)
            out.append(Artist(name))
    return out


class Dictionary:
    """Ім'я -> канонічне ім'я й вид. Три шари, вищий не перетирається нижчим:
    ручна вивірка (`artists.json`, має `kind`) > насіння (`artists_seed.json`, імена з каталогу
    Concert.ua) > виконавці зі структури цього прогону (`learn`). Лише ім'я зі словника дає право
    витягти артиста з назви, у якій немає явного маркера («Гурт X»)."""

    def __init__(self, entries: dict | None = None, seed: list | None = None):
        self._by_key: dict[str, tuple[str, str | None]] = {}
        self._multi: dict[str, list[tuple[list[str], str]]] = collections.defaultdict(list)
        for canonical, entry in (entries or {}).items():
            if canonical == "_" or not isinstance(entry, dict):
                continue
            kind = entry.get("kind")
            if kind is not None and kind not in KINDS:
                raise ValueError(f"artists.json: невідомий kind {kind!r} у {canonical!r}")
            for name in [canonical, *entry.get("aliases", [])]:
                self._by_key[key(name)] = (canonical, kind)
                self._index(name, canonical)
        self.add_names(seed or [])

    def _index(self, name: str, canonical: str) -> None:
        tokens = key(name).split()
        if len(tokens) >= 2:
            self._multi[tokens[0][:3]].append((tokens, canonical))

    def add_names(self, names) -> None:
        for name in names:
            k = key(name)
            # Склеєні «A та B» і чужі рядки знанням не вважаємо.
            if k and len(k) >= 3 and not _MERGED.search(k) and k not in self._by_key:
                self._by_key[k] = (clean_text(name), None)
                self._index(name, clean_text(name))

    @classmethod
    def load(cls, path: pathlib.Path = DICT_PATH, seed_path: pathlib.Path = SEED_PATH) -> "Dictionary":
        try:
            entries = json.loads(path.read_text("utf-8"))
        except FileNotFoundError:
            entries = {}
        try:
            seed = json.loads(seed_path.read_text("utf-8")).get("names", [])
        except FileNotFoundError:
            seed = []
        return cls(entries, seed)

    def lookup(self, name: str) -> tuple[str, str | None] | None:
        return self._by_key.get(key(name))

    def scan(self, text: str) -> list[str]:
        """Відомі імена з двох і більше слів, що стоять у тексті поспіль, у будь-якому відмінку:
        «Сольний Стендап Концерт Богдана Боярина» знаходить «Богдан Боярин»."""
        words = key(text).split()
        found = []
        for i, w in enumerate(words):
            for tokens, canonical in self._multi.get(w[:3], ()):
                chunk = words[i:i + len(tokens)]
                if len(chunk) == len(tokens) and all(
                        c.startswith(t[:max(3, len(t) - 2)]) for c, t in zip(chunk, tokens)):
                    found.append(canonical)
        return found

    def resolve(self, name: str) -> tuple[str, str | None]:
        return self._by_key.get(key(name), (name, None))


# ---- Щабель 3: правила на назві й описі

# Назва про тему чи формат, а не про виконавця: виконавця з неї беремо лише за явним «гурт».
_THEME = re.compile(r"(?i)триб.?ют|tribute|при свічках|кавер|\bcover\b|symphony|симфонічн")
_TRIBUTE = re.compile(r"(?i)триб.?ют|tribute")
_SEGMENTS = re.compile(r"\s+[-–—]\s+|\.\s+|:\s+|\s*\|\s*")
_JOINERS = re.compile(r"\s+(?:та|і|й|&|\+|x|х)\s+|\s*,\s*", re.I)
_GROUP_MARK = re.compile(r"^(?:гурт|група)\s+(.+)$", re.I)
# Латиницею названий склад («Kyiv Mozart Orchestra»): власна назва, не «симфонічний оркестр».
_LATIN_ENSEMBLE = re.compile(r"^[A-Z][\w'’.-]*(?:\s+[A-Z][\w'’.-]*){0,3}\s+(?:Orchestra|Quartet|Quintet|Choir|Trio|Ensemble)$")
# Два слова з великої літери: схоже на імʼя людини (для пари з одним уже відомим імʼям).
_PERSON_SHAPE = re.compile(r"^[A-ZА-ЯІЇЄҐ][\w'’ʼ-]+\s+[A-ZА-ЯІЇЄҐ][\w'’ʼ-]+$")
_SHOW_WORD = re.compile(r"(?i)\bшоу\b|\bshow\b")
_NOISE = re.compile(r"\([^)]*\)|\bзйомка\b|\bна біс\b", re.I)
# У виставах і дитячих назва часто несе режисера чи хореографа («… Раду Поклітару»): там імені з
# насіння мало, потрібен ручний запис зі `kind`.
STRICT_CATEGORIES = frozenset({"art", "kids"})
# Категорії, де артист у назві взагалі можливий: виставка чи конференція не мають виконавця.
TITLE_CATEGORIES = frozenset({"music", "comedy", "art", "kids"})


def from_title(title: str, dictionary: Dictionary, category: str = "music") -> list[Artist]:
    """Артисти з назви. Два шляхи: явний маркер «Гурт X» (працює без словника) і відомі імена,
    що стоять окремим сегментом («Ivan Liulenov. НА БІС», «Алла Волкова та Анастасія Ткаченко»).
    Назва-тема (трибʼют, «при свічках») дає лише явний «гурт»: Queen там не виконавець."""
    if category not in TITLE_CATEGORIES:
        return []
    strict = category in STRICT_CATEGORIES

    def known(text: str):
        hit = dictionary.lookup(text)
        return hit if hit and (hit[1] or not strict) else None

    cleaned = _NOISE.sub(" ", clean_text(title))
    segments = [x.strip(" «»\"“”") for x in _SEGMENTS.split(cleaned) if x.strip()]
    found: dict[str, Artist] = {}

    def add(name: str, how: str = "rules") -> None:
        name = name.strip(" «»\"“”,")
        if name and key(name) not in found:
            canonical, _ = dictionary.resolve(name)
            found[key(name)] = Artist(canonical, how=how, confidence=0.9)

    for seg in segments:
        m = _GROUP_MARK.match(seg)
        if m:
            add(m.group(1))
    if _THEME.search(cleaned):
        for seg in segments[1:]:
            if _LATIN_ENSEMBLE.match(seg) and _TRIBUTE.search(cleaned) is None:
                add(seg)
        return list(found.values())
    # «ТЕМА – Назва Orchestra»: склад названо прямо, решта сегментів — програма, не виконавці.
    ensembles = [seg for seg in segments[1:] if _LATIN_ENSEMBLE.match(seg)]
    if ensembles:
        for seg in ensembles:
            add(seg)
        return list(found.values())
    for seg in segments:
        if _GROUP_MARK.match(seg):
            continue
        if known(seg):
            add(seg)
            continue
        parts = [p.strip() for p in _JOINERS.split(seg) if p.strip()]
        if len(parts) > 1:
            hits = [bool(known(p)) for p in parts]
            # Усі відомі, або хоч одне відоме, а решта має вигляд імені людини.
            if all(hits) or (any(hits) and all(k or _PERSON_SHAPE.match(p)
                                               for k, p in zip(hits, parts))):
                for p in parts:
                    add(p)
                continue
        if _LATIN_ENSEMBLE.match(seg):
            add(seg)
            continue
        for name in dictionary.scan(seg):
            if known(name):
                add(name)
    return list(found.values())


_NAME_TOKEN = r"[A-ZА-ЯІЇЄҐ][\w'’ʼ\-]+"
# Імʼя, прізвище й одразу @handle: так афіші стендапу підписують учасників. Один @handle без
# контексту («Підписуйтесь @x») артистом не вважаємо.
_NAME_HANDLE = re.compile(rf"({_NAME_TOKEN}\s+{_NAME_TOKEN})\s*@[\w.]{{3,30}}")
_HOST = re.compile(rf"(?i)ведуч\w*\s*[:—–-]\s*({_NAME_TOKEN}\s+{_NAME_TOKEN})")
_LINEUP_CONTEXT = re.compile(r"(?i)ведуч|виступа|склад|учасник|хедлайнер|line-?up|лайн-?ап|коміки")
_NOT_NAME = re.compile(r"(?i)instagram|telegram|facebook|підписуйтесь|сторінк|квитки|наш|youtube|tiktok")


def from_description(description: str) -> list[Artist]:
    """Лайнап з опису: «Імʼя Прізвище @handle» (два й більше, або один із контекстом
    «Виступають/Склад/Ведучий») та «Ведучий: Імʼя Прізвище». Для стендапу це єдине місце, де
    названо виконавців конкретного вечора."""
    text = clean_text(description)
    handled = [m for m in _NAME_HANDLE.finditer(text) if not _NOT_NAME.search(m.group(1))]
    out: dict[str, Artist] = {}
    for m in _HOST.finditer(text):
        out[key(m.group(1))] = Artist(m.group(1), role="host", how="lineup", confidence=0.85)
    contextual = len(handled) >= 2 or any(
        _LINEUP_CONTEXT.search(text[max(0, m.start() - 60):m.start()]) for m in handled)
    if contextual:
        for m in handled:
            out.setdefault(key(m.group(1)), Artist(m.group(1), how="lineup", confidence=0.9))
    return list(out.values())


def has_name(name: str, quote: str) -> bool:
    """Кожне слово імені є в цитаті за основою: «Наталія Могилевська» знаходиться в «концерт
    Наталії Могилевської». Без цього відмінювання відкидає правильні імена."""
    words = key(quote).split()
    return all(any(w.startswith(t[:max(3, len(t) - 2)]) for w in words) for t in key(name).split())


def merge(*lists: list[Artist]) -> list[Artist]:
    """Об'єднання без дублів за ключем; раніший щабель стоїть першим і виграє."""
    out: dict[str, Artist] = {}
    for artists in lists:
        for a in artists:
            out.setdefault(key(a.name), a)
    return list(out.values())


def _spot(it):
    """Місце події для підрахунку: координати з округленням до ~80 м. Копії однієї події з різних
    джерел геокодовані з розбіжністю, і сирі координати видають один зал за кілька «місць»."""
    if it.latitude is not None:
        return (round(it.latitude, 3), round(it.longitude, 3))
    return it.venue_name


def _is_initials(name: str, venues: list) -> bool:
    """«НАДТ» — абревіатура залу «Національний академічний драматичний театр…»: слова «театр» у ній
    нема, тож правило слів її не бачить, а це той самий майданчик."""
    token = key(name)
    if " " in token or not 2 <= len(token) <= 6:
        return False
    for venue in venues:
        words = key(venue or "").split()
        if len(words) >= len(token) and "".join(w[0] for w in words[:len(token)]) == token:
            return True
    return False


def _drop_venues(items: list, dictionary: Dictionary, dropped: collections.Counter) -> dict:
    """Словник, абревіатура залу і правило «театр в одному місці = майданчик». Повертає ім'я -> кількість
    місць. Місця рахуємо лише по опублікованих подіях: дубль-копія іншого джерела не додає «місця»."""
    places: dict[str, set] = collections.defaultdict(set)
    for it in items:
        if getattr(it, "stage", "published") != "published":
            continue
        for a in it.artists:
            canonical, _ = dictionary.resolve(a.name)
            places[key(canonical)].add(_spot(it))
    for it in items:
        kept = []
        for a in it.artists:
            canonical, kind = dictionary.resolve(a.name)
            if kind in ("venue", "promoter"):
                dropped[canonical] += 1
                continue
            if kind is None and (
                    _is_initials(canonical, [it.venue_name, getattr(it, "venue_display", None)])
                    or (_is_venue_word(canonical) and len(places[key(canonical)]) <= 1)):
                dropped[canonical] += 1
                continue
            kept.append(dataclasses.replace(a, name=canonical, kind=kind, how="dictionary" if kind else a.how))
        # Повтори прибираємо після зведення до словника: «Павло Пінчук» і «Паша Пінчук» — одне ім'я.
        it.artists = merge(kept)
    return {name: len(spots) for name, spots in places.items() if _is_venue_word(name)}


def settle(items: list, dictionary: Dictionary | None = None) -> dict:
    """Остаточне рішення по всьому прогону.

    1. Словник і «театр в одному місці = майданчик» (щабель 1 очищається від залів).
    2. Імена, що пережили очищення, стають відомими: так Karabas, який виконавця не віддає,
       отримує його з назви, якщо інше джерело вже назвало його виконавцем.
    3. Правила на назві для подій, де структура нічого не дала. Є виконавець зі структури —
       назву не чіпаємо: двох джерел правди для однієї події не тримаємо.
    4. Те саме очищення для щойно знайдених.

    Змінює `item.artists` на місці. Повертає звіт: назви з театральним словом із кількістю місць,
    щоб людина один раз вирішила спірні в `artists.json`, а не правила вгадували щоразу.
    """
    dictionary = dictionary or Dictionary()
    dropped: collections.Counter = collections.Counter()
    _drop_venues(items, dictionary, dropped)
    dictionary.add_names(a.name for it in items for a in it.artists if a.how in ("source", "dictionary"))
    for it in items:
        if not it.artists:
            it.artists = from_title(it.title, dictionary, it.category)
    ambiguous = _drop_venues(items, dictionary, dropped)
    return {"dropped_as_venue": dict(dropped), "venue_word_places": ambiguous}


# ---- Щабель 4: модель, що лише цитує

LLM_CACHE = DICT_PATH.parent / "cache" / "artists_llm.json"
LLM_BATCH = 8
LLM_TEXT = 1500                  # символів тексту на подію: далі йде шаблон продавця й юридичне


def _llm_prompt(batch: list) -> str:
    lines = []
    for n, it in enumerate(batch, 1):
        text = re.sub(r"\s+", " ", it.text or it.description or "")[:LLM_TEXT]
        lines.append(f"{n}. Назва: «{it.title}» · Майданчик: {it.venue_name or '—'} · "
                     f"Категорія: {it.category}\nТекст: {text or '—'}")
    return BODY + BATCH_FORMAT + "\n\n" + "\n\n".join(lines)


def _parse_batch(raw: str, size: int):
    start, end = raw.find("{"), raw.rfind("}")
    try:
        rows = json.loads(raw[start:end + 1]).get("events")
    except (ValueError, AttributeError):
        return None
    out = {}
    for row in rows if isinstance(rows, list) else []:
        try:
            n = int(row.get("n"))
        except (TypeError, ValueError, AttributeError):
            continue
        if 1 <= n <= size and isinstance(row.get("artists"), list):
            out[n] = row["artists"]
    return out


def _verified(proposed: list, it, dictionary: Dictionary | None = None) -> list[Artist]:
    """Ім'я мусить стояти в цитаті, а цитата — в назві чи тексті цієї ж події. Тема трибʼюту
    («Queen при свічках») і виконавець, знайдений лише в назві-темі, відкидаються, як і для структури."""
    dictionary = dictionary or Dictionary()
    haystack = key(f"{it.title} {it.text or it.description or ''}")
    marked = {key(m.group(1)) for seg in _SEGMENTS.split(_NOISE.sub(" ", clean_text(it.title)))
              for m in [_GROUP_MARK.match(seg.strip())] if m}
    out = []
    for a in proposed:
        if not isinstance(a, dict):
            continue
        quote = clean_text(a.get("evidence") or "")
        role = a.get("role") if a.get("role") in ("headliner", "support", "host") else "headliner"
        for name in split_pair(display(a.get("name") or "")):      # пара людей — двоє артистів
            k = key(name)
            if (not name or len(name) > MAX_NAME or not quote or key(quote) not in haystack
                    or not has_name(name, quote) or _PROMOTER.search(k) or not has_proper(name)):
                continue
            if _THEME.search(it.title) and k in key(it.title) and k not in marked:
                continue
            hit = dictionary.lookup(name)
            # Назва самого шоу — не виконавець; бренд лише з ручним записом.
            if _SHOW_WORD.search(it.title) and k in key(it.title) and not (hit and hit[1]):
                continue
            out.append(Artist(name, role=role, how="llm", confidence=0.8))
    out = merge(out)
    # У виставі кілька імен поспіль — це склад акторів, а не виконавці (правило власника): лишаємо
    # лише одне ім'я, тобто моновиставу чи єдиного виконавця.
    return out if it.category not in STRICT_CATEGORIES or len(out) <= 1 else []


def llm_fill(items: list, ask, dictionary: Dictionary | None = None, cache_path=None) -> dict:
    """Щабель 4: події, де щаблі 1–3 нічого не дали, а артист можливий, віддаються моделі.

    `ask(prompt) -> str` — транспорт (`Agent.ask`). Відповіді кешуються за назвою й текстом, тож
    повторний прогін не платить двічі. Збій транспорту лишає події без артиста, а не ламає прогін.
    Зали й промоутери відсікає те саме очищення, що й для структури.
    """
    dictionary = dictionary or Dictionary()
    path = LLM_CACHE if cache_path is None else cache_path
    try:
        cache = json.loads(pathlib.Path(path).read_text("utf-8"))
    except (OSError, ValueError):
        cache = {}

    def ident(it) -> str:
        # У ключ входить і підказка: змінили правила — старі відповіді не годяться.
        return hashlib.sha1(f"{BODY}\n{it.title}\n{it.text or it.description}".encode()).hexdigest()

    targets = [it for it in items if not it.artists and it.category in TITLE_CATEGORIES]
    stats = {"asked": 0, "cached": 0, "found": 0, "errors": 0, "targets": len(targets)}
    todo: dict[str, list] = {}
    for it in targets:
        h = ident(it)
        if h in cache:
            stats["cached"] += 1
            it.artists = _verified(cache[h], it, dictionary)
        else:
            todo.setdefault(h, []).append(it)
    unique = [group[0] for group in todo.values()]
    for start in range(0, len(unique), LLM_BATCH):
        batch = unique[start:start + LLM_BATCH]
        try:
            parsed = _parse_batch(ask(_llm_prompt(batch)), len(batch))
        except Exception:                                        # noqa: BLE001 — див. докстрінг
            parsed = None
        stats["asked"] += 1
        if parsed is None:
            stats["errors"] += 1
            continue
        for n, it in enumerate(batch, 1):
            if n not in parsed:
                continue                                         # модель пропустила подію: спитаємо наступного разу
            cache[ident(it)] = parsed[n]
            for twin in todo[ident(it)]:
                twin.artists = _verified(parsed[n], twin, dictionary)
    stats["found"] = sum(1 for it in targets if it.artists)
    if stats["asked"]:
        try:
            pathlib.Path(path).parent.mkdir(exist_ok=True)
            pathlib.Path(path).write_text(json.dumps(cache, ensure_ascii=False), "utf-8")
        except OSError:
            pass
    stats["dropped_as_venue"] = dict(_drop_llm_venues(items, dictionary))
    return stats


def _drop_llm_venues(items: list, dictionary: Dictionary) -> collections.Counter:
    dropped: collections.Counter = collections.Counter()
    _drop_venues(items, dictionary, dropped)
    return dropped

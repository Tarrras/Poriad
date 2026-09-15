"""Останній щабель класифікації: модель читає те, чого не розібрали тип і словник.

Працює лише над fallback (кілька відсотків обходу): екскурсії з назвами будівель, літературні
вечори тощо. Три запобіжники важливіші за саму класифікацію:

1. Вибір лише з наявних категорій або «жодна»: модель не заводить нову полицю, «жодна» йде у
   звіт про прогалини.
2. Жодних координат: модуль фізично не вміє їх повертати.
3. Окремий щабель `category_how = "agent"`, щоб у звіті було видно частку бази на його судженні.

Мережа через `urllib`, без SDK. Постачальник — параметр (за замовчуванням OpenAI); ключ і
модель зі змінних `OPENAI_API_KEY`/`OPENAI_MODEL` або `ANTHROPIC_API_KEY`/`ANTHROPIC_MODEL`.
"""
from __future__ import annotations

import json
import os
import pathlib
import urllib.error
import urllib.request

from .normalize import CATEGORIES

# Корінь репозиторію: цей файл лежить у tools/ingest/.
ENV_FILE = pathlib.Path(__file__).resolve().parent.parent.parent / ".env"


def load_env(path: pathlib.Path = ENV_FILE) -> int:
    """Підтягує `.env`, якщо він є. Повертає, скільки змінних додано.

    Наявне середовище сильніше за файл; відсутній файл — не помилка. Без сторонніх бібліотек.
    """
    try:
        text = path.read_text("utf-8")
    except (OSError, UnicodeDecodeError):
        return 0
    added = 0
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, _, value = line.partition("=")
        name = name.removeprefix("export ").strip()
        value = value.strip().strip('"').strip("'")
        if name and value and name not in os.environ:
            os.environ[name] = value
            added += 1
    return added

# Подій на запит: при збої втрачається лише одна пачка.
BATCH = 25


# ---- Провайдери. Постачальник моделі — параметр: різниця лише в адресі, заголовках і полі з
# текстом, запобіжники спільні. Відповідь — звичайний текст, `_parse` дістає масив з прози чи ```json.

class _Provider:
    name: str
    endpoint: str
    env_key: str
    env_model: str
    default_model: str

    def headers(self, key: str) -> dict: raise NotImplementedError
    def body(self, model: str, prompt: str) -> dict: raise NotImplementedError
    def text(self, payload: dict) -> str: raise NotImplementedError


class _OpenAI(_Provider):
    name = "openai"
    endpoint = "https://api.openai.com/v1/chat/completions"
    env_key = "OPENAI_API_KEY"
    env_model = "OPENAI_MODEL"
    # Модель зі змінної середовища: перелік у постачальників міняється частіше за цей файл.
    default_model = "gpt-4.1-mini"

    def headers(self, key):
        return {"content-type": "application/json", "authorization": f"Bearer {key}"}

    def body(self, model, prompt):
        return {"model": model, "messages": [{"role": "user", "content": prompt}]}

    def text(self, payload):
        choices = payload.get("choices") or []
        return (choices[0].get("message") or {}).get("content", "") if choices else ""


class _Anthropic(_Provider):
    name = "anthropic"
    endpoint = "https://api.anthropic.com/v1/messages"
    env_key = "ANTHROPIC_API_KEY"
    env_model = "ANTHROPIC_MODEL"
    default_model = "claude-sonnet-5"

    def headers(self, key):
        return {"content-type": "application/json", "anthropic-version": "2023-06-01",
                "x-api-key": key}

    def body(self, model, prompt):
        return {"model": model, "max_tokens": 2000,
                "messages": [{"role": "user", "content": prompt}]}

    def text(self, payload):
        return "".join(part.get("text", "") for part in payload.get("content", []))


PROVIDERS = {p.name: p for p in (_OpenAI(), _Anthropic())}
DEFAULT_PROVIDER = "openai"

_RULES = (
    "Ти розкладаєш афішні події по категоріях застосунку.\n"
    "Дозволені категорії, і жодних інших:\n"
    "  music      — концерти, музичні вечори, оркестри\n"
    "  sport      — змагання, матчі, забіги, турніри\n"
    "  art        — театр, кіно, виставки, література, танець\n"
    "  food       — дегустації, гастрономія, фестивалі їжі й напоїв\n"
    "  games      — настільні ігри, квізи, кіберспорт\n"
    "  outdoors   — походи, природа, активності просто неба\n"
    "  social     — знайомства, спілкування, клуби за інтересами\n"
    "  comedy     — стендап, імпровізація, гумористичні шоу\n"
    "  kids       — події для дітей і родин з дітьми\n"
    "  tours      — екскурсії, прогулянки з гідом, спадщина, архітектура\n"
    "  conference — конференції, форуми, саміти, фахові зустрічі\n"
    "\n"
    "Три правила, кожне з розібраного промаху:\n"
    "1. ФОРМАТ важливіший за ТЕМУ. Показ фільму про гори — це art, а не outdoors; відеопрогулянка\n"
    "   містом у галереї — теж art. Питай себе, що людина робитиме на місці, а не про що подія.\n"
    "2. Якщо в назві лише будівля, памʼятка чи адреса й більше нічого — це tours. Квиток продають\n"
    "   на огляд цього обʼєкта, навіть коли слова «екскурсія» немає ніде.\n"
    "3. Джерело каже про рід події більше за назву: сайт міського туризму продає огляди,\n"
    "   майданчик із дитячим залом — дитяче, фаховий портал — конференції й воркшопи.\n"
    "4. Коли підходять дві категорії, виграє вужча. Наш перелік будувався виділенням: comedy і\n"
    "   kids вийшли з art, tours — з outdoors, conference — з social. Тому дитяча вистава в\n"
    "   дитячому театрі — kids, а не art; стендап — comedy, а не art; прогулянка з гідом —\n"
    "   tours, а не outdoors. Ширшу беремо лише тоді, коли вужча справді не підходить.\n"
    "\n"
    "Якщо жодна не описує подію — відповідай \"none\". Це нормальна відповідь, і вона корисніша "
    "за натягнуту категорію: за нею ми бачимо, якої полиці бракує.\n"
    "Відповідай ЛИШЕ масивом JSON виду\n"
    "[{\"n\": 1, \"category\": \"tours\", \"why\": \"назва будівлі, сайт міського туризму\"}]\n"
    "Поле why — до восьми слів про те, ЩО в тексті вирішило. Воно не потрапляє в базу: воно для\n"
    "того, щоб людина бачила, на чому ґрунтується помилка, і могла виправити саме підказку."
)


class Agent:
    """Класифікатор на моделі. `call` підміняється в тестах, щоб вони не ходили в мережу."""

    def __init__(self, *, provider: str = DEFAULT_PROVIDER, model: str | None = None,
                 api_key: str | None = None, batch: int = BATCH, call=None):
        if provider not in PROVIDERS:
            raise ValueError(f"невідомий постачальник {provider!r}; є {sorted(PROVIDERS)}")
        # `.env` читаємо тут, а не в CLI, щоб ключ бачив і той, хто збирає `Agent` сам.
        load_env()
        self.provider = PROVIDERS[provider]
        self.model = model or os.environ.get(self.provider.env_model) or self.provider.default_model
        self.api_key = (api_key if api_key is not None
                        else os.environ.get(self.provider.env_key))
        self.batch = batch
        # Прапорець, а не порівняння з `self._post`: зв'язаний метод щоразу новий, і `is not` завжди істинне.
        self._injected = call is not None
        self._call = call or self._post
        self.requests = 0
        self.errors: list[str] = []
        self.unknown: list = []               # події, для яких модель сказала «жодна»
        # Рішення з підставами в пам'яті: людина має бачити, на чому модель помилилась.
        self.decisions: list = []
        self.refused: list = []               # вигадані категорії, які запобіжник відхилив
        self.merges: list = []                # рішення про пари: (назва, назва, чи одна, чому)

    # ---- Публічне

    @property
    def ready(self) -> bool:
        return bool(self.api_key) or self._injected

    def classify(self, items) -> int:
        """Дописує категорію тим, що впали у fallback. Повертає, скільки змінено.

        Нічого не піднімає назовні: невдача агента робить обхід біднішим, а не зламаним. Категорія
        в таких подій лишається та, що була, тобто `social`.
        """
        targets = [i for i in items if i.category_how == "fallback"]
        if not targets or not self.ready:
            return 0
        changed = 0
        for start in range(0, len(targets), self.batch):
            chunk = targets[start:start + self.batch]
            try:
                answers = self._ask(chunk)
            except Exception as exc:                      # noqa: BLE001 — див. докстрінг
                self.errors.append(f"{type(exc).__name__}: {str(exc)[:120]}")
                continue
            for position, (category, why) in answers.items():
                if not 1 <= position <= len(chunk):
                    continue
                item = chunk[position - 1]
                if category == "none":
                    self.unknown.append((item.title, why))
                    continue
                if category not in CATEGORIES:            # запобіжник 1
                    self.refused.append((item.title, category, why))
                    continue
                item.category = category
                item.category_how = "agent"               # запобіжник 3
                self.decisions.append((item.title, category, why))
                changed += 1
        return changed

    def judge_pairs(self, pairs) -> list[bool]:
        """Чи це та сама подія. `pairs` — послідовність (item_a, item_b).

        Для пар, які правило за словами не зведе: назви різними мовами («Львів Стартап Сніданок»
        і «Lviv Startup Breakfast»). Хибне злиття ховає подію назавжди, тому за замовчуванням
        не зливати. Повертає список тієї ж довжини; невдача — усі `False`.
        """
        pairs = list(pairs)
        if not pairs or not self.ready:
            return [False] * len(pairs)
        verdicts = [False] * len(pairs)
        for start in range(0, len(pairs), self.batch):
            chunk = pairs[start:start + self.batch]
            lines = []
            for number, (a, b) in enumerate(chunk, 1):
                lines.append(f"{number}. «{a.title}» ({a.source_slug})"
                             f"  ПРОТИ  «{b.title}» ({b.source_slug})"
                             f" · майданчик: {a.venue_name or '—'} · місто: {a.city}")
            try:
                answers = _parse_pairs(self._call(_PAIR_RULES + "\n\n" + "\n".join(lines)))
            except Exception as exc:                      # noqa: BLE001
                self.errors.append(f"pairs {type(exc).__name__}: {str(exc)[:100]}")
                continue
            for position, (same, why) in answers.items():
                if 1 <= position <= len(chunk):
                    verdicts[start + position - 1] = same
                    self.merges.append((chunk[position - 1][0].title,
                                        chunk[position - 1][1].title, same, why))
        return verdicts

    def ask(self, prompt: str) -> str:
        """Один запит, сира відповідь. Для того, що не є класифікацією — наприклад рецензії.

        Тримає ту саму транспортну обвʼязку: постачальник, ключ, лічильник запитів. Помилку
        піднімає назовні, бо той, хто кличе, знає краще, чим її замінити.
        """
        return self._call(prompt)

    # ---- Внутрішнє

    def _ask(self, chunk) -> dict[int, str]:
        lines = []
        for number, item in enumerate(chunk, 1):
            # Опис обрізаємо: 200 символів досить, повний текст роздуває запит.
            description = (item.description or "")[:200].replace("\n", " ")
            lines.append(f"{number}. «{item.title}» · майданчик: {item.venue_name or '—'}"
                         f" · місто: {item.city}"
                         f" · джерело: {getattr(item, 'source_slug', '—')}"
                         + (f" · {description}" if description else ""))
        text = self._call(_RULES + "\n\n" + "\n".join(lines))
        return _parse(text)

    def _post(self, prompt: str) -> str:
        provider = self.provider
        request = urllib.request.Request(
            provider.endpoint,
            data=json.dumps(provider.body(self.model, prompt)).encode(),
            headers=provider.headers(self.api_key or ""),
        )
        self.requests += 1
        with urllib.request.urlopen(request, timeout=90) as response:
            payload = json.loads(response.read())
        return provider.text(payload)


_PAIR_RULES = (
    "Кожен рядок — ДВІ назви подій, які відбуваються в ту саму хвилину й на тій самій точці, але\n"
    "з різних джерел. Скажи для кожного, чи це ОДНА подія, продана двома продавцями.\n"
    "\n"
    "Так буває, коли продавці підписують ту саму подію по-різному: один додає абревіатуру театру,\n"
    "другий жанр, третій перекладає назву іншою мовою.\n"
    "\n"
    "Але на одному майданчику о тій самій годині можуть іти й РІЗНІ події — у сусідніх залах або\n"
    "в різних кімнатах. Помилкове злиття гірше за пропущений дубль: подія зникає назавжди, і\n"
    "ніхто не дізнається, що вона була. Коли не впевнений — відповідай false.\n"
    "\n"
    "Відповідай ЛИШЕ масивом JSON виду\n"
    "[{\"n\": 1, \"same\": true, \"why\": \"та сама назва українською й англійською\"}]"
)


def _parse_pairs(text: str) -> dict:
    start, end = text.find("["), text.rfind("]")
    if start < 0 or end <= start:
        return {}
    try:
        rows = json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return {}
    out = {}
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        try:
            number = int(row.get("n"))
        except (TypeError, ValueError):
            continue
        out[number] = (bool(row.get("same")), str(row.get("why") or "").strip()[:80])
    return out


def _parse(text: str) -> dict[int, str]:
    """Витягує масив JSON із відповіді. Модель може обгорнути його в ```json — це не помилка."""
    start, end = text.find("["), text.rfind("]")
    if start < 0 or end <= start:
        return {}
    try:
        rows = json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return {}
    answers: dict[int, str] = {}
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        try:
            number = int(row.get("n"))
        except (TypeError, ValueError):
            continue
        category = str(row.get("category") or "").strip().lower()
        if category:
            answers[number] = (category, str(row.get("why") or "").strip()[:80])
    return answers

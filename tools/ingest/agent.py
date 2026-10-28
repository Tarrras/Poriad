"""Останній щабель класифікації: модель читає те, чого не розібрали тип і словник.

Працює лише над fallback (кілька відсотків обходу): екскурсії з назвами будівель, літературні
вечори тощо. Три запобіжники важливіші за саму класифікацію:

1. Вибір лише з наявних категорій або «жодна»: модель не заводить нову полицю, «жодна» йде у
   звіт про прогалини.
2. Жодних координат: модуль фізично не вміє їх повертати.
3. Окремий щабель `category_how = "agent"`, щоб у звіті було видно частку бази на його судженні.

Мережа через `urllib`, без SDK. Постачальник — параметр. За замовчуванням `claude`: `claude -p` за
підпискою Max, модель `opus` (змінна `CLAUDE_AGENT_MODEL`), ключ не потрібен. Інші: `openai`
(`OPENAI_API_KEY`/`OPENAI_MODEL`) і `anthropic` (`ANTHROPIC_API_KEY`/`ANTHROPIC_MODEL`).
Мірка 2026-10-05 на золотих наборах: артисти precision 96,3% / recall 77,2% (OpenAI 95,6% / 80,1%),
категорії 19 із 20 (OpenAI 20 із 20; промах — «Зоопарк», постійний заклад, дала outdoors).
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request

from .normalize import CATEGORIES

# Корінь репозиторію: цей файл лежить у tools/ingest/.
ENV_FILE = pathlib.Path(__file__).resolve().parent.parent.parent / ".env"


_ENV_PREFIXES = ("OPENAI_", "ANTHROPIC_")


def load_env(path: pathlib.Path = ENV_FILE) -> int:
    """Підтягує `.env`, якщо він є. Повертає, скільки змінних додано.

    Наявне середовище сильніше за файл; відсутній файл — не помилка. Без сторонніх бібліотек.
    Лише ключі моделей: `.env` тримає й `SUPABASE_DB_URL`, а конвеєру доступ до бази не потрібен.
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
        if name.startswith(_ENV_PREFIXES) and value and name not in os.environ:
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
    keyless = False          # true — без HTTP і ключа: модель кличе локальний CLI за підпискою

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


class _ClaudeCLI(_Provider):
    """`claude -p` за підпискою (Max), а не за ключем API. Вхід — звичайний вхід користувача чи
    `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token`). Модель — аліас CLI: `opus`, `fable`, `sonnet`."""
    name = "claude"
    endpoint = ""
    env_key = "claude у PATH"      # лише для повідомлень «потрібен …»; змінної середовища нема
    env_model = "CLAUDE_AGENT_MODEL"
    default_model = "opus"
    keyless = True


PROVIDERS = {p.name: p for p in (_OpenAI(), _Anthropic(), _ClaudeCLI())}
DEFAULT_PROVIDER = "claude"

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
    "   Квиток на візит у заклад просто неба — зоопарк, ботсад, парк — це outdoors, а не «жодна»:\n"
    "   афіша продає саме відвідування на дату, навіть коли формату події у назві нема.\n"
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
        self.failures = 0                     # запити, що закінчились помилкою транспорту
        self.errors: list[str] = []
        self.unknown: list = []               # події, для яких модель сказала «жодна»
        # Рішення з підставами в пам'яті: людина має бачити, на чому модель помилилась.
        self.decisions: list = []
        self.refused: list = []               # вигадані категорії, які запобіжник відхилив
        self.merges: list = []                # рішення про пари: (назва, назва, чи одна, чому)
        self.blurb_refused: list = []         # речення, що не пройшли _blurb_ok: (назва, речення, чому)
        self.pitch_refused: list = []         # описи, що не пройшли _pitch_ok: (назва, опис, чому)

    # ---- Публічне

    @property
    def ready(self) -> bool:
        keyless = self.provider.keyless and shutil.which("claude") is not None
        return bool(self.api_key) or self._injected or keyless

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

    def describe(self, items, cache_path=None) -> dict:
        """Речення «що це» (`item.blurb`, у базі `events.blurb`) для опублікованих подій, найближчі першими.

        Кеш за вмістом (підказка, назва, текст, склад): щоденний обхід питає лише нове. `""` — модель не
        зрозуміла з тексту, що це, або речення не пройшло `_blurb_ok`: у базі тоді порожньо, а не вигадка.
        `None` — не питали чи збій транспорту: базу не чіпаємо. Нічого не піднімає назовні.
        """
        return self._fill(items, attr="blurb", cache_path=BLURB_CACHE if cache_path is None else cache_path,
                          key=_blurb_key, prompt=_blurb_prompt, ok=self._blurb_ok, new=BLURB_NEW, batch=BLURB_BATCH)

    def pitch(self, items, cache_path=None) -> dict:
        """Опис, що чіпляє (`item.pitch`, у базі `events.pitch`, docs/return-hooks.md): два речення під «що це» для
        стосу «Ваш тиждень». Після `describe`: модель бачить речення «що це» й не переказує його, тож питаємо лише
        тих, кому речення вже вирішене. Той самий кеш за вмістом і ті самі значення `""` і `None`, що в `describe`.
        """
        return self._fill(items, attr="pitch", cache_path=PITCH_CACHE if cache_path is None else cache_path,
                          key=_pitch_key, prompt=_pitch_prompt, ok=self._pitch_ok, new=PITCH_NEW, batch=PITCH_BATCH,
                          eligible=lambda i: getattr(i, "blurb", None) is not None)

    def _fill(self, items, *, attr, cache_path, key, prompt, ok, new, batch, eligible=lambda i: True) -> dict:
        """Спільне для `describe` і `pitch`: кеш, ліміт нових за прогін, пачки, запобіжник `ok`."""
        path = pathlib.Path(cache_path)
        try:
            cache = json.loads(path.read_text("utf-8"))
        except (OSError, ValueError):
            cache = {}
        targets = sorted((i for i in items if i.stage == "published" and eligible(i)), key=lambda i: i.starts_at)
        todo: dict[str, list] = {}
        for it in targets:
            h = key(it)
            if h in cache:
                setattr(it, attr, ok(cache[h], it))
            else:
                todo.setdefault(h, []).append(it)
        fresh = list(todo.items())[:new] if self.ready else []
        stats = {"targets": len(targets), "cached": len(targets) - sum(map(len, todo.values())),
                 "asked": 0, "left": len(todo) - len(fresh)}
        for start in range(0, len(fresh), batch):
            chunk = fresh[start:start + batch]
            try:
                answers = _parse_field(self._call(prompt([group[0] for _, group in chunk])), attr)
            except Exception as exc:                      # noqa: BLE001 — див. докстрінг describe
                self.errors.append(f"{attr} {type(exc).__name__}: {str(exc)[:100]}")
                continue
            stats["asked"] += 1
            for n, (h, group) in enumerate(chunk, 1):
                if n in answers:                          # пропущену подію спитаємо наступного разу
                    cache[h] = answers[n]
                    for it in group:
                        setattr(it, attr, ok(answers[n], it))
        if stats["asked"]:
            try:
                path.parent.mkdir(exist_ok=True)
                path.write_text(json.dumps(cache, ensure_ascii=False), "utf-8")
            except OSError:
                pass
        stats["written"] = sum(1 for i in targets if getattr(i, attr))
        stats["empty"] = sum(1 for i in targets if getattr(i, attr) == "")
        return stats

    def _blurb_ok(self, text, item) -> str:
        """Речення або `""`. Запобіжник поверх підказки: модель іноді все ж повторює назву чи пише формулу."""
        text = " ".join(str(text or "").split()).replace("'", "’").replace("ʼ", "’")
        if len(text) > 1 and text[0] + text[-1] in ("«»", '""', "“”"):     # усе речення в лапках
            text = text[1:-1].strip()
        if not text:
            return ""
        letters = [c for c in text if c.isalpha()]
        # Назва з одного слова («Стендап», «Енеїда») може стояти в реченні як жанр чи твір; з двох і більше — це повтор.
        title = " ".join(re.sub(r"\W+", " ", item.title.lower()).split())
        why = ("довге" if len(text) > BLURB_MAX_CHARS
               else "тире чи знак" if re.search(r"[—–?!]", text)
               else "ціна" if re.search(r"₴|\bгрн", text)
               else "капс" if sum(c.isupper() for c in letters) > len(letters) / 3
               else "повтор назви" if " " in title and f" {title} " in " " + re.sub(r"\W+", " ", text.lower()) + " "
               else "формула" if _BLURB_FORMULAS.search(text) else None)
        if why:
            self.blurb_refused.append((item.title, text, why))
            return ""
        return text

    def _pitch_ok(self, text, item) -> str:
        """Опис або `""`. Поверх підказки: модель іноді пише про назву й організаторів, переносить оцінки продавця
        чи дописує речення «що це» займенником."""
        text = " ".join(str(text or "").split()).replace("'", "’").replace("ʼ", "’")
        if len(text) > 1 and text[0] + text[-1] in ("«»", '""', "“”"):
            text = text[1:-1].strip()
        if not text:
            return ""
        letters = [c for c in text if c.isalpha()]
        title = " ".join(re.sub(r"\W+", " ", item.title.lower()).split())
        why = ("довге" if len(text) > PITCH_MAX_CHARS
               else "тире чи знак" if re.search(r"[—–?!]", text)
               else "ціна" if re.search(r"₴|\bгрн", text)
               else "капс" if sum(c.isupper() for c in letters) > len(letters) / 3
               else "повтор назви" if " " in title and f" {title} " in " " + re.sub(r"\W+", " ", text.lower()) + " "
               else "формула" if _BLURB_FORMULAS.search(text) or _PITCH_FORMULAS.search(text) else None)
        if why:
            self.pitch_refused.append((item.title, text, why))
            return ""
        return text

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

    def _run_claude(self, prompt: str) -> str:
        """Один виклик `claude -p`: без інструментів, MCP, налаштувань користувача й проєкту (hooks,
        CLAUDE.md), у нейтральній теці. Промпт іде через stdin: він завеликий для аргументу."""
        self.requests += 1
        # Токен із секрету CI міг потрапити з переносом рядка (скопійований з терміналу): CLI тоді
        # відповідає «Invalid auth token». Пробіли в токені не бувають, тож їх прибираємо.
        env = dict(os.environ)
        if env.get("CLAUDE_CODE_OAUTH_TOKEN"):
            env["CLAUDE_CODE_OAUTH_TOKEN"] = "".join(env["CLAUDE_CODE_OAUTH_TOKEN"].split())
        proc = subprocess.run(
            ["claude", "-p", "--model", self.model, "--no-session-persistence", "--restricted",
             "--tools", "", "--disable-slash-commands", "--strict-mcp-config",
             "--system-prompt", "Відповідай лише тим, про що просять, без вступів і пояснень."],
            input=prompt, capture_output=True, text=True, timeout=300, cwd=tempfile.gettempdir(), env=env)
        if proc.returncode != 0:
            self.failures += 1
            raise RuntimeError((proc.stderr or proc.stdout).strip()[:200] or f"claude -p: код {proc.returncode}")
        return proc.stdout

    def _post(self, prompt: str) -> str:
        provider = self.provider
        if provider.keyless:
            return self._run_claude(prompt)
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
        out[number] = (row.get("same") is True, str(row.get("why") or "").strip()[:80])
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


# ---- Речення «що це» (events.blurb): рядок під назвою в Telegram, згодом на сайті й у застосунку

BLURB_CACHE = pathlib.Path(__file__).resolve().parent / "cache" / "blurbs.json"
BLURB_BATCH = 20
BLURB_TEXT = 1200                 # символів тексту картки: далі шаблон продавця, правила залу й юридичне
BLURB_MAX_CHARS = 120             # просимо до 90, відкидаємо довше за це
# ponytail: нових подій за прогін не більше BLURB_NEW (~30 с на пачку з 20), найближчі першими. Перший прогін —
# ~2300 подій (dev, 26.10), це година понад звичні 30–70 хв обходу при timeout 120; решта доходить за кілька днів.
# Ручний прогін може підняти межу змінною INGEST_BLURB_NEW. Швидше — паралельні виклики.
BLURB_NEW = int(os.environ.get("INGEST_BLURB_NEW") or 400)
# Формули продавця й логістика: «перенесено з вересня» в тексті картки застаріває раніше за подію.
_BLURB_FORMULAS = re.compile(r"чому варто|не пропуст|запрошу|незабутн|унікальн|справжн\w* свят|перенес|скасов", re.I)

_BLURB_RULES = """Ти пишеш для афіші застосунку «Поряд» одне речення «що це» під назвою події.
Назву, жанр, дату, час, заклад і ціну читач бачить поруч. Твоє речення каже те, чого назва не каже:
що там відбувається, хто виступає, про що це.

Правила:
- одне речення українською, до 90 символів, з крапкою в кінці;
- лише з того, що є в назві, тексті й складі нижче. Нічого від себе: ні фактів, ні оцінок
  («найкращий», «унікальний», «легендарний»), ні того, чого текст не каже;
- не повторюй назву події, місто, дату, час, заклад і ціну;
- без тире, знаків оклику й питання, без емодзі й капсу;
- без формул продавця: «Чому варто відвідати», «не пропустіть», «запрошуємо», «незабутні емоції»,
  «справжнє свято»;
- склад вистави не переписуй. Імʼя виконавця, гурту чи оркестру можна, якщо його нема в назві;
- голос теплий, упевнений, трохи іронічний, як у друга, що знає, куди піти. Іронія лише там, де текст
  дає привід, і ніколи про війну, памʼять, утрату чи хворобу;
- якщо з тексту не зрозуміло, що це за подія (лише назва, дата й заклад, або сама реклама без суті),
  blurb порожній. Порожньо краще за вигадку.

Як це виглядає:
- текст «…історія двох сімей, які живуть в одному з подільських двориків повоєнного Києва…»
  → «Комедія про дві сімʼї з одного подільського дворика повоєнних років.»
- текст «…стендап-хепенінг про людей… Тих, кому можеш розповісти все, крім того, де ти живеш…»
  → «Стендап про друзів, яким розповідаєш усе, крім своєї адреси.»
- текст «Чому варто відвідати? Яскраве шоу! Незабутні емоції для всієї родини!» → «»

Відповідай ЛИШЕ JSON виду
{"events": [{"n": 1, "blurb": "..."}]}
Кожна подія з переліку має бути у відповіді, навіть з порожнім "blurb"."""


def _blurb_source(it) -> tuple[str, str]:
    """(текст, склад) події, як їх бачить модель. Одне місце і для підказки, і для ключа кешу."""
    text = " ".join((getattr(it, "text", "") or it.description or "").split())[:BLURB_TEXT]
    cast = ", ".join(a.name for a in getattr(it, "artists", []) or [])
    return text, cast


def _blurb_key(it) -> str:
    # У ключ входить і підказка: змінили правила — старі речення не годяться.
    text, cast = _blurb_source(it)
    return hashlib.sha1(f"{_BLURB_RULES}\n{it.title}\n{it.category}\n{cast}\n{text}".encode()).hexdigest()


def _blurb_prompt(batch: list) -> str:
    lines = []
    for n, it in enumerate(batch, 1):
        text, cast = _blurb_source(it)
        lines.append(f"{n}. Назва: «{it.title}» · Категорія: {it.category}"
                     + (f" · Склад: {cast}" if cast else "") + f"\nТекст: {text or '—'}")
    return _BLURB_RULES + "\n\n" + "\n\n".join(lines)


# ---- Опис, що чіпляє (events.pitch): два речення під «що це» у стосі «Ваш тиждень» (docs/return-hooks.md)

PITCH_CACHE = pathlib.Path(__file__).resolve().parent / "cache" / "pitches.json"
PITCH_BATCH = 20
PITCH_MAX_CHARS = 200             # просимо до 180, відкидаємо довше за це
# ponytail: як BLURB_NEW — найближчі першими, решта доходить за кілька днів; INGEST_PITCH_NEW піднімає межу.
PITCH_NEW = int(os.environ.get("INGEST_PITCH_NEW") or 400)
# Проба v1–v4 (28.10): мова про текст чи організаторів замість події, оцінки продавця, продовження «що це» займенником.
_PITCH_FORMULAS = re.compile(r"\bназв[аиуоі]\b|підзаголов|організатор|обіця|натяка|вражаюч|яскрав\w* представник|"
                             r"найкращ|неймовірн|^(вона|вони|до них|поруч із ними|окрім|до компанії)\b", re.I)

_PITCH_RULES = """Ти пишеш для афіші застосунку «Поряд» короткий опис події — два речення, які чіпляють.
Людина бачить його в стосі «так/ні» і за кілька секунд вирішує, чи їй це цікаво. Над описом стоїть речення
«що це» (дано нижче як «Що це»), поруч — назва, жанр, заклад, дата й ціна.

Мета — щоб людина побачила подію зсередини і захотіла туди. Для цього в описі має бути хоча б одна картинка
чи дія: що там відбувається, що людина побачить, почує чи робитиме руками, який конфлікт чи поворот у сюжеті,
чим цей формат незвичний. Конкретна деталь з тексту завжди сильніша за прикметник.

Правила:
- два речення українською, разом до 180 символів, крапка в кінці кожного;
- опис має читатися й сам по собі, без «Що це» поруч: не починай з «вона», «вони», «до них», «поруч із ними»,
  «до компанії», «окрім»;
- не переказуй «Що це» іншими словами й не повторюй назву; можна розвинути його деталлю, якої там нема.
  Місто, дату, час, заклад і ціну не називай;
- пиши про саму подію, а не про текст чи організаторів. Не можна: «назва», «підзаголовок», «сеанс має назву»,
  «організатори обіцяють», «автори натякають», «як кажуть організатори»;
- оцінок продавця не переносиш навіть як переказ чи цитату: «смішно, гостро, провокативно», «вражаюча історія»,
  «яскравий представник», «найкращий», «унікальний», «незабутній», «неймовірний», «справжній»;
- опис не може бути переліком імен. Імʼя — лише з роллю й не більше двох-трьох;
- лише факти з назви, тексту й складу нижче: нічого від себе, жодних подробиць і чисел, яких текст не каже.
  Без висновків і наслідків від себе: що людина забере додому, що там можна зробити чи відчути, якщо текст
  цього прямо не каже;
- назв сеансів, рубрик і програм у лапках не цитуй;
- без тире, знаків оклику й питання, без емодзі й капсу;
- без закликів і формул продавця: «приходьте», «бронюйте», «не пропустіть», «запрошуємо», «чому варто
  відвідати», «незабутні емоції», «справжнє свято», «чудова нагода», «для всієї родини»;
- голос спокійний, теплий і впевнений, як у друга, що знає, куди піти. Можна на «ви», без заклику. Іронія лише
  там, де текст дає привід, і ніколи про війну, памʼять, утрату чи хворобу;
- якщо в тексті нема суті (лише реклама, дата й заклад) — pitch порожній. Порожньо краще за вигадку.

Як це виглядає:
- текст «Нічна екскурсія музеєм: після закриття гості обходять зали з ліхтариками, екскурсовод розповідає
  історії, які не входять у денні екскурсії»
  погано: «Сеанс має назву "Ніч у музеї". Організатори обіцяють незабутню атмосферу.»
  добре: «Музей відкривають після закриття, і зали обходять з ліхтариками. Екскурсовод розповідає те, чого не
  почуєте на денній екскурсії.»
- текст «Стендап-вечір: Петро Іванов, Ольга Коваль, Ігор Мельник і ще двоє коміків пробують новий матеріал,
  частина жартів може не дожити до спешлу»
  погано: «До них приєднуються Ігор Мельник і ще двоє коміків.»
  добре: «Коміки пробують новий матеріал, і частина жартів може не дожити до спешлу. Ви почуєте їх раніше
  за всіх.»
- текст «Чому варто відвідати? Яскраве шоу! Незабутні емоції для всієї родини!» → «»

Перед відповіддю перечитай кожен опис: чи є тут факт чи висновок, якого нема в тексті, і чи не переказує
він «Що це». Якщо є — перепиши. Порожньо — лише коли в тексті справді нема нічого понад «Що це».

Відповідай ЛИШЕ JSON виду
{"events": [{"n": 1, "pitch": "..."}]}
Кожна подія з переліку має бути у відповіді, навіть з порожнім "pitch"."""


def _pitch_key(it) -> str:
    # У ключ входять підказка й речення «що це»: опис його продовжує і не має переказувати.
    text, cast = _blurb_source(it)
    blurb = getattr(it, "blurb", None) or ""
    return hashlib.sha1(f"{_PITCH_RULES}\n{it.title}\n{it.category}\n{cast}\n{blurb}\n{text}".encode()).hexdigest()


def _pitch_prompt(batch: list) -> str:
    lines = []
    for n, it in enumerate(batch, 1):
        text, cast = _blurb_source(it)
        lines.append(f"{n}. Назва: «{it.title}» · Категорія: {it.category}"
                     + (f" · Склад: {cast}" if cast else "")
                     + f"\nЩо це: {getattr(it, 'blurb', None) or '—'}\nТекст: {text or '—'}")
    return _PITCH_RULES + "\n\n" + "\n\n".join(lines)


def _parse_field(text: str, field: str) -> dict[int, str]:
    """`{"events": [{"n": 1, "<field>": "..."}]}` → {1: "..."}; зіпсоване — порожньо."""
    start, end = text.find("{"), text.rfind("}")
    try:
        rows = json.loads(text[start:end + 1]).get("events")
    except (ValueError, AttributeError):
        return {}
    out = {}
    for row in rows if isinstance(rows, list) else []:
        try:
            n = int(row.get("n"))
        except (TypeError, ValueError, AttributeError):
            continue
        if isinstance(row.get(field), str):
            out[n] = row[field]
    return out

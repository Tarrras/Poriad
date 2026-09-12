"""Останній щабель класифікації: модель читає те, чого не розібрали тип і словник.

Навіщо він тут і чому саме тут.

Драбина категорій має три щаблі: тип schema.org, словник, а далі `social` за замовчуванням. На
обході пʼяти міст 2026-09-11 у той останній щабель падало 95 подій, і розбір показав, що вони не
однорідні:

    39  спадщина й екскурсії від lviv.travel — «Вілла Айва», «Дім Людкевича», «Вежа Латинської
        катедри». У жодній назві немає слова «екскурсія». Зрозуміти, що назва будівлі з адресою
        на сайті міського туризму означає прогулянку з гідом, можна лише знаючи, що це таке.
    21  визначається типом майданчика: дванадцять фільмів у залі «KINOMAN», циркові шоу в цирку.
     6  уже правильно `social`: «Побачення наосліп».
     4  проста робота для словника: «Чемпіонат УПЛ», «Kyiv Food and Wine Festival».

Агент потрібен рівно для першої групи й ще для десятка літературних та музичних вечорів. Двадцять
одну подію, яку однозначно визначає майданчик, йому давати не треба: платити за недетермінованість
там, де її не було, — погана угода. Тому модуль працює лише над тим, що лишилось після словника,
тобто над сімома відсотками обходу, а не над усім.

Чим це відрізняється від телеграму, де я від агента відмовлявся: там бракувало координат, а їх у
тексті немає за жодної якості читання. Тут уся потрібна інформація в тексті є, бракує лише
судження.

Три запобіжники, і вони важливіші за саму класифікацію:

1. **Вибір лише з наявних категорій або чесне «жодна».** Модель не може завести дванадцяту
   полицю. «CAREER EXPO» вона визначить правильно, але якщо для цього роду подій категорії немає,
   правильна відповідь — «жодна», і вона йде у звіт про прогалини, а не в базу. Агент не прибирає
   продуктове рішення, він ставить його точно.
2. **Жодних координат.** Правило «координати вигадувати не можна» не слабшає від того, що модель
   звучить упевнено. Цей модуль фізично не вміє їх повертати.
3. **Окремий щабель `category_how = "agent"`.** Щоб у звіті було видно, яка частка бази тримається
   на його судженні — так само, як зараз видно частку типу й словника.

Мережа тут через `urllib`, а не через SDK: конвеєр тримається на стандартній бібліотеці, і одна
залежність заради одного POST того не варта. Ключ береться з `ANTHROPIC_API_KEY`.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

from .normalize import CATEGORIES

ENDPOINT = "https://api.anthropic.com/v1/messages"
MODEL = "claude-sonnet-5"

# Скільки подій в одному запиті. Не через ліміти моделі — вони значно більші, — а тому що при
# збої втрачається рівно одна пачка, і решта обходу лишається класифікованою.
BATCH = 25

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
    "Якщо жодна не описує подію — відповідай \"none\". Це нормальна відповідь, і вона корисніша "
    "за натягнуту категорію: за нею ми бачимо, якої полиці бракує.\n"
    "Відповідай ЛИШЕ масивом JSON виду [{\"n\": 1, \"category\": \"tours\"}], без пояснень."
)


class Agent:
    """Класифікатор на моделі. `call` підміняється в тестах, щоб вони не ходили в мережу."""

    def __init__(self, *, model: str = MODEL, api_key: str | None = None,
                 batch: int = BATCH, call=None):
        self.model = model
        self.api_key = api_key if api_key is not None else os.environ.get("ANTHROPIC_API_KEY")
        self.batch = batch
        # Прапорець, а не порівняння з `self._post`: звʼязаний метод створюється наново на
        # кожному зверненні, тож `self._call is not self._post` завжди істинне — і `ready`
        # повертав True навіть без ключа. Зловлено тестом.
        self._injected = call is not None
        self._call = call or self._post
        self.requests = 0
        self.errors: list[str] = []
        self.unknown: list[str] = []          # події, для яких модель сказала «жодна»

    # ---------------------------------------------------------------- публічне

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
            for position, category in answers.items():
                if not 1 <= position <= len(chunk):
                    continue
                item = chunk[position - 1]
                if category == "none":
                    self.unknown.append(item.title)
                    continue
                if category not in CATEGORIES:            # запобіжник 1
                    continue
                item.category = category
                item.category_how = "agent"               # запобіжник 3
                changed += 1
        return changed

    # ---------------------------------------------------------------- нутрощі

    def _ask(self, chunk) -> dict[int, str]:
        lines = []
        for number, item in enumerate(chunk, 1):
            # Опис обрізаємо: перших двохсот символів вистачає, щоб відрізнити екскурсію від
            # лекції, а повний текст лише роздуває запит.
            description = (item.description or "")[:200].replace("\n", " ")
            lines.append(f"{number}. «{item.title}» · майданчик: {item.venue_name or '—'}"
                         f" · місто: {item.city}" + (f" · {description}" if description else ""))
        text = self._call(_RULES + "\n\n" + "\n".join(lines))
        return _parse(text)

    def _post(self, prompt: str) -> str:
        body = json.dumps({
            "model": self.model,
            "max_tokens": 2000,
            "messages": [{"role": "user", "content": prompt}],
        }).encode()
        request = urllib.request.Request(ENDPOINT, data=body, headers={
            "content-type": "application/json",
            "anthropic-version": "2023-06-01",
            "x-api-key": self.api_key or "",
        })
        self.requests += 1
        with urllib.request.urlopen(request, timeout=90) as response:
            payload = json.loads(response.read())
        return "".join(part.get("text", "") for part in payload.get("content", []))


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
            answers[number] = category
    return answers

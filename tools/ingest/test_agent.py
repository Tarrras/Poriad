"""Перевірки агента-класифікатора. Мережі не потребують: клієнт підміняється.

Тестуються не здібності моделі, а запобіжники навколо неї. Здібності перевіряє живий прогін,
а запобіжники мають триматись і тоді, коли модель відповідає дурницями.
"""
from __future__ import annotations

import unittest

from .agent import Agent, _parse
from .normalize import CATEGORIES


class _Item:
    """Рівно ті поля, які читає агент."""

    def __init__(self, title, how="fallback", category="social", venue="", city="Львів", desc=""):
        self.title, self.category, self.category_how = title, category, how
        self.venue_name, self.city, self.description = venue, city, desc


def _agent(reply):
    return Agent(call=lambda prompt: reply, api_key="test")


class AgentGuards(unittest.TestCase):

    def test_classifies_and_marks_the_rung(self):
        items = [_Item("Вілла Айва"), _Item("Event Industry Forum 2027")]
        changed = _agent('[{"n":1,"category":"tours"},{"n":2,"category":"conference"}]').classify(items)
        self.assertEqual(changed, 2)
        self.assertEqual([i.category for i in items], ["tours", "conference"])
        # Щабель має бути видно у звіті окремо від типу й словника, інакше не видно, яка частка
        # бази тримається на судженні моделі.
        self.assertEqual([i.category_how for i in items], ["agent", "agent"])

    def test_only_fallback_is_offered(self):
        """Те, що вирішив тип або словник, моделі не показують і нею не перезаписують."""
        decided = _Item("Концерт", how="type", category="music")
        agent = _agent('[{"n":1,"category":"tours"}]')
        self.assertEqual(agent.classify([decided]), 0)
        self.assertEqual(decided.category, "music")

    def test_invented_category_is_refused(self):
        """Запобіжник 1: модель не може завести дванадцяту полицю."""
        item = _Item("CAREER EXPO 2026")
        self.assertEqual(_agent('[{"n":1,"category":"business"}]').classify([item]), 0)
        self.assertEqual(item.category, "social")
        self.assertEqual(item.category_how, "fallback")

    def test_none_is_a_valid_answer_and_is_recorded(self):
        """«Жодна» корисніша за натягнуту категорію: за нею видно, якої полиці бракує."""
        item = _Item("Зібрання клубу нумізматів")
        agent = _agent('[{"n":1,"category":"none"}]')
        self.assertEqual(agent.classify([item]), 0)
        self.assertEqual(item.category, "social")
        self.assertEqual(agent.unknown, ["Зібрання клубу нумізматів"])

    def test_failure_leaves_the_crawl_intact(self):
        """Невдача агента робить обхід біднішим, а не зламаним."""
        def boom(prompt):
            raise TimeoutError("no answer")
        item = _Item("Вілла Айва")
        agent = Agent(call=boom, api_key="test")
        self.assertEqual(agent.classify([item]), 0)
        self.assertEqual(item.category, "social")
        self.assertEqual(len(agent.errors), 1)

    def test_out_of_range_row_is_ignored(self):
        item = _Item("Вілла Айва")
        self.assertEqual(_agent('[{"n":9,"category":"tours"}]').classify([item]), 0)

    def test_no_key_no_call(self):
        """Без ключа агент мовчить, а не падає посеред обходу."""
        agent = Agent(api_key="")
        self.assertFalse(agent.ready)
        self.assertEqual(agent.classify([_Item("Вілла Айва")]), 0)

    def test_batches_are_independent(self):
        """Збій однієї пачки не забирає з собою решту."""
        items = [_Item(f"Подія {n}") for n in range(4)]
        calls = {"n": 0}

        def flaky(prompt):
            calls["n"] += 1
            if calls["n"] == 1:
                raise ConnectionError("dropped")
            return '[{"n":1,"category":"tours"},{"n":2,"category":"tours"}]'

        agent = Agent(call=flaky, api_key="test", batch=2)
        self.assertEqual(agent.classify(items), 2)
        self.assertEqual([i.category for i in items], ["social", "social", "tours", "tours"])

    def test_agent_cannot_return_coordinates(self):
        """Запобіжник 2: правило «координати вигадувати не можна» не слабшає через модель."""
        self.assertFalse(hasattr(Agent, "geocode"))
        self.assertFalse(hasattr(Agent, "locate"))
        item = _Item("Вілла Айва")
        _agent('[{"n":1,"category":"tours","lat":49.8,"lon":24.0}]').classify([item])
        self.assertFalse(hasattr(item, "latitude"))


class ReplyParsing(unittest.TestCase):

    def test_fenced_json_is_accepted(self):
        text = 'Ось результат:\n```json\n[{"n": 1, "category": "tours"}]\n```'
        self.assertEqual(_parse(text), {1: "tours"})

    def test_prose_without_json_yields_nothing(self):
        self.assertEqual(_parse("Вибач, не можу допомогти."), {})

    def test_broken_json_yields_nothing(self):
        self.assertEqual(_parse('[{"n": 1, "category":]'), {})

    def test_rules_name_every_category(self):
        """Перелік у підказці має збігатися з переліком у коді, інакше модель не знатиме нової."""
        from .agent import _RULES
        for category in CATEGORIES:
            self.assertIn(category, _RULES, f"категорії {category} немає в підказці агента")


if __name__ == "__main__":
    unittest.main()

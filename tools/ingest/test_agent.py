"""Перевірки агента-класифікатора. Мережі не потребують: клієнт підміняється.

Тестуються не здібності моделі, а запобіжники навколо неї. Здібності перевіряє живий прогін,
а запобіжники мають триматись і тоді, коли модель відповідає дурницями.
"""
from __future__ import annotations

import json
import pathlib
import unittest

from .agent import Agent, PROVIDERS, _parse, load_env
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
        # Щабель агента у звіті окремо: видно, яка частка бази тримається на судженні моделі.
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
        self.assertEqual(agent.unknown, [("Зібрання клубу нумізматів", "")])

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

    def test_decisions_and_refusals_are_recorded_with_reasons(self):
        """Рішення, відмови й «жодна» лягають у списки з підставою — це вхід для полірування."""
        items = [_Item("Вілла Айва"), _Item("CAREER EXPO")]
        agent = _agent('[{"n":1,"category":"tours","why":"будівля, туристичний сайт"},'
                       ' {"n":2,"category":"business","why":"фахова подія"}]')
        agent.classify(items)
        self.assertEqual(agent.decisions, [("Вілла Айва", "tours", "будівля, туристичний сайт")])
        self.assertEqual(agent.refused, [("CAREER EXPO", "business", "фахова подія")])

    def test_agent_cannot_return_coordinates(self):
        """Запобіжник 2: правило «координати вигадувати не можна» не слабшає через модель."""
        self.assertFalse(hasattr(Agent, "geocode"))
        self.assertFalse(hasattr(Agent, "locate"))
        item = _Item("Вілла Айва")
        _agent('[{"n":1,"category":"tours","lat":49.8,"lon":24.0}]').classify([item])
        self.assertFalse(hasattr(item, "latitude"))


class PairJudging(unittest.TestCase):
    """Другий обовʼязок агента: пари, яких правило за словами не бере."""

    class _E:
        def __init__(self, title, slug):
            self.title, self.source_slug = title, slug
            self.venue_name, self.city = "Момент", "Львів"

    def _pair(self):
        return (self._E("Львів Стартап Сніданок", "dou"),
                self._E("Lviv Startup Breakfast", "yoy"))

    def test_translation_pair_is_merged(self):
        agent = _agent('[{"n":1,"same":true,"why":"переклад тієї самої назви"}]')
        self.assertEqual(agent.judge_pairs([self._pair()]), [True])
        self.assertEqual(agent.merges[0][2], True)

    def test_different_events_stay_apart(self):
        agent = _agent('[{"n":1,"same":false,"why":"різні вистави в сусідніх залах"}]')
        self.assertEqual(agent.judge_pairs([self._pair()]), [False])

    def test_failure_means_no_merge(self):
        """Невдача мережі має лишити сьогоднішню поведінку, а не злити навмання."""
        def boom(_):
            raise TimeoutError("no answer")
        agent = Agent(call=boom, api_key="t")
        self.assertEqual(agent.judge_pairs([self._pair()]), [False])
        self.assertEqual(len(agent.errors), 1)

    def test_missing_answer_means_no_merge(self):
        """Мовчання про пару — теж «не зливати»: замовчування не є згодою."""
        self.assertEqual(_agent("[]").judge_pairs([self._pair()]), [False])

    def test_length_always_matches(self):
        agent = _agent('[{"n":1,"same":true}]')
        self.assertEqual(len(agent.judge_pairs([self._pair()] * 3)), 3)

    def test_no_key_no_merge(self):
        self.assertEqual(Agent(api_key="").judge_pairs([self._pair()]), [False])

    def test_prompt_warns_about_the_expensive_mistake(self):
        """Асиметрія має бути в підказці: хибне злиття ховає подію назавжди."""
        from .agent import _PAIR_RULES
        self.assertIn("false", _PAIR_RULES)
        self.assertIn("гірше", _PAIR_RULES)


class Providers(unittest.TestCase):
    """Постачальник — параметр. Запобіжники спільні, різні лише адреса, заголовки й поле тексту."""

    def test_openai_is_the_default(self):
        agent = Agent(api_key="k")
        self.assertEqual(agent.provider.name, "openai")
        self.assertIn("api.openai.com", agent.provider.endpoint)

    def test_each_provider_reads_its_own_key(self):
        for name, provider in PROVIDERS.items():
            with self.subTest(name):
                self.assertTrue(provider.env_key.endswith("_API_KEY"))
                self.assertTrue(provider.headers("secret"))
                self.assertIn("secret", json.dumps(provider.headers("secret")))

    def test_openai_body_and_answer(self):
        p = PROVIDERS["openai"]
        self.assertEqual(p.body("m", "hi")["messages"][0]["content"], "hi")
        answer = {"choices": [{"message": {"content": '[{"n":1,"category":"tours"}]'}}]}
        self.assertEqual(_parse(p.text(answer)), {1: ("tours", "")})

    def test_anthropic_body_and_answer(self):
        p = PROVIDERS["anthropic"]
        self.assertEqual(p.body("m", "hi")["messages"][0]["content"], "hi")
        answer = {"content": [{"type": "text", "text": '[{"n":1,"category":"tours"}]'}]}
        self.assertEqual(_parse(p.text(answer)), {1: ("tours", "")})

    def test_empty_answer_does_not_explode(self):
        """Порожня відповідь — це нуль класифікацій, а не виняток посеред обходу."""
        for name, provider in PROVIDERS.items():
            with self.subTest(name):
                self.assertEqual(_parse(provider.text({})), {})

    def test_unknown_provider_is_refused_loudly(self):
        with self.assertRaises(ValueError):
            Agent(provider="gemini", api_key="k")

    def test_model_comes_from_the_environment(self):
        """Зміна моделі не має бути зміною коду: переліки оновлюються частіше за цей файл."""
        import os
        os.environ["OPENAI_MODEL"] = "gpt-test"
        try:
            self.assertEqual(Agent(api_key="k").model, "gpt-test")
        finally:
            del os.environ["OPENAI_MODEL"]
        self.assertEqual(Agent(api_key="k", model="explicit").model, "explicit")


class EnvFile(unittest.TestCase):
    """Читання `.env`. Ключ у файлі — зручність; правила навколо нього важливіші за неї."""

    def setUp(self):
        import os, tempfile
        self.dir = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self.dir.name) / ".env"
        self.saved = {k: os.environ.get(k) for k in ("T_KEY", "T_MODEL")}
        for k in self.saved:
            os.environ.pop(k, None)

    def tearDown(self):
        import os
        for k, v in self.saved.items():
            os.environ.pop(k, None)
            if v is not None:
                os.environ[k] = v
        self.dir.cleanup()

    def test_reads_pairs_and_skips_noise(self):
        import os
        self.path.write_text("# коментар\n\nT_KEY=sk-123\nбез-рівності\n", "utf-8")
        self.assertEqual(load_env(self.path), 1)
        self.assertEqual(os.environ["T_KEY"], "sk-123")

    def test_export_prefix_and_quotes_are_stripped(self):
        import os
        self.path.write_text('export T_KEY="sk-456"\n', "utf-8")
        load_env(self.path)
        self.assertEqual(os.environ["T_KEY"], "sk-456")

    def test_environment_beats_the_file(self):
        """Забутий старий ключ у файлі не має перебивати щойно заданий свідомо."""
        import os
        os.environ["T_KEY"] = "exported"
        self.path.write_text("T_KEY=from-file\n", "utf-8")
        self.assertEqual(load_env(self.path), 0)
        self.assertEqual(os.environ["T_KEY"], "exported")

    def test_missing_file_is_not_an_error(self):
        """Файла немає на свіжому клоні, і робота без агента від нього не залежить."""
        self.assertEqual(load_env(pathlib.Path(self.dir.name) / "немає"), 0)

    def test_empty_value_is_not_set(self):
        """Порожній рядок у зразку не має вдавати заданий ключ."""
        import os
        self.path.write_text("T_KEY=\n", "utf-8")
        self.assertEqual(load_env(self.path), 0)
        self.assertNotIn("T_KEY", os.environ)


class ReplyParsing(unittest.TestCase):

    def test_fenced_json_is_accepted(self):
        text = 'Ось результат:\n```json\n[{"n": 1, "category": "tours"}]\n```'
        self.assertEqual(_parse(text), {1: ("tours", "")})

    def test_reason_is_kept_for_the_human(self):
        """Підстава потрібна не базі, а людині: за нею видно, НА ЧОМУ модель помилилась."""
        self.assertEqual(_parse('[{"n":1,"category":"tours","why":"назва будівлі"}]'),
                         {1: ("tours", "назва будівлі")})

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

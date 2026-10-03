"""Пошук дублів артистів: кандидати, перевірка відповіді агента, застосування. Мережі нема."""
import json
import tempfile
import unittest
from pathlib import Path

from . import dedupe_artists as dd


def row(name, kind=None, *titles):
    return {"name": name, "kind": kind, "events": [{"title": t, "venue": "Зал", "city": "Київ"} for t in titles]}


NAMES = ["Струнний квартет «Black Tie»", "Black Tie String Quartet", "Олена Тополь", "Олена Тополя",
         "Олена Кравець", "Олена Дудич", "Андрій Бережко", "Андрій Остапенко", "BIGSHOW Band"]


class Candidates(unittest.TestCase):
    def clusters(self, names=NAMES):
        artists = [row(n) for n in names]
        return [sorted(artists[i]["name"] for i in c) for c in dd.candidates(artists)]

    def test_shared_rare_word_and_similar_words_cluster(self):
        got = self.clusters()
        self.assertIn(sorted(["Струнний квартет «Black Tie»", "Black Tie String Quartet"]), got)
        self.assertIn(sorted(["Олена Тополь", "Олена Тополя"]), got)

    def test_common_first_name_alone_does_not_cluster(self):
        flat = [n for c in self.clusters() for n in c]
        for name in ("Олена Кравець", "Олена Дудич", "Андрій Бережко", "Андрій Остапенко", "BIGSHOW Band"):
            self.assertNotIn(name, flat)

    def test_word_in_five_names_still_clusters(self):
        got = self.clusters(["Black Tie", "Black Tie Quintet", "Струнний квартет Black Tie", "DJ Olga Black", "Olga Black"])
        self.assertTrue(any({"Black Tie", "Струнний квартет Black Tie"} <= set(c) for c in got))

    def test_transliteration_clusters(self):
        got = self.clusters(["Скрябін", "Skryabin Band", "Інший Гурт"])
        self.assertTrue(any({"Скрябін", "Skryabin Band"} == set(c) for c in got))


def ask_with(*groups_per_cluster):
    def ask(prompt):
        return json.dumps({"clusters": [{"n": n, "groups": g} for n, g in enumerate(groups_per_cluster, 1)]},
                          ensure_ascii=False)
    return ask


def group(canonical, members, confidence=0.95, basis="wikipedia", reason="одне й те саме за Вікіпедією"):
    return {"canonical": canonical, "members": members, "confidence": confidence, "basis": basis, "reason": reason}


class Judge(unittest.TestCase):
    cluster = [row("Black Tie String Quartet", "group", "A"), row("Струнний квартет «Black Tie»", "group", "B")]

    def test_valid_group_is_returned(self):
        v = dd.judge([self.cluster], ask_with([group("Black Tie String Quartet",
                     ["Black Tie String Quartet", "Струнний квартет «Black Tie»"])]), wiki=False)
        self.assertEqual(len(v), 1)
        self.assertTrue(dd.accepted(v[0]))

    def test_invented_names_wrong_canonical_and_missing_reason_are_dropped(self):
        for bad in (group("Вигадане", ["Вигадане", "Black Tie String Quartet"]),
                    group("Black Tie String Quartet", ["Black Tie String Quartet", "Вигадане"]),
                    group("Чужий", ["Black Tie String Quartet", "Струнний квартет «Black Tie»"]),
                    group("Black Tie String Quartet", ["Black Tie String Quartet", "Струнний квартет «Black Tie»"], reason="")):
            self.assertEqual(dd.judge([self.cluster], ask_with([bad]), wiki=False), [])

    def test_name_used_in_two_groups_counts_once(self):
        v = dd.judge([self.cluster + [row("Black Tie Quintet")]], ask_with([
            group("Black Tie String Quartet", ["Black Tie String Quartet", "Струнний квартет «Black Tie»"]),
            group("Black Tie String Quartet", ["Black Tie String Quartet", "Black Tie Quintet"])]), wiki=False)
        self.assertEqual(len(v), 1)

    def test_low_confidence_knowledge_and_kind_conflict_are_not_applied(self):
        same = ["Black Tie String Quartet", "Струнний квартет «Black Tie»"]
        low = dd.judge([self.cluster], ask_with([group(same[0], same, confidence=0.7)]), wiki=False)[0]
        know = dd.judge([self.cluster], ask_with([group(same[0], same, basis="knowledge")]), wiki=False)[0]
        clash = [row("Скрябін", "group"), row("Андрій Кузьменко", "person")]
        conflict = dd.judge([clash], ask_with([group("Скрябін", ["Скрябін", "Андрій Кузьменко"])]), wiki=False)[0]
        self.assertEqual([dd.accepted(v) for v in (low, know, conflict)], [False, False, False])
        self.assertTrue(conflict["kind_conflict"])

    def test_a_joint_credit_is_not_folded_into_one_person(self):
        pair = [row("Сергій Степанисько", "person"), row("Вєсти Гунченко і Сергія Степаниська", "person")]
        v = dd.judge([pair], ask_with([group("Сергій Степанисько", ["Сергій Степанисько", "Вєсти Гунченко і Сергія Степаниська"])]), wiki=False)[0]
        self.assertFalse(dd.accepted(v))
        both = [row("Бампер і Сус"), row("Петро Бампер і Сус")]
        w = dd.judge([both], ask_with([group("Бампер і Сус", ["Бампер і Сус", "Петро Бампер і Сус"])]), wiki=False)[0]
        self.assertTrue(dd.accepted(w))

    def test_garbage_reply_is_a_failure_not_a_crash(self):
        self.assertEqual(dd.judge([self.cluster], lambda p: "не можу", wiki=False), [])
        self.assertEqual(dd.judge([self.cluster], lambda p: (_ for _ in ()).throw(RuntimeError("мережа")), wiki=False), [])

    def test_a_failed_batch_is_retried_once(self):
        calls = []
        good = ask_with([group("Black Tie String Quartet", ["Black Tie String Quartet", "Струнний квартет «Black Tie»"])])

        def flaky(prompt):
            calls.append(1)
            if len(calls) == 1:
                raise RuntimeError("тимчасово")
            return good(prompt)

        self.assertEqual(len(dd.judge([self.cluster], flaky, wiki=False)), 1)
        self.assertEqual(len(calls), 2)


class Passes(unittest.TestCase):
    def test_second_pass_catches_what_the_first_missed_and_keeps_best_confidence(self):
        cluster = Judge.cluster
        pair = ["Black Tie String Quartet", "Струнний квартет «Black Tie»"]
        replies = iter([ask_with([]), ask_with([group(pair[0], pair, confidence=0.93)]),
                        ask_with([group(pair[0], pair, confidence=0.97)])])
        # Два проходи по одному кластеру: 1-й порожній, 2-й знаходить пару.
        v = dd.judge_passes([cluster], lambda p: next(replies)(p), wiki=False, passes=2)
        self.assertEqual([(x["members"], x["confidence"]) for x in v], [(pair, 0.93)])


class Apply(unittest.TestCase):
    def apply(self, entries, verdicts):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.json"
            path.write_text(json.dumps(entries, ensure_ascii=False), "utf-8")
            n = dd.apply(verdicts, path)
            return n, json.loads(path.read_text("utf-8"))

    def verdict(self, canonical, members, **kw):
        return {"canonical": canonical, "members": members, "confidence": 0.95, "basis": "spelling", "reason": "лише написання",
                "kind": "person", "kind_conflict": False, **kw}

    def test_writes_alias_with_reason_and_keeps_existing(self):
        n, out = self.apply({"_": "x", "Олена Тополя": {"kind": "person", "aliases": ["Тополя О."]}},
                            [self.verdict("Олена Тополь", ["Олена Тополь", "Олена Тополя"])])
        self.assertEqual(n, 1)
        self.assertEqual(out["Олена Тополя"]["aliases"], ["Тополя О.", "Олена Тополь"])      # наявний ручний запис лишився канонічним
        self.assertIn("лише написання", out["Олена Тополя"]["merged_by"])
        self.assertNotIn("Олена Тополь", out)

    def test_creates_new_entry_and_is_idempotent(self):
        v = self.verdict("Black Tie String Quartet", ["Black Tie String Quartet", "Струнний квартет «Black Tie»"], kind="group")
        n, out = self.apply({"_": "x"}, [v, v])
        self.assertEqual((n, out["Black Tie String Quartet"]["kind"], out["Black Tie String Quartet"]["aliases"]),
                         (1, "group", ["Струнний квартет «Black Tie»"]))

    def test_already_folded_pair_creates_no_empty_entry(self):
        n, out = self.apply({"_": "x"}, [self.verdict("Крістін Мілворд (Kristine Milward)",
                                                       ["Крістін Мілворд", "Крістін Мілворд (Kristine Milward)"])])
        self.assertEqual((n, out), (0, {"_": "x"}))        # ключ без дужок уже один

    def test_unaccepted_verdicts_write_nothing(self):
        n, out = self.apply({"_": "x"}, [self.verdict("A B", ["A B", "A Bc"], confidence=0.5)])
        self.assertEqual((n, out), (0, {"_": "x"}))


if __name__ == "__main__":
    unittest.main()

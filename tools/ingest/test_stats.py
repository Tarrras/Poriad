"""Статистика прогону (emit.stats_sql): рядки ingest_runs і елементи, що на них посилаються."""
import dataclasses
import unittest

from . import emit, pipeline
from .sources import by_slug
from .test_regressions import raw_event, NOW
from .venues import VenueIndex

RUN = "00000000-0000-0000-0000-000000000001"


class StatsSql(unittest.TestCase):
    def setUp(self):
        index = VenueIndex([], "Київ", {"Зал": {"lat": 50.45, "lon": 30.53}})
        self.a = pipeline._build(raw_event(), by_slug("concert_ua"), "Київ", index, NOW)
        self.a.stage = "published"
        self.b = dataclasses.replace(self.a, source_slug="badseller", source_uid="b-1", stage="duplicate",
                                     duplicate_of=(self.a.source_slug, self.a.source_uid))

    def test_runs_items_and_links(self):
        reports = [{"source": "concert_ua", "city": "Київ", "parsed": 3, "duplicates": 0, "review": 0},
                   {"source": "karabas_status", "coverage": "partial", "review": [{"url": "x"}]}]
        parts = emit.stats_sql(reports, [self.a, self.b], RUN)
        sql = "".join(parts)
        self.assertIn("delete from private.ingest_runs where finished_at < now() - interval '30 days'", sql)
        # Три пари: два з звітів (karabas_status — під slug karabas, без міста) і badseller з елементів.
        runs = parts[1]
        self.assertEqual(runs.count("union all"), 2)
        self.assertIn("where s.slug='karabas'", runs)
        self.assertIn(emit.stats_run_id(RUN, "badseller", "Київ"), runs)
        # Дубль посилається на переможця за ключем (slug, source_uid): перенесений рядок лишає старий id.
        self.assertIn(f"'concert_ua','{self.a.source_uid}')", parts[2])
        self.assertIn("ws.slug=v.w_slug and e.source_uid=v.w_uid", parts[2])
        self.assertIn("'duplicate'", parts[2])

    def test_items_split_by_budget(self):
        items = [dataclasses.replace(self.a, source_uid=f"u{n}") for n in range(6)]
        one = emit.stats_sql([], items[:1], RUN)[-1]
        parts = emit.stats_sql([], items, RUN, max_bytes=len(one.encode()) * 2)
        self.assertGreater(len(parts), 3)
        self.assertTrue(all(p.endswith(";\n") for p in parts))


if __name__ == "__main__":
    unittest.main()

import datetime as dt
import json
import pathlib
import unittest

from tools.ingest import extract
from tools.ingest.shadow_checks import report, verdict

# Ті самі кейси ганяє двійник на TS: node supabase/functions/offer-check/verdict.test.mjs
CASES = json.loads((pathlib.Path(__file__).parent / "verdict_cases.json").read_text("utf-8"))

AT = dt.datetime(2026, 11, 7, 19, 0, tzinfo=dt.timezone(dt.timedelta(hours=2)))


def node(start="2026-11-07T19:00:00+02:00", status="https://schema.org/EventScheduled", **extra):
    return {"@type": "Event", "startDate": start, "eventStatus": status, **extra}


def judge(status=200, redirected=False, nodes=()):
    return verdict(status, redirected, list(nodes), AT, "source", "Europe/Kyiv")


class VerdictTest(unittest.TestCase):
    def test_shared_cases(self):
        for case in CASES:
            with self.subTest(case["name"]):
                nodes = extract.events_from_html(case["html"]) if "html" in case else case["nodes"]
                got = verdict(case.get("status", 200), case.get("redirected", False), nodes,
                              dt.datetime.fromisoformat(case["expected"]), case.get("policy", "source"), "Europe/Kyiv")
                self.assertEqual(got, (case["kind"], case["detail"]))

    def test_page_speaks_for_this_session(self):
        self.assertEqual(judge(nodes=[node()])[0], "scheduled")
        self.assertEqual(judge(nodes=[node(status="https://schema.org/EventCancelled")])[0], "cancelled")
        self.assertEqual(judge(nodes=[node(status="EventPostponed")])[0], "postponed")
        # Перенесено сюди — сеанс на цю дату живий.
        self.assertEqual(judge(nodes=[node(status="EventRescheduled")])[0], "scheduled")

    def test_moved_away_is_explicit_but_other_sessions_are_not(self):
        moved = node(start="2026-11-14T19:00:00+02:00", status="EventRescheduled",
                     previousStartDate="2026-11-07T19:00:00+02:00")
        self.assertEqual(judge(nodes=[moved]), ("rescheduled_away", {"new_start": "2026-11-14T19:00:00+02:00"}))
        # Один сеанс на сторінці, час інший — тихий перенос; кілька інших сеансів — наш просто зник.
        kind, detail = judge(nodes=[node(start="2026-11-07T18:00:00+02:00")])
        self.assertEqual((kind, detail["new_start"]), ("moved_silent", "2026-11-07T18:00:00+02:00"))
        kind, detail = judge(nodes=[node(start="2026-11-08T19:00:00+02:00"), node(start="2026-11-09T19:00:00+02:00")])
        self.assertEqual((kind, len(detail["dates"])), ("date_missing", 2))

    def test_sold_out_is_only_a_flag(self):
        kind, detail = judge(nodes=[node(offers={"availability": "https://schema.org/SoldOut"})])
        self.assertEqual((kind, detail["sold_out"]), ("scheduled", True))

    def test_silent_disappearance_and_failures(self):
        self.assertEqual(judge(status=404)[0], "gone")
        self.assertEqual(judge(redirected=True)[0], "redirect_away")
        self.assertEqual(judge()[0], "no_jsonld")
        self.assertEqual(judge(status=403, nodes=[node()])[0], "error")    # бан продавця — не свідчення

    def test_report_separates_explicit_from_silent(self):
        row = lambda e, v, db="withdrawn": {"at": "2026-10-21T04:00:00+00:00", "event": e, "group": "withdrawn",
                                             "twin_of": None, "slug": "karabas", "url": f"https://k.ua/{e}",
                                             "starts_at": "2026-11-07T17:00:00+00:00", "db": db, "verdict": v}
        text = report([row("a", "cancelled"), row("b", "gone"), row("e", "moved_silent"), row("f", "gone"),
                       row("c", "scheduled"), row("d", "gone", "live")])
        self.assertIn("Справді нема сеансу: 4; продавець сказав прямо: 1 (25%); та сама сторінка, інший час: 1 (25%)", text)
        self.assertIn("пропуск імпорту): 1", text)


if __name__ == "__main__":
    unittest.main()

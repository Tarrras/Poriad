"""Генерує справжній SQL для ізольованого інтеграційного тесту PostgreSQL."""
import dataclasses
import datetime as dt
import json
from . import emit, pipeline
from .sources import enabled_sources, by_slug
from .test_regressions import raw_event, NOW
from .venues import VenueIndex

RUN = "00000000-0000-0000-0000-000000000001"
index = VenueIndex([], "Київ", {"Зал": {"lat": 50.45, "lon": 30.53}})
source = by_slug("concert_ua")
a = pipeline._build(raw_event(), source, "Київ", index, NOW)
b = pipeline._build(raw_event(startDate="2026-10-18T18:00:00+03:00"), source, "Київ", index, NOW)
for item in (a, b):
    item.stage = "published"
    item.quality = .8
moved = dataclasses.replace(b, starts_at=b.starts_at + dt.timedelta(days=1),
                            ends_at=b.ends_at + dt.timedelta(days=1), previous_start=b.starts_at)
moved.source_uid = pipeline.occurrence_uid(moved.canonical_url, moved.starts_at)
moved.event_id = __import__("uuid").uuid5(pipeline.NAMESPACE, source.slug + "|" + moved.source_uid)
loser = dataclasses.replace(moved, source_slug="internet_bilet", previous_start=a.starts_at,
                            stage="duplicate", duplicate_of=(source.slug, moved.source_uid))
# Зміна посилання: той самий сеанс під новою адресою лишається тим самим рядком. Окреме джерело,
# щоб зняття за відсутністю не зачепило інші перевірки.
mv_source = dataclasses.replace(source, slug="ticketsbox", catalogs=None)
at = "2026-10-20T18:30:00+03:00"
before = pipeline._build(raw_event(name="П'ята ранку", url="https://example.org/teatr-2", startDate=at,
                                   endDate="2026-10-20T20:30:00+03:00"), mv_source, "Київ", index, NOW)
after = pipeline._build(raw_event(name="П'ята ранку", url="https://example.org/teatr-3", startDate=at,
                                  endDate="2026-10-20T20:30:00+03:00"), mv_source, "Київ", index, NOW)
other = pipeline._build(raw_event(name="Інша вистава", url="https://example.org/teatr-9", startDate=at,
                                  endDate="2026-10-20T20:30:00+03:00"), mv_source, "Київ", index, NOW)
for item in (before, after, other):
    item.stage = "published"
    item.quality = .8
karabas_uids = [f"https://example.org/k{i}" for i in range(10)]

print(json.dumps({
    "sources": emit.sources_sql(enabled_sources()),
    "insert": "".join(emit.events_sql([a, b], RUN)),
    "cancel": "".join(emit.withdrawals_sql(source.slug, [{"url": a.canonical_url,
                          "starts_at": a.starts_at.isoformat()}], RUN)),
    "move": "".join(emit.events_sql([moved], RUN)),
    "duplicate": "".join(emit.duplicates_sql([loser], RUN)),
    "uids": [a.source_uid, b.source_uid, moved.source_uid],
    "move_before": "".join(emit.events_sql([before], RUN)),
    "move_after": "".join(emit.events_sql([after], RUN)),
    "move_other": "".join(emit.events_sql([other], RUN)),
    "move_uids": [before.source_uid, after.source_uid, other.source_uid],
    "retire_after_move": emit.retire_absent_sql("ticketsbox", "Київ", [after.source_uid, other.source_uid]),
    "karabas_uids": karabas_uids,
    "retire_one": emit.retire_absent_sql("karabas", "Київ", karabas_uids[:9]),
    "retire_mass": emit.retire_absent_sql("karabas", "Київ", karabas_uids[:1]),
}))

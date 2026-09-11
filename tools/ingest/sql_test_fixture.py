"""Emit real SQL for the isolated PostgreSQL integration test."""
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
print(json.dumps({
    "sources": emit.sources_sql(enabled_sources()),
    "insert": "".join(emit.events_sql([a, b], RUN)),
    "cancel": "".join(emit.withdrawals_sql(source.slug, [{"url": a.canonical_url,
                          "starts_at": a.starts_at.isoformat()}], RUN)),
    "move": "".join(emit.events_sql([moved], RUN)),
    "duplicate": "".join(emit.duplicates_sql([loser], RUN)),
    "uids": [a.source_uid, b.source_uid, moved.source_uid],
}))

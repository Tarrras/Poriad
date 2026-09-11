#!/usr/bin/env python3
"""Probe the production ingestion path, without writing to a database.

python3 tools/probe_event_sources.py --city Київ --source ticketsbox --sample 5
python3 -m tools.probe_event_sources --json /tmp/source-report.json
"""
from __future__ import annotations

import argparse
import collections
import dataclasses
import datetime as dt
import json
from pathlib import Path
import sys

if __package__ in (None, ''):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.ingest.extract import events_from_html as events_in
from tools.ingest.pipeline import harvest
from tools.ingest.normalize import zone
from tools.ingest.sources import by_slug, enabled_sources
from tools.ingest.venues import VenueIndex


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--city', default='Київ')
    ap.add_argument('--source', action='append')
    ap.add_argument('--sample', type=int, default=12, help='maximum detail pages per source')
    ap.add_argument('--json', type=Path)
    args = ap.parse_args(argv)
    if args.sample < 1:
        ap.error('--sample must be positive')
    try:
        sources = [by_slug(s) for s in dict.fromkeys(args.source)] if args.source else enabled_sources()
    except KeyError as exc:
        ap.error(str(exc))
    sources = [s for s in sources if args.city in s.listing_urls]
    if not sources:
        ap.error('No configured sources for this city')
    now = dt.datetime.now(dt.timezone.utc)
    records = []
    for source in sources:
        sampled = dataclasses.replace(source, max_details=args.sample)
        items, counters = harvest(sampled, args.city, VenueIndex([], args.city), now=now)
        record = {'source': source.slug, 'city': args.city, 'checked_at': now.isoformat(),
                  'url': source.listing_urls[args.city], **counters,
                  'future_or_ongoing': len(items),
                  'with_source_coordinates': sum(i.latitude is not None for i in items),
                  'with_declared_end': sum(i.end_declared for i in items),
                  'local_start_hours': dict(collections.Counter(i.starts_at.astimezone(
                      zone(source.time_zone)).hour for i in items))}
        records.append(record)
        print(json.dumps(record, ensure_ascii=False), flush=True)
    if args.json:
        args.json.write_text(json.dumps(records, ensure_ascii=False, indent=2), 'utf-8')
    # A deliberate sample limit is visible in detail_errors; it does not mean source failure.
    return int(any(r.get('error') and r.get('detail_errors') != ['DETAIL_LIMIT'] for r in records))


if __name__ == '__main__':
    raise SystemExit(main())

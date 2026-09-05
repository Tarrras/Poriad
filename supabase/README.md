# Poruch backend

Applied to the explicitly selected hosted project `tzdogzdvctlumsqlqskr` (`EventOrganiztor`) on 2026-09-05. The initial migration was created with the Supabase CLI, applied using the Supabase MCP `apply_migration` operation, then its local timestamp was aligned with the server-returned migration version `20260905101755`.

The public RPC contract matches `../docs/implementation-plan.md`. `events_in_view` returns at most 300 future published events; category, dates and spatial filtering run before this bound. Longitude bounds with west > east cross the antimeridian. Times are `timestamptz`; date filters are `[from,to)`. `my_events` includes organized, joined and saved events, including cancelled history. Guests can read public event details and aggregates but cannot read member identities or mutate data.

All five public tables have RLS and explicit grants. Clients cannot write events or memberships directly. Public mutation RPCs are invokers calling privileged implementations in unexposed `private`. Every mutation derives its user from `auth.uid()`. Search paths are empty and relations fully qualified. Do not add `private` or `gis` to the Data API exposed schemas. `private` schema usage and narrow execute grants are necessary for invoker wrappers and policies, and do not expose REST endpoints.

Joining, leaving, cancellation and editing lock the same event row. Duplicate joins are idempotent, hosts do not consume guest capacity, and capacity cannot be reduced below attendance. Creating uses the client-generated UUID plus a transaction advisory lock so uncertain-response retries return the same event. A retry with an existing UUID returns the original event ID without overwriting its fields; editing is a separate RPC.

The `event-images` public bucket allows JPEG, PNG and WebP up to 5 MiB. Write paths must be `<authenticated-user-id>/<owned-event-id>/<filename>`. Create the event first, upload the image, then update `image_url`. Insert, update/upsert and delete all enforce event ownership. Image reads are public; do not upload private material. Both native clients include system photo-picker upload on an existing owned event; iOS converts to JPEG. Transport and physical-device upload QA remain separate from SQL policy tests.

`profiles` contains only display name/avatar and is populated by an Auth trigger; signup metadata is used only for the display name. `user_preferences` stores private categories and reminder opt-in. Profile email is never copied into public tables. Configure email confirmation and native redirect URLs in Auth before production use; this migration does not change project-wide Auth settings.

## Verification

Executed successfully on the selected project:

- `tests/access_and_transactions.sql`: profile/preferences triggers; idempotent create and join; direct event/member writes denied; owner-only edits/cancellation; saved/profile/preferences/roster isolation; full capacity and capacity reduction; cancelled history and exclusion; idempotent leave; guest mutation rejection; owner image path checks; past time, coordinate, timezone, end time and capacity validation.
- `tests/discovery.sql`: both sides of antimeridian, ordinary bounds, category/date filters, 300-result bound, guest aggregate projection and invalid bounds.
- Both SQL suites use `BEGIN` / `ROLLBACK`, including synthetic Auth users. After tests: **0 events, 0 profiles, 0 synthetic test users** remained.
- Security advisor: **zero findings**. No public SECURITY DEFINER functions.
- Performance advisor: two informational unused-index notices on a fresh empty database (`events_category_starts_idx`, `saved_events_event_idx`). Retained because these support expected category queries and cascading foreign keys. [Advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).
- Live concurrent capacity test: **PASS**. Two parallel database transactions called `join_event` for the last place, with a three-second lock hold. Exactly one succeeded and the other returned `EVENT_FULL`; stored membership count was 1. A single bounded orchestration used `try/finally` cleanup; final checks showed **0 remaining test users and 0 remaining test events**. The earlier isolated setup was rejected by automatic review; the complete cleanup-scoped run was accepted.
- `tests/concurrent_capacity.py`: Python syntax checked; reusable two-connection runner with a `finally` cleanup that verifies deletion. Requires `psycopg[binary]==3.2.9` and `TEST_DATABASE_URL` pointed at an authorized test database. The live run above used the Supabase SQL tool concurrently, not this Python transport.

To repeat SQL tests, execute each whole file as a database administrator through the SQL editor or `psql -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f tests/access_and_transactions.sql`. Do not run partial fixture sections. This test uses database JWT claim emulation to test Postgres authorization; it does not replace device Auth, email callback, upload transport or end-to-end UI tests.

## Errors

Stable message strings: `AUTH_REQUIRED`, `EVENT_NOT_FOUND`, `NOT_ORGANIZER`, `ORGANIZER_CANNOT_JOIN`, `EVENT_FULL`, `EVENT_CANCELLED`, `EVENT_STARTED`, `START_MUST_BE_FUTURE`, `INVALID_TIME_ZONE`, `INVALID_BOUNDS`, `CAPACITY_BELOW_ATTENDANCE`. Constraint violations use standard Postgres SQLSTATEs. UI should translate messages, not expose raw SQL diagnostics.

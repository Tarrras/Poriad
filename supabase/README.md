# Poruch backend

Applied to the explicitly selected hosted project `tzdogzdvctlumsqlqskr` (`EventOrganiztor`) on 2026-09-05. The initial migration was created with the Supabase CLI, applied using the Supabase MCP `apply_migration` operation, then its local timestamp was aligned with the server-returned migration version `20260905101755`.

The public RPC contract matches `../docs/implementation-plan.md`. `events_in_view` returns at most 300 future published events; category, dates and spatial filtering run before this bound. Longitude bounds with west > east cross the antimeridian. Times are `timestamptz`; date filters are `[from,to)`. `my_events` includes organized, joined and saved events, including cancelled history. Guests can read public event details and aggregates but cannot read member identities or mutate data.

All five public tables have RLS and explicit grants. Clients cannot write events or memberships directly. Public mutation RPCs are invokers calling privileged implementations in unexposed `private`. Every mutation derives its user from `auth.uid()`. Search paths are empty and relations fully qualified. Do not add `private` or `gis` to the Data API exposed schemas. `private` schema usage and narrow execute grants are necessary for invoker wrappers and policies, and do not expose REST endpoints.

Joining, leaving, cancellation and editing lock the same event row. Duplicate joins are idempotent, hosts do not consume guest capacity, and capacity cannot be reduced below attendance. Creating uses the client-generated UUID plus a transaction advisory lock so uncertain-response retries return the same event. A retry with an existing UUID returns the original event ID without overwriting its fields; editing is a separate RPC.

The `event-images` public bucket allows JPEG, PNG and WebP up to 5 MiB. Write paths must be `<authenticated-user-id>/<owned-event-id>/<filename>`. Create the event first, upload the image, then update `image_url`. Insert, update/upsert and delete all enforce event ownership. Image reads are public; do not upload private material. Both native clients include system photo-picker upload on an existing owned event; iOS converts to JPEG. Transport and physical-device upload QA remain separate from SQL policy tests.

`profiles` contains only display name/avatar and is populated by an Auth trigger; signup metadata is used only for the display name. `user_preferences` stores private categories and reminder opt-in. Profile email is never copied into public tables. Configure email confirmation and native redirect URLs in Auth before production use; this migration does not change project-wide Auth settings.

## Attendee roster

`migrations/20260905203918_event_attendees.sql` adds `public.attendee_result` and `public.event_attendees(uuid,integer)`, applied to the same hosted project on 2026-09-05 through the Supabase MCP `apply_migration` operation; the local file name carries the server-returned version.

The function is an invoker, so `members_read` on `event_members` and `profiles_read` on `profiles` govern it unchanged: the organizer and confirmed members read identities, a signed-in stranger gets an empty set, and `anon` holds no execute grant. The aggregate `attendee_count` in `event_result` is untouched and stays visible to everyone, so this adds no new exposure of who attends what. `p_limit` is clamped to `[1,100]` rather than trusted. Both clients treat the roster as best-effort: a failure leaves the count-only view instead of an error.

## Waiting list

`migrations/20260905221357_event_waitlist.sql` adds `public.event_waitlist`, the queue RPCs and the promotion helper; `migrations/20260905221547_event_waitlist_grants.sql` adds the execute grants the invoker wrappers need on their private implementations. Both applied on 2026-09-05; local file names carry the server-returned versions.

A full event is no longer a dead end. `join_waitlist` accepts a position only when the event is published, future, and actually full; the organizer and existing members are refused. Positions are private — `waitlist_read` restricts `event_waitlist` to its own holder, and `my_waitlist` returns only the caller's rows, so waiting for an event never becomes a public signal. There is no aggregate queue length in any projection.

Places free up in two ways and both advance the queue inside the transaction that already holds the event row lock: `leave_event` and a capacity increase in `update_event` both call `private.promote_waitlist`, which fills places from the head of the queue by `created_at`. Joining outright drops any position the same person held. `promote_waitlist` carries no execute grant: it is reached only from inside definer functions, which run as the owner.

## Verification

Executed successfully on the selected project:

- `tests/access_and_transactions.sql`: profile/preferences triggers; idempotent create and join; direct event/member writes denied; owner-only edits/cancellation; saved/profile/preferences/roster isolation; full capacity and capacity reduction; cancelled history and exclusion; idempotent leave; guest mutation rejection; owner image path checks; past time, coordinate, timezone, end time and capacity validation.
- `tests/discovery.sql`: both sides of antimeridian, ordinary bounds, category/date filters, 300-result bound, guest aggregate projection and invalid bounds.
- `tests/attendees.sql`: roster readable by a member and by the organizer, ordered by join time; a signed-in stranger reads no identities but still reads `attendee_count`; guests are refused by the missing execute grant; `p_limit` clamped up from `0`, down from `10000`, and defaulted from `null`. Executed on the selected project on 2026-09-05: **PASS**, with 0 events, 0 profiles, 0 members and 0 synthetic test users remaining. Because `now()` is the transaction timestamp, both joins in a single transaction share one `joined_at`; the suite spreads them apart so the ordering guarantee is genuinely exercised rather than decided by the uuid tiebreak.
- `tests/waitlist.sql`: a full event refuses `join_event` with `EVENT_FULL` but accepts a queue position; queueing twice is idempotent; members get `ALREADY_MEMBER` and the organizer `ORGANIZER_CANNOT_JOIN`; positions stay private between two queued accounts; leaving promotes the head of the queue and clears its position while capacity holds; raising capacity promotes the next one; an event with room refuses queueing with `EVENT_HAS_SPACE`; leaving a queue you are not in is a no-op; guests are refused by the missing execute grant. Executed on the selected project on 2026-09-05: **PASS**, 0 rows left behind. As in the roster suite, queue rows created in one transaction share `created_at`, so the suite spreads them apart before asserting promotion order.
- `tests/access_and_transactions.sql` re-run after the waiting list replaced `join_event`, `leave_event` and `update_event`: **PASS**, no regression.
- The `my_waitlist` response shape was confirmed over PostgREST — a scalar `setof uuid` returns a flat JSON array of strings, which is what the client parses.
- Advisors after this migration: security **zero findings**; performance one informational unused-index notice on the empty database (`events_category_starts_idx`), retained for the same reason as before.
- All SQL suites use `BEGIN` / `ROLLBACK`, including synthetic Auth users. After tests: **0 events, 0 profiles, 0 synthetic test users** remained.
- Security advisor: **zero findings**. No public SECURITY DEFINER functions.
- Performance advisor: two informational unused-index notices on a fresh empty database (`events_category_starts_idx`, `saved_events_event_idx`). Retained because these support expected category queries and cascading foreign keys. [Advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).
- Live concurrent capacity test: **PASS**. Two parallel database transactions called `join_event` for the last place, with a three-second lock hold. Exactly one succeeded and the other returned `EVENT_FULL`; stored membership count was 1. A single bounded orchestration used `try/finally` cleanup; final checks showed **0 remaining test users and 0 remaining test events**. The earlier isolated setup was rejected by automatic review; the complete cleanup-scoped run was accepted.
- `tests/concurrent_capacity.py`: Python syntax checked; reusable two-connection runner with a `finally` cleanup that verifies deletion. Requires `psycopg[binary]==3.2.9` and `TEST_DATABASE_URL` pointed at an authorized test database. The live run above used the Supabase SQL tool concurrently, not this Python transport.

To repeat SQL tests, execute each whole file as a database administrator through the SQL editor or `psql -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f tests/access_and_transactions.sql`. Do not run partial fixture sections. This test uses database JWT claim emulation to test Postgres authorization; it does not replace device Auth, email callback, upload transport or end-to-end UI tests.

## Errors

Stable message strings: `AUTH_REQUIRED`, `EVENT_NOT_FOUND`, `NOT_ORGANIZER`, `ORGANIZER_CANNOT_JOIN`, `EVENT_FULL`, `EVENT_HAS_SPACE`, `ALREADY_MEMBER`, `EVENT_CANCELLED`, `EVENT_STARTED`, `START_MUST_BE_FUTURE`, `INVALID_TIME_ZONE`, `INVALID_BOUNDS`, `CAPACITY_BELOW_ATTENDANCE`. Constraint violations use standard Postgres SQLSTATEs. UI should translate messages, not expose raw SQL diagnostics.

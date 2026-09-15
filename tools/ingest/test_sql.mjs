// node tools/ingest/test_sql.mjs /absolute/path/to/@electric-sql/pglite/dist/index.js [live.sql ...]
// Temporary PostgreSQL only. The reduced schema mirrors ingestion columns/constraints;
// application RLS, auth and PostGIS are outside this test.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';

const { PGlite } = await import(pathToFileURL(process.argv[2]));
const db = new PGlite();
const fixture = JSON.parse(execFileSync('python3', ['-m', 'tools.ingest.sql_test_fixture'], { encoding: 'utf8' }));
await db.exec(`
create table event_sources (
 id uuid primary key default gen_random_uuid(), slug text unique not null, name text,
 kind text, base_url text, listing_urls text[], weight numeric, crawl_delay_seconds int,
 tz_policy text, default_time_zone text, enabled boolean, organizer_id uuid
);
create table events (
 id uuid primary key, organizer_id uuid, title text not null check(length(title) between 3 and 120),
 description text, category text, city text, address text, latitude double precision,
 longitude double precision, starts_at timestamptz not null, ends_at timestamptz not null,
 time_zone text, capacity int, image_url text, origin text, source_id uuid references event_sources(id),
 source_uid text, canonical_url text, dedupe_key text, quality numeric,
 import_status text check(import_status in ('live','stale','withdrawn')),
 price_min numeric check(price_min >= 0), is_free boolean, ingest_run_id uuid,
 updated_at timestamptz default now(), check(ends_at > starts_at)
);
create unique index events_source_uid_uidx on events(source_id,source_uid) where source_id is not null;
create table venues (
 norm_name text, norm_address text, display_name text, latitude double precision,
 longitude double precision, city text, source text, osm_ref text, confidence numeric,
 unique(norm_name,norm_address)
);`);
await db.exec(fixture.sources);
const legacyId = '11111111-1111-1111-1111-111111111111';
await db.exec(`insert into events(id,title,starts_at,ends_at,source_id,source_uid,canonical_url,origin,import_status)
 values('${legacyId}','Тестовий концерт','2026-10-17T18:00:00+03:00','2026-10-17T21:00:00+03:00',
 (select id from event_sources where slug='concert_ua'),'https://example.org/event','https://example.org/event','import','live');`);
await db.exec(fixture.insert);
await db.exec(fixture.insert);
assert.equal((await db.query('select * from events')).rows.length, 2);
assert.equal((await db.query('select id from events where source_uid=$1', [fixture.uids[0]])).rows[0].id, legacyId);
await db.exec(fixture.cancel);
assert.deepEqual((await db.query('select import_status from events order by starts_at')).rows.map(r => r.import_status), ['withdrawn', 'live']);
const secondId = (await db.query('select id from events where source_uid=$1', [fixture.uids[1]])).rows[0].id;
await db.exec(fixture.move);
await db.exec(fixture.move);
assert.equal((await db.query('select * from events')).rows.length, 2);
assert.equal((await db.query('select id from events where source_uid=$1', [fixture.uids[2]])).rows[0].id, secondId);
await db.exec(`insert into events(id,title,starts_at,ends_at,source_id,source_uid,canonical_url,origin,import_status)
 values('22222222-2222-2222-2222-222222222222','Тестовий концерт','2026-10-17T18:00:00+03:00','2026-10-17T21:00:00+03:00',
 (select id from event_sources where slug='internet_bilet'),'https://example.org/event','https://example.org/event','import','live');`);
await db.exec(fixture.duplicate);
assert.equal((await db.query("select import_status from events where id='22222222-2222-2222-2222-222222222222'")).rows[0].import_status, 'withdrawn');
// ── Зміна посилання не відриває збережене: той самий сеанс під новою адресою — той самий рядок.
const statusOf = async (uid) => (await db.query('select import_status from events where source_uid=$1', [uid])).rows[0]?.import_status;
await db.exec(fixture.move_before);
const movedRowId = (await db.query('select id from events where source_uid=$1', [fixture.move_uids[0]])).rows[0].id;
await db.exec(fixture.move_after);
await db.exec(fixture.move_after);
const movedRows = (await db.query('select id, source_uid, canonical_url from events where id=$1', [movedRowId])).rows;
assert.equal(movedRows.length, 1);
assert.equal(movedRows[0].source_uid, fixture.move_uids[1]);
assert.equal(movedRows[0].canonical_url, 'https://example.org/teatr-3');
assert.equal((await db.query('select count(*)::int as n from events where source_uid=$1', [fixture.move_uids[0]])).rows[0].n, 0);
// Інша назва в ту саму хвилину на тій самій точці — окрема подія, а не переїзд.
await db.exec(fixture.move_other);
assert.equal((await db.query('select count(*)::int as n from events where source_uid=$1', [fixture.move_uids[2]])).rows[0].n, 1);
// Зняття після вставок не чіпає переїхалий рядок: під новим ключем він «бачений».
await db.exec(fixture.retire_after_move);
assert.equal(await statusOf(fixture.move_uids[1]), 'live');
assert.equal(await statusOf(fixture.move_uids[2]), 'live');

// ── Зникнення з афіші — скасування, але лише в межах джерела, міста й майбутнього.
const insertKarabas = async (uid, city, starts, ends) => db.exec(`insert into events(id,title,city,starts_at,ends_at,source_id,source_uid,canonical_url,origin,import_status)
 values(gen_random_uuid(),'Подія для зняття','${city}','${starts}','${ends}',(select id from event_sources where slug='karabas'),'${uid}','${uid}','import','live');`);
for (const uid of fixture.karabas_uids) await insertKarabas(uid, 'Київ', '2026-11-01T19:00:00+02:00', '2026-11-01T21:00:00+02:00');
await insertKarabas('https://example.org/k-past', 'Київ', '2026-09-01T19:00:00+03:00', '2026-09-01T21:00:00+03:00');
await insertKarabas('https://example.org/k-lviv', 'Львів', '2026-11-01T19:00:00+02:00', '2026-11-01T21:00:00+02:00');
await db.exec(fixture.retire_one);
assert.equal(await statusOf(fixture.karabas_uids[9]), 'withdrawn');
for (const uid of fixture.karabas_uids.slice(0, 9)) assert.equal(await statusOf(uid), 'live');
assert.equal(await statusOf('https://example.org/k-past'), 'live');
assert.equal(await statusOf('https://example.org/k-lviv'), 'live');
// Зламаний обхід, що «бачив» одну подію з девʼяти, не знімає нічого: частка понад запобіжник.
await db.exec(fixture.retire_mass);
for (const uid of fixture.karabas_uids.slice(0, 9)) assert.equal(await statusOf(uid), 'live');
console.log('PostgreSQL: moved URL keeps row id, retire scoped to source/city/future, mass retire blocked OK');

for (const path of process.argv.slice(3)) {
 const sql = readFileSync(path, 'utf8');
 await db.exec(sql);
 const before = (await db.query('select count(*)::int as n from events')).rows[0].n;
 await db.exec(sql);
 assert.equal((await db.query('select count(*)::int as n from events')).rows[0].n, before);
 console.log(`Live SQL replay OK: ${path} (${before} total rows)`);
}
console.log('PostgreSQL: sessions, legacy ID preservation, cancellation, reschedule and replay OK');
await db.close();

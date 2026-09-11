"""Two real DB connections compete for one place. Requires psycopg[binary]==3.2.9.
Run ONLY against an authorized test database with the migration applied:
  TEST_DATABASE_URL='postgresql://...' python3 concurrent_capacity.py
Creates synthetic fixtures; finally deletes those exact auth IDs (cascading all data).
"""
import os
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
import psycopg


def main():
    url = os.environ['TEST_DATABASE_URL']
    host, guest_b, guest_c, event = [uuid.uuid4() for _ in range(4)]
    fixtures = (host, guest_b, guest_c)
    locked = threading.Event()
    contender_started = threading.Event()

    def join(user, first):
        try:
            with psycopg.connect(url, connect_timeout=10) as conn:
                conn.execute("set local statement_timeout = '10s'")
                conn.execute("set local role authenticated")
                conn.execute("select set_config('request.jwt.claim.sub',%s,true)", (str(user),))
                if first:
                    conn.execute('select public.join_event(%s)', (event,))
                    locked.set()
                    if not contender_started.wait(5):
                        raise RuntimeError('Second connection did not start')
                    # Keep the row lock so the contender genuinely overlaps this transaction.
                    time.sleep(1)
                else:
                    if not locked.wait(5):
                        raise RuntimeError('First connection did not acquire the lock')
                    contender_started.set()
                    conn.execute('select public.join_event(%s)', (event,))
            return 'joined'
        except psycopg.Error as exc:
            if exc.sqlstate == 'P0001' and exc.diag.message_primary == 'EVENT_FULL':
                return 'full'
            raise

    try:
        with psycopg.connect(url, connect_timeout=10) as conn:
            for user in fixtures:
                # Joining refuses an account that never declared an age, so the fixtures state one.
                conn.execute(
                    'insert into auth.users(id,email,raw_user_meta_data) values(%s,%s,%s)',
                    (user, f'poruch-race-{user}@example.invalid', '{"birth_date": "1990-01-01"}'))
            conn.execute("""insert into public.events
                (id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity)
                values(%s,%s,'Capacity test','','social','Kyiv','Park',50,30,
                now()+interval '1 day',now()+interval '2 days','Europe/Kyiv',1)""", (event, host))
        with ThreadPoolExecutor(max_workers=2) as pool:
            a = pool.submit(join, guest_b, True)
            b = pool.submit(join, guest_c, False)
            results = sorted([a.result(), b.result()])
        assert results == ['full', 'joined'], results
        with psycopg.connect(url, connect_timeout=10) as conn:
            count = conn.execute('select count(*) from public.event_members where event_id=%s', (event,)).fetchone()[0]
            assert count == 1, count
        print('PASS: two overlapping transactions; one joined, one EVENT_FULL; one stored membership')
    finally:
        with psycopg.connect(url, connect_timeout=10) as conn:
            conn.execute('delete from auth.users where id = any(%s)', (list(fixtures),))
            assert conn.execute('select count(*) from auth.users where id = any(%s)', (list(fixtures),)).fetchone()[0] == 0
            assert conn.execute('select count(*) from public.events where id=%s', (event,)).fetchone()[0] == 0
        print('Cleanup verified')


if __name__ == '__main__':
    main()

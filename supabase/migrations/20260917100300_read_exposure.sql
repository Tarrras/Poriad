-- Аудит 2026-09-16, V1/V4/V5: що читалось напряму через REST поза проєкціями.
-- V1: contact_url і службові колонки events були доступні anon через GET /rest/v1/events.
--     Клієнти ходять лише через RPC; проєкції (event_rows, event_cards, discover_index) — definer,
--     тож звужуємо табличний грант до колонок, які потрібні invoker-функціям і політикам.
revoke select on public.events from anon, authenticated;
grant select (id, organizer_id, title, description, category, city, address, latitude, longitude,
 starts_at, ends_at, time_zone, capacity, status, image_url, created_at, updated_at,
 min_age, max_age, approval_required, origin, source_id, canonical_url, import_status, price_min, is_free,
 -- events_in_view / search_events_in_view — invoker і фільтрують по location та quality.
 location, quality)
 on public.events to anon, authenticated;

-- V5: гість перелічував усіх користувачів. Імена організаторів гостю віддають definer-проєкції.
revoke select on public.profiles from anon;
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (true);

-- V4: підтверджений учасник бачив, хто лише подав запит. Запити — організатору й самому прохачу.
drop policy if exists members_read on public.event_members;
create policy members_read on public.event_members for select to authenticated using (
 user_id = (select auth.uid())
 or exists(select 1 from public.events e where e.id=event_id and e.organizer_id=(select auth.uid()))
 or (status='approved' and private.can_view_members(event_id))
);

-- event_sources: картці потрібні лише назва й адреса, не etag/listing_urls/crawl_delay.
revoke select on public.event_sources from anon, authenticated;
grant select (id, slug, name, base_url) on public.event_sources to anon, authenticated;

-- Зайві execute на private-помічниках: їх кличуть лише definer-функції.
revoke execute on function private.age_of(uuid), private.assert_age_limits(integer,integer),
 private.assert_event_editable(public.events), private.assert_contact_url(text), private.assert_can_join(uuid,public.events)
 from authenticated;

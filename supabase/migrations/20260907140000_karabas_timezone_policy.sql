-- karabas.com зсуває момент на UTC-зсув: сторінка каже 18:00, JSON-LD — 21:00+03:00. Правило:
-- UTC-момент karabas дорівнює правильному локальному часу. Виявлено дедуплікацією з concert.ua.

alter table public.event_sources drop constraint event_sources_tz_policy_check;
alter table public.event_sources add constraint event_sources_tz_policy_check
 check (tz_policy in ('source','force_local','utc_is_local'));

update public.event_sources set tz_policy='utc_is_local' where slug='karabas';

-- Завантажені події зсуваємо назад: стінний час за UTC читаємо як київський, як робить конвеєр.
update public.events e
set starts_at = (e.starts_at at time zone 'UTC') at time zone 'Europe/Kyiv',
    ends_at   = (e.ends_at   at time zone 'UTC') at time zone 'Europe/Kyiv',
    dedupe_key = to_char(((e.starts_at at time zone 'UTC') at time zone 'Europe/Kyiv')
                          at time zone 'Europe/Kyiv', 'YYYY-MM-DD')
                 || ':' || round(e.latitude::numeric, 2) || ',' || round(e.longitude::numeric, 2),
    updated_at = now()
from public.event_sources s
where s.id = e.source_id and s.slug = 'karabas' and e.origin = 'import';

-- karabas.com зсуває час рівно на UTC-зсув, і робить це непомітно.
--
-- Джерело віддає коректний зсув, ба навіть із переходом на зимовий час, тому розмітка виглядає
-- бездоганно. Але сам момент зсунуто вперед: сторінка показує «17 жовтня 2026, 18:00», а її ж
-- JSON-LD каже 2026-10-17T21:00:00+03:00. Правило, перевірене на 10 сторінках із 10:
-- UTC-момент karabas дорівнює правильному локальному часу.
--
-- Виявлено дедуплікацією: та сама подія з concert.ua і karabas розходилась рівно на зсув.
-- Це аргумент за те, щоб дублікати між джерелами не приховувати, а дивитись на них.

alter table public.event_sources drop constraint event_sources_tz_policy_check;
alter table public.event_sources add constraint event_sources_tz_policy_check
 check (tz_policy in ('source','force_local','utc_is_local'));

update public.event_sources set tz_policy='utc_is_local' where slug='karabas';

-- Уже завантажені події зсуваємо назад: беремо цифри стінного годинника за UTC і читаємо їх
-- як київський час. Це та сама операція, що робить конвеєр, тільки в SQL.
update public.events e
set starts_at = (e.starts_at at time zone 'UTC') at time zone 'Europe/Kyiv',
    ends_at   = (e.ends_at   at time zone 'UTC') at time zone 'Europe/Kyiv',
    dedupe_key = to_char(((e.starts_at at time zone 'UTC') at time zone 'Europe/Kyiv')
                          at time zone 'Europe/Kyiv', 'YYYY-MM-DD')
                 || ':' || round(e.latitude::numeric, 2) || ',' || round(e.longitude::numeric, 2),
    updated_at = now()
from public.event_sources s
where s.id = e.source_id and s.slug = 'karabas' and e.origin = 'import';

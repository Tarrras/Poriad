-- Джерело internet-bilet.ua.
--
-- У документах домен був записаний як «internetbilet.ua» — він не резолвиться, тож джерело роками
-- лишалось поза полем зору. Справжній домен має дефіс. Виміряно 2026-09-10:
--
--   270 подій за ОДИН запит на kyiv.internet-bilet.ua/uk;
--   endDate / offers / image / streetAddress / location.name — по 100%;
--   244 із 270 (90%) відсутні і в karabas, і в concert.ua;
--   33 ComedyEvent — саме той сольний стендап, якого не було на жодному наявному джерелі.
--
-- Час чесний: зсуви DST-коректні, і JSON-LD звірено з часом на самій сторінці — 8 із 8 збіглись.
-- Тому tz_policy='source', а не пастка utc_is_local, як у karabas.
--
-- Вага 0.75 — вище за karabas (0.7, доведена вада часу), нижче за concert.ua (0.8). На поріг
-- якості вага тут майже не впливає; вона вирішує, чия копія лишається канонічною при злитті
-- дублікатів. Тримати нижче за найдовіреніше джерело навмисно: прихована вада тоді проявиться
-- як видимий дубль, а не як тиха заміна добрих даних.
--
-- Це перша міграція, що заводить рядок у public.event_sources. Три наявні джерела створені поза
-- версіонуванням; без рядка тут emit.events_sql віддає source_id = NULL і вся вставка падає на
-- events_origin_source_ck.

insert into public.event_sources
 (slug, name, kind, base_url, listing_urls, city, weight, crawl_delay_seconds,
  tz_policy, default_time_zone, licence, enabled)
values
 ('internet_bilet', 'Internet-Bilet', 'listing_jsonld', 'https://internet-bilet.ua',
  array[
    'https://kyiv.internet-bilet.ua/uk',
    'https://lviv.internet-bilet.ua/uk',
    'https://kharkiv.internet-bilet.ua/uk',
    'https://odesa.internet-bilet.ua/uk',
    'https://dnipro.internet-bilet.ua/uk'
  ],
  'Київ', 0.75, 2, 'source', 'Europe/Kyiv', 'jsonld_public', true)
on conflict (slug) do update set
 name = excluded.name,
 kind = excluded.kind,
 base_url = excluded.base_url,
 listing_urls = excluded.listing_urls,
 weight = excluded.weight,
 crawl_delay_seconds = excluded.crawl_delay_seconds,
 tz_policy = excluded.tz_policy,
 licence = excluded.licence,
 enabled = excluded.enabled;

-- Наявні три джерела теж обходять по пʼятьох містах — доповнюємо їхні listing_urls, щоб рядок у
-- базі не розходився з tools/ingest/sources.py.
update public.event_sources set listing_urls = array[
  'https://kyiv.karabas.com/', 'https://lviv.karabas.com/', 'https://kharkiv.karabas.com/',
  'https://odesa.karabas.com/', 'https://dnipro.karabas.com/'] where slug = 'karabas';

update public.event_sources set listing_urls = array[
  'https://concert.ua/uk/kyiv', 'https://concert.ua/uk/lviv', 'https://concert.ua/uk/kharkiv',
  'https://concert.ua/uk/odesa', 'https://concert.ua/uk/dnipro'] where slug = 'concert_ua';

-- Джерело internet-bilet.ua (з дефісом; «internetbilet.ua» не резолвиться). 270 подій за один
-- запит, 90% відсутні в інших джерелах, повні поля. Час чесний, тому tz_policy='source'.
-- Вага 0.75: вище за karabas, нижче за concert.ua, щоб прихована вада проявилась дублем, а не
-- тихою заміною. Перша міграція з рядком у event_sources: без нього вставка падає на events_origin_source_ck.

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

-- listing_urls наявних джерел доповнюємо, щоб база не розходилась з tools/ingest/sources.py.
update public.event_sources set listing_urls = array[
  'https://kyiv.karabas.com/', 'https://lviv.karabas.com/', 'https://kharkiv.karabas.com/',
  'https://odesa.karabas.com/', 'https://dnipro.karabas.com/'] where slug = 'karabas';

update public.event_sources set listing_urls = array[
  'https://concert.ua/uk/kyiv', 'https://concert.ua/uk/lviv', 'https://concert.ua/uk/kharkiv',
  'https://concert.ua/uk/odesa', 'https://concert.ua/uk/dnipro'] where slug = 'concert_ua';

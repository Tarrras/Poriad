-- Лише читання. «Артисти», де весь склад записано одним рядком капсом без розділювачів:
-- «АРСЕН ПУЧКОВ МАКС РЕДЗЕЛЬ ДМИТРО ТАРАБАКІН ВІТАЛІЙ ШИНДЕРОВСЬКИЙ» (Badseller `performer`).
-- Той самий вираз, що `artists._CAPS_LINEUP`: від чотирьох слів лише з великих літер. Імена, відомі
-- цілими в `artists.json` (шоу-бренд «CARIBBEAN CLUB DISCO PARTY»), правило не ділить, а запит показує.
select a.name, a.source, count(ea.event_id) as events
from public.artists a
left join public.event_artists ea on ea.artist_id = a.id
where a.name ~ '^[A-ZА-ЯІЇЄҐ''’ʼ-]+(\s+[A-ZА-ЯІЇЄҐ''’ʼ-]+){3,}$'
group by a.id, a.name, a.source
order by events desc, a.name;

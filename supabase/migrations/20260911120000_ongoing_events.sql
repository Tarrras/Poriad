-- Подія, що вже почалась, але ще не скінчилась.
--
-- Конвеєр давно імпортує виставки, ярмарки й фестивальні програми, але показати їх не було кому:
-- і `private.discover_index`, і `public.search_events_in_view` відсікали подію за часом **початку**
-- (`e.starts_at > now()`). На обході пʼяти міст під цю умову потрапляли 62 події, яких застосунок
-- не показував жодного дня їхнього прокату.
--
-- Заміна умови на `ends_at` безпечна лише після того, як у базі не лишиться записів із вигаданим
-- кінцем, — тому спершу знімаємо з публікації постійні пропозиції, а вже потім міняємо умову.
-- Межа прокату відтепер стоїть в `tools/ingest/pipeline.py` (`PERMANENT_RUN`), тобто при імпорті,
-- а не при показі: фільтр ховає рядок, але рядок лишається й спливає в кожному новому запиті.
--
-- Чого ця міграція НЕ чіпає:
--   `p_from`/`p_to` лишаються на `starts_at`. «На вихідних» — це питання про те, що **почнеться**
--   на вихідних, а не про те, що тоді триватиме. Різні питання, один параметр їх не вміщає.
--
--   `public.events_in_view` лишається на `starts_at`: жоден клієнт її не викликає (карта ходить у
--   `discover_events`, запасний шлях — у `search_events_in_view`), і міняти умову в функції, якої
--   ніхто не питає, означало б додати третє місце, де ця умова написана.

-- ------------------------------------------------------------------ 1. постійні пропозиції геть
--
-- Десять таких рядків уже завезено: «Київський океанаріум», «Музей медуз», VR-екскурсія,
-- майстер-клас із кінцем через 560 днів. У них `endDate` — не кінець події, а дата, доки діє
-- квиткова пропозиція. Після зміни умови нижче вони висіли б у стрічці як «триває зараз»
-- місяцями.
--
-- `withdrawn`, а не `delete`: якщо хтось уже зберіг океанаріум, порожній запис гірший за позначку
-- (та сама причина, що в `private.is_discoverable` — відкликана подія лишається доступною тому,
-- хто її зберіг). Межа тут повторює `tools/ingest/pipeline.py`: 90 днів.
update public.events set import_status='withdrawn', updated_at=now()
where origin='import' and import_status='live' and ends_at - starts_at > interval '90 days';

-- ------------------------------------------------------------------ 2. умова й порядок в індексі
--
-- Дві зміни в одному тілі, і друга без першої ламає стрічку. Умова `ends_at > now()` впускає
-- виставку, що почалась 38 днів тому, а `order by starts_at` розставляє все, що вже йде, за тим,
-- хто почався давніше: найдовший прокат опиняється першим і лишається там до кінця.
-- `greatest(starts_at, now())` згортає те, що вже йде, в одну точку «зараз» і далі розрізняє за
-- `id`; майбутнє лишається в порядку початку.
--
-- Чого це НЕ робить, і це варто сказати прямо: те, що йде зараз, і далі стоїть попереду того, що
-- почнеться завтра, — це і є «цікаво зараз». Змінюється лише те, що перше місце в цій групі
-- більше не дістається найдовшому прокату за вислугою років.
--
-- Решта тіла — слово в слово з 20260911070031: сигнатура та сама, тож це заміна тіла, і жоден
-- грант не губиться дорогою.
create or replace function private.discover_index(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text, p_from timestamptz, p_to timestamptz, p_text text, p_available boolean,
 p_limit integer, p_cards integer)
returns table(index jsonb, total integer, truncated boolean, card_ids uuid[])
-- Без `plan_cache_mode='force_custom_plan'`, як і в 20260911070031: узагальнений план бере
-- gist-індекс і без нього, а планування цього запиту коштує ~65 мс.
language sql stable security definer set search_path='' as $$
 with matched as (
  select e.id, e.starts_at, e.latitude, e.longitude, e.category, e.time_zone, e.title,
         e.origin, e.capacity, e.source_id
  from public.events e
  where e.status='published' and e.ends_at > now()
    and private.is_discoverable(e.origin, e.import_status, e.quality)
    and (nullif(btrim(p_text),'') is null
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), lower(btrim(p_text))) > 0)
    -- `case` замість `and`: порядок обчислення в кон'юнкції не гарантований, а нам потрібно, щоб
    -- перевірка колонки стояла перед викликом функції.
    and (not coalesce(p_available,false)
         or case when e.capacity is null then false else private.event_has_space(e.id) end)
    and (p_category is null or e.category = p_category)
    and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
    and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
      or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
       or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326)))))
 , ranked as (
  select m.*, row_number() over (order by greatest(m.starts_at, now()), m.id) as rank,
         count(*) over () as total
  from matched m
 )
 , page as (select r.* from ranked r where r.rank <= p_limit)
 select
  coalesce((select jsonb_agg(jsonb_build_array(
     p.id, p.latitude, p.longitude, p.category, p.starts_at, p.time_zone, p.title, p.origin,
     s.slug,
     p.capacity,
     case when p.origin='community' then
       (select count(*)::integer from public.event_members mm where mm.event_id=p.id and mm.status='approved')
     else 0 end
   ) order by p.rank) from page p left join public.event_sources s on s.id=p.source_id), '[]'::jsonb),
  coalesce((select max(r.total)::integer from ranked r), 0),
  coalesce((select max(r.total) from ranked r), 0) > p_limit,
  coalesce((select array_agg(p.id order by p.rank) from page p where p.rank <= p_cards), '{}'::uuid[]);
$$;

-- ------------------------------------------------------------------ 3. те саме в запасному шляху
--
-- Збірки, які ще не знають про `discover_events`, ходять сюди. Умова й порядок мають збігатись з
-- індексом, інакше та сама область показувала б різне залежно від версії застосунку. Порядок тут
-- у двох місцях — у підзапиті з `limit 300` і в зовнішньому `order by`; загубити друге найлегше,
-- і саме воно вирішує, що людина побачить першим.
create or replace function public.search_events_in_view(p_south double precision,p_west double precision,p_north double precision,p_east double precision,p_category text default null,p_from timestamptz default null,p_to timestamptz default null,p_text text default null,p_available boolean default false)
 returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text)>120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and e.ends_at > now()
 and private.is_discoverable(e.origin,e.import_status,e.quality)
 and (nullif(btrim(p_text),'') is null or strpos(lower(concat_ws(' ',e.title,e.description,e.city,e.address)),lower(btrim(p_text)))>0)
 and (not coalesce(p_available,false) or case when e.capacity is null then false else private.event_has_space(e.id) end)
 and (p_category is null or e.category=p_category)
 and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
 and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
 or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
 or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326))))
 order by greatest(e.starts_at,now()),e.id limit 300)) r order by greatest(r.starts_at,now()),r.id;
end $$;

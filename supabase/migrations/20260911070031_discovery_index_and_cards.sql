-- Видача мапи двома рівнями: повний тонкий індекс і картки вікном.
--
-- Що це лікує. `search_events_in_view` бере `order by starts_at limit 300` і віддає всі двадцять
-- вісім полів композиту на кожен рядок. У Києві це означає дві речі одночасно: 163 події просто
-- не існує для застосунку, а ті 300, що існують, важать 306 КБ і будуються 95 мс. Обидва числа —
-- наслідок одного рішення: одна відповідь несе і те, чим мапа ставить пін, і те, чим картка малює
-- обкладинку.
--
-- Розділяємо ці два питання, і стеля стає непотрібною:
--
--   індекс  — усі 433 київські події, 66 КБ, 6.5 мс. Досить, щоб поставити кожен пін,
--             відранжувати за смаком **увесь** набір, склеїти дублікати й назвати чесне число.
--   картки  — те, чим подія виглядає як подія: адреса, обкладинка, ціна, джерело. Пачкою за
--             списком ідентифікаторів, бо порядок показу вирішує клієнт, а не сервер.
--
-- Композит `public.event_result` не чіпаємо: нові функції повертають `jsonb`, тож нічого не
-- скидається й не відтворюється, і жоден із п'яти залежних грантів не губиться дорогою
-- (supabase/README.md, «це єдиний чесний спосіб змінити тип»). Усе, що тут змінює наявне, —
-- `create or replace` з тією самою сигнатурою.

-- ------------------------------------------------------------------ 1. дешева перевірка місць
--
-- `p_available` коштував 470 мс, щоб віддати дві події: `event_has_space` викликався на кожного з
-- 463 кандидатів, а всередині ще `has_event_access` і `count(*)` по учасниках. Місткість при цьому
-- заповнена рівно у 2 подій з 1256 — у афіші кімнати немає.
--
-- Семантика не змінюється: при `capacity is null` порівняння й так давало null, тобто «ні».
-- Змінюється те, що тепер це видно до виклику, а не після.
create or replace function private.event_has_space(p_event_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.events e
   where e.id=p_event_id and e.capacity is not null
   and private.has_event_access(e.id)
   and (select count(*) from public.event_members m where m.event_id=e.id and m.status='approved') < e.capacity);
$$;

-- ------------------------------------------------------------------ 2. індекс
--
-- Definer тут не зручність, а суть. Набір обмежений `status='published'`, а
-- `private.has_event_access` для опублікованої події повертає true беззастережно
-- (20260905101755). Тобто на цьому шляху RLS нічого не вирішує — лише виконується, 433 рази на
-- запит. Прибираємо виконання, не прибираючи правило.
--
-- Блокування й неактивні акаунти перевіряємо **тут теж**, і не заради безпеки (її тримає проєкція
-- карток), а заради чесності лічильника: інакше «знайдено 433» рахувало б події, яких цей читач
-- не побачить, і вікно карток поверталося б коротшим за обіцяне.
--
-- Масив масивів, а не масив об'єктів: у відповіді на сотні рядків основною вагою були не
-- значення, а двадцять вісім разів повторені назви полів.
create or replace function private.discover_index(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text, p_from timestamptz, p_to timestamptz, p_text text, p_available boolean,
 p_limit integer, p_cards integer)
returns table(index jsonb, total integer, truncated boolean, card_ids uuid[])
-- Без `plan_cache_mode='force_custom_plan'`, хоч спокуса була: межі приходять параметрами, і
-- здавалося, що узагальнений план не зможе взяти gist-індекс. Виміряно — може. А ось планування
-- цього запиту коштує ~65 мс (PostGIS-оператори й схема `gis`), тож примусове перепланування на
-- кожен виклик перетворювало 11 мс на 45. Перший виклик у з'єднанні платить, решта — ні.
language sql stable security definer set search_path='' as $$
 with matched as (
  select e.id, e.starts_at, e.latitude, e.longitude, e.category, e.time_zone, e.title,
         e.origin, e.capacity, e.source_id
  from public.events e
  where e.status='published' and e.starts_at > now()
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
  -- `count(*) over ()` дає повне число тим самим проходом вікна, яким нумеруються рядки. Спершу
  -- тут стояли окремі `count(*) from matched` і `limit` — і `matched` доводилось матеріалізувати
  -- й перечитувати тричі: 45 мс замість 15.
  select m.*, row_number() over (order by m.starts_at, m.id) as rank, count(*) over () as total
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
revoke all on function private.discover_index(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer) from public,anon,authenticated;
grant execute on function private.discover_index(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer) to anon,authenticated;

-- ------------------------------------------------------------------ 3. картки
--
-- Ті самі перевірки доступу, що й у `private.event_rows`, слово в слово: це не швидший шлях повз
-- права, це той самий шлях без полів, яких мапа не малює.
--
-- `jsonb_strip_nulls` прибирає те, чого в події цього роду не існує взагалі: у афіші немає
-- місткості й членства, у кімнати немає джерела й ціни квитка. На 1254 афішах з 1256 подій це
-- знімає по вісім ключів з рядка. Клієнт це переживає без жодної правки: у `EventDto` кожне таке
-- поле має значення за замовчуванням, а розбір іде з `ignoreUnknownKeys`.
create or replace function private.event_cards(p_ids uuid[]) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(card order by starts_at, id), '[]'::jsonb) from (
  select e.starts_at, e.id, jsonb_strip_nulls(jsonb_build_object(
    'id', e.id, 'title', e.title, 'description', nullif(e.description,''), 'category', e.category,
    'city', e.city, 'address', e.address,
    'starts_at', e.starts_at, 'ends_at', e.ends_at, 'time_zone', e.time_zone, 'status', e.status,
    'latitude', e.latitude, 'longitude', e.longitude, 'image_url', e.image_url,
    'organizer_id', e.organizer_id, 'organizer_name', coalesce(p.display_name, s.name),
    'capacity', e.capacity,
    'attendee_count', case when e.origin='community' then
      (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved') end,
    'joined', case when e.origin='community' and auth.uid() is not null then
      exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved') end,
    'membership', case when e.origin='community' and auth.uid() is not null then
      (select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()) end,
    'min_age', nullif(e.min_age, private.min_signup_age()), 'max_age', e.max_age,
    'approval_required', case when e.approval_required then true end,
    'origin', e.origin, 'source_name', s.name, 'canonical_url', e.canonical_url,
    'import_status', e.import_status, 'price_min', e.price_min, 'is_free', e.is_free)) as card
  from public.events e
  left join public.profiles p on p.id = e.organizer_id
  left join public.event_sources s on s.id = e.source_id
  where e.id = any(p_ids) and private.has_event_access(e.id)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
 ) t;
$$;
revoke all on function private.event_cards(uuid[]) from public,anon,authenticated;
grant execute on function private.event_cards(uuid[]) to anon,authenticated;

-- ------------------------------------------------------------------ 4. публічні входи
--
-- Один round-trip на перший екран: індекс і перші картки їдуть разом. Гість із порожніми
-- відповідями (найчастіший випадок) більше нічого не питає взагалі; той, хто пройшов онбординг,
-- дозапитує рівно одне вікно — і то поки мапа вже малюється.
create or replace function public.discover_events(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text default null, p_from timestamptz default null, p_to timestamptz default null,
 p_text text default null, p_available boolean default false,
 p_limit integer default 5000, p_cards integer default 24)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v record; v_limit integer; v_cards integer;
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90
         and p_west between -180 and 180 and p_east between -180 and 180) then
  raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 -- Запобіжник, а не стеля: на місті він не спрацьовує ніколи, але не дає одному запиту вивезти
 -- країну, якщо мапу віддалити до глобуса.
 v_limit := least(greatest(coalesce(p_limit,5000), 1), 5000);
 v_cards := least(greatest(coalesce(p_cards,24), 0), 100);
 select * into v from private.discover_index(
   p_south, p_west, p_north, p_east, p_category, p_from, p_to, p_text, p_available, v_limit, v_cards);
 return jsonb_build_object(
   'total', coalesce(v.total, 0),
   'truncated', coalesce(v.truncated, false),
   'index', coalesce(v.index, '[]'::jsonb),
   'cards', private.event_cards(coalesce(v.card_ids, '{}'::uuid[])));
end $$;

-- Вікно карток: наступна сторінка стрічки, стос майданчика, добірка головної. Сотня за раз — це
-- більше, ніж поміщається на будь-якому екрані, і менше, ніж варто тягнути одним запитом.
create or replace function public.event_cards_by_ids(p_ids uuid[])
returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if p_ids is null then return '[]'::jsonb; end if;
 if array_length(p_ids, 1) > 100 then raise exception 'TOO_MANY_IDS' using errcode='22023'; end if;
 return private.event_cards(p_ids);
end $$;

revoke all on function
 public.discover_events(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer),
 public.event_cards_by_ids(uuid[])
 from public,anon,authenticated;
grant execute on function
 public.discover_events(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer),
 public.event_cards_by_ids(uuid[])
 to anon,authenticated;

-- ------------------------------------------------------------------ 5. старий вхід теж дешевшає
--
-- Той самий запобіжник у чинній RPC, щоб збірки, які ще не знають про `discover_events`, теж
-- перестали платити 470 мс за фільтр «Є місця». Сигнатура й тип повернення ті самі, тож це
-- заміна тіла, а не перестворення: композит не чіпається, п'ять залежних функцій лишаються.
create or replace function public.search_events_in_view(p_south double precision,p_west double precision,p_north double precision,p_east double precision,p_category text default null,p_from timestamptz default null,p_to timestamptz default null,p_text text default null,p_available boolean default false)
 returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text)>120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and e.starts_at > now()
 and private.is_discoverable(e.origin,e.import_status,e.quality)
 and (nullif(btrim(p_text),'') is null or strpos(lower(concat_ws(' ',e.title,e.description,e.city,e.address)),lower(btrim(p_text)))>0)
 and (not coalesce(p_available,false) or case when e.capacity is null then false else private.event_has_space(e.id) end)
 and (p_category is null or e.category=p_category)
 and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
 and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
 or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
 or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326))))
 order by e.starts_at,e.id limit 300)) r order by r.starts_at,r.id;
end $$;

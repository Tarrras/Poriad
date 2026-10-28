-- Кіно (docs/cinema-import.md): категорія `cinema` для сеансів Multiplex і Planeta Kino з імпорту. Розклад
-- віддаємо лише клієнтам, що його знають, а рядок індексу кіносеансу несе назву кінотеатру — квиток із гаманця
-- знаходить свій зал, а не сусідній. Backfill не потрібен: кіно приходить новим джерелом.

-- ───────────────────────────────────────────── категорія

alter table public.events drop constraint events_category_check;
alter table public.events add constraint events_category_check
 check (category in ('music','sport','art','food','games','outdoors','social','comedy','kids',
                     'tours','conference','cinema'));

alter table public.user_preferences drop constraint user_preferences_categories_check;
alter table public.user_preferences add constraint user_preferences_categories_check
 check (categories <@ array['music','sport','art','food','games','outdoors','social','comedy','kids',
                           'tours','conference','cinema']::text[]);

-- Тіло — з 20261102120000_security_hardening; інтерес `cinema` і стеля 12.
create or replace function private.touch_device(p_token text, p_platform text, p_city text, p_interests text[]) returns void
language plpgsql security definer set search_path='' as $$
declare v_interests text[] := coalesce(p_interests, '{}');
 -- nullif: у сесії після запиту PostgREST налаштування лишається порожнім рядком, а не null.
 v_ip text := nullif(nullif(current_setting('request.headers', true), '')::json->>'cf-connecting-ip', '');
begin
 if p_platform is null or p_platform not in ('android','ios') then raise exception 'INVALID_PLATFORM' using errcode='22023'; end if;
 -- Межа повтору в регулярних виразах Postgres — 255, тож довжину FCM-токена міряємо окремо.
 if p_token is null or (p_platform = 'ios' and p_token !~ '^[0-9a-f]{64}$')
   or (p_platform = 'android' and (p_token !~ '^[A-Za-z0-9_:-]+$' or length(p_token) not between 100 and 4096)) then
  raise exception 'INVALID_TOKEN' using errcode='22023';
 end if;
 if p_city is not null and p_city not in ('Київ','Харків','Одеса','Дніпро','Львів') then raise exception 'INVALID_CITY' using errcode='22023'; end if;
 if cardinality(v_interests) > 12 or array_position(v_interests, null) is not null or not v_interests <@ array['music','sport','art','food','games',
   'outdoors','social','comedy','kids','tours','conference','cinema'] then
  raise exception 'INVALID_INTERESTS' using errcode='22023';
 end if;
 update private.devices set platform = p_platform, city = p_city, interests = v_interests, last_seen = now() where token = p_token;
 if found then return; end if;
 if v_ip is not null then
  delete from private.device_ips where ip = v_ip and at < now() - interval '1 hour';
  if (select count(*) from private.device_ips where ip = v_ip) >= 60 then
   raise warning 'touch_device: too many new devices from one address, not stored';
   return;
  end if;
  insert into private.device_ips(ip) values (v_ip);
 end if;
 if (select count(*) from private.devices) >= 100000 then
  raise warning 'touch_device: devices ceiling reached, new device not stored';
  return;
 end if;
 insert into private.devices(token, platform, city, interests) values (p_token, p_platform, p_city, v_interests)
 on conflict (token) do update set platform = excluded.platform, city = excluded.city, interests = excluded.interests, last_seen = now();
end $$;

-- ───────────────────────────────────────────── видача

-- Клієнти до 1.4 (і сайт, і пости в Telegram) про кіно не знають: ~1 000 сеансів Києва на три дні прийшли б до них
-- подіями невідомої категорії. Тому `cinema` — лише тим, хто передає `p_cinema`. Новий параметр — нова сигнатура, тож
-- старі видаляються: дві перевантажені з типовими значеннями PostgREST не розрізнить.
drop function public.discover_events(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer);
drop function private.discover_index(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer);

-- Тіло — з 20261110120000_company_intents; фільтр кіно, черга й 13-та позиція: назва місця кіносеансу (`places.name`),
-- решті null. У 47% сеансів Multiplex Києва той самий фільм у ту саму хвилину йде в іншому залі мережі (28.10), і без
-- назви `TicketMatch` обирав би не той. Клієнти до 1.4 читають перші 12 позицій.
-- Кіно — у кінці черги: тиждень сеансів Києва — ~2 200 рядків, і на стелі `p_limit` (5 000) відрізатись мають далекі
-- сеанси, а не концерти грудня. Заодно перші картки (`p_cards`) — не кіно. Клієнт ранжує індекс сам, тож порядок
-- сервера важить лише тут.
create function private.discover_index(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text, p_from timestamptz, p_to timestamptz, p_text text, p_available boolean,
 p_limit integer, p_cards integer, p_cinema boolean)
returns table(index jsonb, total integer, truncated boolean, card_ids uuid[])
language sql stable security definer set search_path='' as $$
 with matched as (
  select e.id, e.starts_at, e.latitude, e.longitude, e.category, e.time_zone, e.title,
         e.origin, e.capacity, e.source_id, e.place_id
  from public.events e
  where e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
    and (coalesce(p_cinema,false) or e.category <> 'cinema')
    -- Варіант у підзапиті: рахується раз на виклик, а не на кожен рядок.
    and (nullif(btrim(p_text),'') is null
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), lower(btrim(p_text))) > 0
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), (select private.search_translit(p_text))) > 0)
    -- `case` замість `and`: порядок обчислення кон'юнкції не гарантований.
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
  select m.*, row_number() over (order by m.category = 'cinema', greatest(m.starts_at, now()), m.id) as rank,
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
     else 0 end,
     -- ponytail: рахуємо всіх, без блоків і неактивних — точне число дає `company_teaser` на деталях.
     case when p.origin='import' then
       (select count(*)::integer from private.company_intents ci where ci.event_id=p.id)
     else 0 end,
     case when p.category='cinema' then pl.name end
   ) order by p.rank) from page p left join public.event_sources s on s.id=p.source_id
     left join public.places pl on pl.id=p.place_id), '[]'::jsonb),
  coalesce((select max(r.total)::integer from ranked r), 0),
  coalesce((select max(r.total) from ranked r), 0) > p_limit,
  coalesce((select array_agg(p.id order by p.rank) from page p where p.rank <= p_cards), '{}'::uuid[]);
$$;
revoke all on function private.discover_index(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer,boolean) from public,anon,authenticated;
grant execute on function private.discover_index(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer,boolean) to anon,authenticated;

-- Тіло — з 20260911070031_discovery_index_and_cards; параметр `p_cinema`.
create function public.discover_events(
 p_south double precision, p_west double precision, p_north double precision, p_east double precision,
 p_category text default null, p_from timestamptz default null, p_to timestamptz default null,
 p_text text default null, p_available boolean default false,
 p_limit integer default 5000, p_cards integer default 24, p_cinema boolean default false)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v record; v_limit integer; v_cards integer;
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90
         and p_west between -180 and 180 and p_east between -180 and 180) then
  raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 -- Запобіжник, а не стеля: на місті не спрацьовує, але не дає одним запитом вивезти країну.
 v_limit := least(greatest(coalesce(p_limit,5000), 1), 5000);
 v_cards := least(greatest(coalesce(p_cards,24), 0), 100);
 select * into v from private.discover_index(
   p_south, p_west, p_north, p_east, p_category, p_from, p_to, p_text, p_available, v_limit, v_cards, p_cinema);
 return jsonb_build_object(
   'total', coalesce(v.total, 0),
   'truncated', coalesce(v.truncated, false),
   'index', coalesce(v.index, '[]'::jsonb),
   'cards', private.event_cards(coalesce(v.card_ids, '{}'::uuid[])));
end $$;
revoke all on function public.discover_events(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer,boolean) from public,anon,authenticated;
grant execute on function public.discover_events(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer,boolean) to anon,authenticated;

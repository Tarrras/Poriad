-- Безпека події: найближчі укриття й комендантська година міста. З 11.09.2026 правила Мінкульту
-- вимагають заздалегідь повідомляти учасникам, де найближче укриття; ми показуємо його в деталях
-- і на веб-сторінці події. Укриття заливає `tools/shelters.py` з відкритих даних міста (Київ, CC BY).

create table public.shelters (
 -- '<джерело>:<id в джерелі>': повторне завантаження оновлює той самий рядок.
 id text primary key,
 city text not null,
 -- metro | underpass | parking | basement — клієнт підписує сам (ShelterKind).
 kind text not null check (kind in ('metro','underpass','parking','basement')),
 address text not null check (length(address) between 1 and 300),
 latitude double precision not null check (latitude between -90 and 90),
 longitude double precision not null check (longitude between -180 and 180),
 location gis.geography(Point,4326) generated always as
  (gis.st_setsrid(gis.st_makepoint(longitude,latitude),4326)::gis.geography) stored,
 -- Пандус / інклюзивний вхід за даними міста.
 accessible boolean not null default false,
 -- Години, якщо не цілодобово. Null — цілодобово.
 hours text check (length(hours) <= 100),
 source text not null,
 updated_at timestamptz not null default now()
);
create index shelters_location_idx on public.shelters using gist (location);
-- Лише через event_safety: сирий список нікому з клієнтів не потрібен.
alter table public.shelters enable row level security;

-- Правила міняє міська чи обласна влада; оновлюється рядком SQL, без релізу застосунків.
create table public.city_curfews (
 city text primary key,
 starts time not null,
 ends time not null,
 updated_at timestamptz not null default now()
);
alter table public.city_curfews enable row level security;
-- Supabase за замовчуванням дає anon/authenticated права на нові таблиці; RLS без політик і так
-- віддав би нуль рядків, але читати їх напряму нікому не треба.
revoke all on public.shelters, public.city_curfews from anon, authenticated;
insert into public.city_curfews (city, starts, ends) values
 ('Київ', '01:00', '05:00'),
 ('Львів', '00:00', '05:00'),
 ('Дніпро', '00:00', '05:00'),
 ('Одеса', '00:00', '05:00'),
 ('Харків', '00:00', '05:00');

-- До трьох найближчих укриттів у радіусі 1 км і комендантська година міста події.
-- Null — подію не видно (той самий has_event_access, що в event_details). Порожні shelters і
-- null curfew — даних для цього місця нема, а не «укриттів нема».
create or replace function public.event_safety(p_event_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'shelters', coalesce((
   select jsonb_agg(to_jsonb(s) order by s.distance_m) from (
    -- Одна адреса — один рядок, а метро — один рядок узагалі (найближчий вхід): інакше три
    -- найближчі бувають трьома входами тієї ж станції, і людина не бачить іншого варіанта.
    select * from (
     select distinct on (case when sh.kind = 'metro' then 'metro' else lower(sh.address) end) sh.kind, sh.address, sh.accessible, sh.hours, sh.latitude, sh.longitude,
            round(gis.st_distance(sh.location, e.location))::integer as distance_m
     from public.shelters sh
     where gis.st_dwithin(sh.location, e.location, 1000)
     order by case when sh.kind = 'metro' then 'metro' else lower(sh.address) end, gis.st_distance(sh.location, e.location)) nearest
    order by distance_m, address
    limit 3) s), '[]'::jsonb),
  'curfew', (select jsonb_build_object('starts', to_char(c.starts, 'HH24:MI'), 'ends', to_char(c.ends, 'HH24:MI'))
             from public.city_curfews c where c.city = e.city))
 from public.events e
 where e.id = p_event_id and private.has_event_access(e.id);
$$;
revoke all on function public.event_safety(uuid) from public, anon, authenticated;
grant execute on function public.event_safety(uuid) to anon, authenticated;

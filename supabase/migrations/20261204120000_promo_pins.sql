-- Промокоди й піни (docs/promo-pins-2026-11.md).
--  * Промокод — код знижки, який діє на сайті квитків продавця чи організатора; заодно мітка: продавець рахує квитки з
--    кодом. Ставить організатор власної події (кабінет на сайті) через set_event_promo; на подіях з імпорту — ми SQL-ом.
--    create_event/update_event не чіпаємо: застосунок поля не надсилає й не зітре. Видаємо, лише поки діє.
--  * Пін — закріплена подія: першою в «У місті» застосунку й у «Не пропустіть» сайту, без позначки (власник 12.11:
--    бартер, «Реклама» відлякує). Заводимо SQL-ом у private.event_pins. Пін діє лише там, де подію й так видно: «Лише за
--    посиланням», знята чи минула подія в індекс не потрапляє.

-- ---- Промокод

alter table public.events
 add column promo_code text check (promo_code ~ '^[A-Za-z0-9_-]{2,30}$'),
 add column promo_note text check (char_length(promo_note) <= 60),
 add column promo_until timestamptz;

create function private.set_event_promo(p_event uuid, p_code text, p_note text default null, p_until timestamptz default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events;
 v_code text := nullif(btrim(coalesce(p_code,'')),''); v_note text := nullif(btrim(coalesce(p_note,'')),'');
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 select * into v_event from public.events where id = p_event for update;
 if not found or v_event.organizer_id is distinct from v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
 -- Порожній код прибирає промокод разом з описом і строком.
 if v_code is null then
  update public.events set promo_code = null, promo_note = null, promo_until = null, updated_at = now() where id = p_event;
  return;
 end if;
 if v_event.status <> 'published' or v_event.ends_at <= now() then raise exception 'EVENT_ENDED' using errcode='P0001'; end if;
 if v_code !~ '^[A-Za-z0-9_-]{2,30}$' then raise exception 'INVALID_PROMO_CODE' using errcode='22023'; end if;
 if char_length(v_note) > 60 then raise exception 'INVALID_PROMO_NOTE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_note);
 if private.has_payment_details(v_note) then raise exception 'PAYMENT_DETAILS' using errcode='22023'; end if;
 -- Без строку — до початку події: квитки купують до неї.
 if p_until is not null and (p_until <= now() or p_until > v_event.ends_at) then
  raise exception 'INVALID_PROMO_UNTIL' using errcode='22023'; end if;
 update public.events set promo_code = v_code, promo_note = v_note, promo_until = coalesce(p_until, v_event.starts_at),
  updated_at = now() where id = p_event;
end $$;

create function public.set_event_promo(p_event uuid, p_code text, p_note text default null, p_until timestamptz default null)
returns void language sql set search_path='' as $$ select private.set_event_promo(p_event, p_code, p_note, p_until); $$;

revoke all on function private.set_event_promo(uuid,text,text,timestamptz), public.set_event_promo(uuid,text,text,timestamptz)
 from public, anon, authenticated;
grant execute on function private.set_event_promo(uuid,text,text,timestamptz), public.set_event_promo(uuid,text,text,timestamptz)
 to authenticated;

-- ---- Пін

-- ponytail: стелю «два на місто» тримаємо руками, пінів заводимо одиниці; тригер — коли піни ставитиме не лише команда.
create table private.event_pins (
 event_id uuid primary key references public.events(id) on delete cascade,
 starts_at timestamptz not null default now(),
 ends_at timestamptz,
 note text
);
revoke all on private.event_pins from public, anon, authenticated;

create function private.is_pinned(p_event uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.event_pins p where p.event_id = p_event and p.starts_at <= now()
  and (p.ends_at is null or p.ends_at > now()));
$$;
revoke all on function private.is_pinned(uuid) from public, anon, authenticated;
grant execute on function private.is_pinned(uuid) to anon, authenticated;

-- ---- Точкові правки в нинішніх визначеннях: кожна заміна має знайти свій рядок.

create function pg_temp.rewrite(p_fn regprocedure, p_from text, p_to text) returns void language plpgsql as $$
declare v_def text := pg_get_functiondef(p_fn); v_new text := replace(v_def, p_from, p_to);
begin
 if v_new = v_def then raise exception 'promo_pins: % has no «%»', p_fn, p_from; end if;
 execute v_new;
end $$;

-- Деталі віддають промокод, поки він діє (і строк — кабінету для правки).
alter type public.event_result add attribute promo_code text, add attribute promo_note text, add attribute promo_until timestamptz;
select pg_temp.rewrite('private.event_rows(uuid[])'::regprocedure,
 E' e.link_only\n from public.events e',
 E' e.link_only,\n case when e.promo_until > now() then e.promo_code end,\n case when e.promo_until > now() then e.promo_note end,\n case when e.promo_until > now() then e.promo_until end\n from public.events e');

-- Індекс: закріплені — першими в черзі (тож потрапляють і в сторінку, і в перші картки) і з 15-ю позицією 1.
-- Клієнти ранжують індекс самі: до 1.5 читають свої перші позиції, тож у них подія стоїть на звичайному місці.
select pg_temp.rewrite('private.discover_index(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer,boolean)'::regprocedure,
 E'as origin, e.capacity, e.source_id, e.place_id\n  from public.events e',
 E'as origin, e.capacity, e.source_id, e.place_id, private.is_pinned(e.id) as pinned\n  from public.events e');
select pg_temp.rewrite('private.discover_index(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer,boolean)'::regprocedure,
 'row_number() over (order by r.category = ''cinema'', greatest(r.starts_at, now()), r.id) as rank',
 'row_number() over (order by not r.pinned, r.category = ''cinema'', greatest(r.starts_at, now()), r.id) as rank');
select pg_temp.rewrite('private.discover_index(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean,integer,integer,boolean)'::regprocedure,
 E'     p.sessions\n   ) order by p.rank)',
 E'     p.sessions,\n     case when p.pinned then 1 end\n   ) order by p.rank)');

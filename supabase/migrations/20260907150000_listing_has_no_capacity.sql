-- Місткість — властивість кімнати, а не оголошення.
--
-- Попередні міграції вже сказали, що приєднатися до афіші не можна (`assert_can_join`), але
-- колонка `capacity` лишалася `not null`, тож конвеєр мусив писати туди число. Він писав `1` —
-- і клієнт чесно малював «Лишилось 1 місце» та «0 з 1 учасників» під чужим концертом на 800 осіб.
--
-- Це не вада UI. Поки в рядку стоїть число, будь-який клієнт має право його показати, і кожен
-- новий екран винаходитиме власне «а тут не показуй». Правильна відповідь — не число, а його
-- відсутність: у афіші місткості немає, і сказати це можна лише `null`.

alter table public.events alter column capacity drop not null;

-- Обов'язковість переїжджає туди, де вона справді потрібна, — тим самим прийомом, яким
-- 20260907130000 зняла `organizer_id not null`. Подія, до якої можна приєднатися, зобов'язана
-- мати розмір кімнати: без нього нічого перевіряти на вході й нікого просувати з черги.
alter table public.events add constraint events_community_has_capacity_ck
 check (origin <> 'community' or capacity is not null);

-- Уже імпортовані рядки несуть вигадану одиницю. Прибираємо її разом із причиною.
update public.events set capacity = null where origin <> 'community' and capacity is not null;

-- ------------------------------------------------------------------ запобіжник у черзі
--
-- `private.promote_waitlist` виходить із циклу за умовою `count >= capacity`. При `capacity is
-- null` порівняння дає `null`, тобто «не вийти» — цикл крутився б вічно, тримаючи блокування на
-- рядку. Дістатися туди неможливо (черга закрита для афіші тим самим `assert_can_join`, що й
-- двері), але ціна помилки надто різна з ціною одного рядка: перша версія цієї функції
-- у 20260905221357 таку перевірку мала, і рефактор безпеки її загубив.
create or replace function private.promote_waitlist(p_event_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_event public.events; v_next uuid; v_allowed boolean;
begin
 select * into v_event from public.events where id=p_event_id and status='published';
 if not found or v_event.approval_required or v_event.capacity is null then return; end if;
 loop
  exit when (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity;
  select user_id into v_next from public.event_waitlist where event_id=p_event_id order by created_at,user_id limit 1;
  exit when v_next is null;
  delete from public.event_waitlist where event_id=p_event_id and user_id=v_next;
  begin perform private.assert_can_join(v_next,v_event); v_allowed := true;
  exception when others then v_allowed := false; end;
  if v_allowed then insert into public.event_members(event_id,user_id,status) values(p_event_id,v_next,'approved') on conflict do nothing; end if;
 end loop;
end $$;

-- `private.event_has_space` порівнює `count(*) < e.capacity`: при `null` вираз дає `null`, тож
-- `exists` хибний і фільтр «тільки з вільними місцями» не показує афіші. Це і є потрібна
-- поведінка — окремої правки не потребує.

comment on column public.events.capacity is
 'Розмір кімнати. Null для афіші: чужою місткістю ми не керуємо й не знаємо її.';

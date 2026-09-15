-- Місткість — властивість кімнати, а не афіші. Поки колонка була `not null`, конвеєр писав 1,
-- і клієнт малював «Лишилось 1 місце» під чужим концертом. Правильна відповідь — `null`.

alter table public.events alter column capacity drop not null;

-- Обов'язкова місткість лише у спільнотної події, як organizer_id у 20260907130000.
alter table public.events add constraint events_community_has_capacity_ck
 check (origin <> 'community' or capacity is not null);

-- Прибираємо вигадану одиницю з імпортованих рядків.
update public.events set capacity = null where origin <> 'community' and capacity is not null;

-- ---- Запобіжник у черзі: при `capacity is null` умова виходу з циклу в promote_waitlist давала
-- б null, і цикл крутився б вічно з блокуванням. Недосяжно, але ціна помилки надто велика.
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

-- event_has_space при null дає false, тож фільтр «Є місця» афіші не показує. Так і треба.

comment on column public.events.capacity is
 'Розмір кімнати. Null для афіші: чужою місткістю ми не керуємо й не знаємо її.';

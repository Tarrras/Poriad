-- Пуш учасникам, коли їхня подія змінилась так, що план ламається: організатор її скасував або
-- переніс початок (docs/event-change-push.md). Хто отримує — вирішує функція `push`: підтверджені
-- учасники, крім організатора й тих, хто заблокований з ним.

create function private.on_event_changed() returns trigger language plpgsql security definer set search_path='' as $$
declare v_kind text;
begin
 -- Про те, що вже скінчилось, не сповіщаємо: модерація й видалення акаунта скасовують і минулі події.
 if old.status = 'published' and new.status = 'cancelled' and new.ends_at > now() then
  v_kind := 'cancelled';
 elsif old.starts_at <> new.starts_at and new.status = 'published' and old.starts_at > now() then
  v_kind := 'moved';
 end if;
 if v_kind is not null then
  perform private.notify_push(jsonb_build_object('type','event','kind',v_kind,'event_id',new.id));
 end if;
 return new;
end $$;
-- Лише спільнотні події: конвеєр імпорту щоночі оновлює тисячі рядків, і йому пуші не потрібні.
create trigger events_push after update on public.events
 for each row when (new.organizer_id is not null and
  (old.status is distinct from new.status or old.starts_at is distinct from new.starts_at))
 execute function private.on_event_changed();
revoke all on function private.on_event_changed() from public, anon, authenticated;

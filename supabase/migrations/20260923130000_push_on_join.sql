-- Пуш організатору, коли хтось приєднався до відкритої події (одразу `approved`), а не лише
-- на запит у події з підтвердженням. Той самий тригер: тип пейлоада — за статусом нового рядка.
-- Просування з листа очікування теж вставляє `approved` — організатор дізнається і про це.

create or replace function private.on_member_requested() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.notify_push(jsonb_build_object(
  'type', case when new.status='requested' then 'request' else 'joined' end,
  'event_id', new.event_id, 'user_id', new.user_id));
 return new;
end $$;

drop trigger event_members_push on public.event_members;
create trigger event_members_push after insert on public.event_members
 for each row when (new.status in ('requested','approved')) execute function private.on_member_requested();

revoke all on function private.on_member_requested() from public,anon,authenticated;

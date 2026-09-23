-- Межі назви й опису UGC-подій — ті самі, що EventRules у клієнті (3..120, 10..5000). Досі сервер
-- тримав лише верх опису, тож «Ура» з патченого чи старого клієнта проходило. Імпорт (organizer_id
-- null) не чіпаємо: афіші джерел бувають з коротким описом. Перевіряємо лише змінене поле, щоб
-- правка старої події з коротким описом не падала на незміненому тексті.
create or replace function private.check_event_text() returns trigger language plpgsql set search_path='' as $$
begin
 if new.organizer_id is null then return new; end if;
 if (tg_op='INSERT' or new.title is distinct from old.title)
    and char_length(btrim(new.title)) not between 3 and 120 then
  raise exception 'INVALID_TITLE' using errcode='22023';
 end if;
 if (tg_op='INSERT' or new.description is distinct from old.description)
    and char_length(btrim(new.description)) not between 10 and 5000 then
  raise exception 'INVALID_DESCRIPTION' using errcode='22023';
 end if;
 return new;
end $$;
revoke all on function private.check_event_text() from public,anon,authenticated;

create trigger events_text_lengths before insert or update of title,description on public.events
 for each row execute function private.check_event_text();

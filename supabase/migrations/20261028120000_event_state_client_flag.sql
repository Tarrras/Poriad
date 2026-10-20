-- Стан афіші — клієнтам лише за перемикачем фази 3 (docs/event-offers.md, фаза 4). Потребує
-- 20261027120000_event_changes (private.flag). Поки перемикач `event_changes` вимкнено, клієнти й /e/{id} не бачать стану
-- тіні: `state` — з import_status, як досі, а `previous_starts_at` і `checked_at` — порожні («Перевірено» біля стану,
-- якого не показуємо, вводило б в оману). Увімкнення (private.set_event_changes(true)) одним кроком вмикає пуші,
-- import_status за станом, перенос events.starts_at і стан у клієнтах. Продавці (`offers`) від перемикача не залежать.

create or replace function private.event_client_state(p_event uuid, p_origin text, p_starts timestamptz,
 p_import_status text, out state text, out previous_starts_at timestamptz, out checked_at timestamptz)
language sql stable set search_path='' as $$
 select
  case when p_origin = 'community' then null
       when s.event_id is not null and abs(extract(epoch from s.starts_at - p_starts)) < 60 then s.state
       when p_import_status = 'withdrawn' then 'unknown' else 'scheduled' end,
  case when p_origin <> 'community' and s.state = 'scheduled' and abs(extract(epoch from s.starts_at - p_starts)) < 60
        and abs(extract(epoch from s.previous_starts_at - p_starts)) >= 60 then s.previous_starts_at end,
  case when p_origin <> 'community' then s.checked_at end
 from (select 1) one
 left join private.event_state s on s.event_id = p_event and private.flag('event_changes');
$$;

revoke all on function private.event_client_state(uuid, text, timestamptz, text) from public, anon, authenticated;

-- Подія безкоштовна, лише коли жоден живий продавець не просить грошей; ціна — найменша додатна.
--
-- `bool_or(is_free)` робив безкоштовною всю подію, якщо безкоштовний хоч один продавець. 26.10 на prod «Скляний
-- звіринець», театр ГАРТ, Київ 13.11 (3d99568a) показувався «Безкоштовно»: Concert.ua з «Продаж призупинено» віддав
-- 0 ₴, а Badseller продає той самий сеанс за 550 ₴. Заглушку тепер ловить parse_price (tools/ingest/normalize.py), а
-- тут — щоб нуль одного продавця не перебивав ціну іншого: is_free — лише без жодної додатної ціни, price_min —
-- найменша додатна, а без неї — як було (0 або невідомо).

-- Тіло — з 20261027120000_event_changes; змінено лише агрегати живих пропозицій.
create or replace function private.sync_event(p_event uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_event public.events; v_primary public.event_offers; v_live integer; v_price numeric; v_free boolean; v_status text;
 v_state text;
begin
 select * into v_event from public.events where id = p_event;
 if not found or v_event.merged_into is not null then return; end if;
 select o.* into v_primary from public.event_offers o join public.event_sources s on s.id = o.source_id
 where o.event_id = p_event
 order by o.status = 'live' desc, (o.source_id = v_event.source_id and o.source_uid = v_event.source_uid) desc,
          s.weight desc, o.created_at, o.id
 limit 1;
 if not found then return; end if;           -- подія без пропозицій (спільнотна чи тестова) — не наша справа
 select count(*), coalesce(min(o.price_min) filter (where o.price_min > 0), min(o.price_min)),
        case when bool_or(o.price_min > 0) then false else bool_or(o.is_free) end
 into v_live, v_price, v_free
 from public.event_offers o where o.event_id = p_event and o.status = 'live';
 v_status := case when v_live = 0 then 'withdrawn'
                  when v_event.import_status = 'stale' and v_event.ends_at < now() then 'stale' else 'live' end;
 if private.flag('event_changes') then
  select s.state into v_state from private.event_state s where s.event_id = p_event;
  if v_state in ('cancelled','postponed','unknown') then
   v_status := 'withdrawn';
  elsif v_live = 0 and exists (select 1 from jsonb_array_elements(private.offer_evidence(p_event)) x where x->>'says' = 'alive') then
   v_status := case when v_event.import_status = 'stale' and v_event.ends_at < now() then 'stale' else 'live' end;
  end if;
 end if;
 if v_live = 0 then v_price := v_event.price_min; v_free := v_event.is_free; end if;
 update public.events e set source_id = v_primary.source_id, source_uid = v_primary.source_uid,
  canonical_url = v_primary.canonical_url, price_min = v_price, is_free = v_free, import_status = v_status,
  ingest_run_id = v_primary.ingest_run_id, updated_at = now()
 where e.id = p_event and (e.source_id, e.source_uid, e.canonical_url, e.price_min, e.is_free, e.import_status, e.ingest_run_id)
  is distinct from (v_primary.source_id, v_primary.source_uid, v_primary.canonical_url, v_price, v_free, v_status,
                    v_primary.ingest_run_id);
end $$;

revoke all on function private.sync_event(uuid) from public, anon, authenticated;

-- Нулі Concert.ua, записані до фіксу parse_price: той самий висновок, що й у коді (безкоштовно Concert.ua не продає).
-- Тригер event_offers_sync перераховує подію.
update public.event_offers o set price_min = null, is_free = null
from public.event_sources s
where s.id = o.source_id and s.slug = 'concert_ua' and o.status = 'live' and o.price_min = 0;

-- Решта подій, де нуль одного продавця сховав додатну ціну іншого.
select private.sync_event(e.id) from public.events e
where e.merged_into is null and (e.is_free or e.price_min = 0)
  and exists (select 1 from public.event_offers o where o.event_id = e.id and o.status = 'live' and o.price_min > 0);

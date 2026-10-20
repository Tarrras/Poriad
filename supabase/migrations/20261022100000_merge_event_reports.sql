-- Скарги йдуть за подією (docs/event-offers.md, R2). `merge_event` з 20261021120000_event_offers переносив усі
-- зв'язки, крім `reports.event_id`: скарга на рядок-дубль лишалась на надгробку, якого модерація вже не бачить.
-- Тепер обхід зливає дублі щоночі, тож такі скарги з'являлися б і далі. Тіло функції те саме, плюс скарги.
-- Тригер `reports_auto_hide` дивиться лише на `message_id`, тож перенесення event_id його не будить.

create or replace function private.merge_event(p_from uuid, p_into uuid, p_reason text default 'pipeline') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_from public.events; v_into public.events; v jsonb := '{}'; n integer; d integer;
begin
 select * into v_from from public.events where id = p_from for update;
 select * into v_into from public.events where id = p_into for update;
 if v_from.id is null or v_into.id is null or p_from = p_into or v_from.origin = 'community'
    or v_into.origin = 'community' or v_into.merged_into is not null then
  raise exception 'MERGE_REFUSED % -> %', p_from, p_into using errcode = '22023';
 end if;
 if v_from.merged_into = p_into then return v; end if;
 if v_from.merged_into is not null then
  raise exception 'MERGE_REFUSED % already merged into %', p_from, v_from.merged_into using errcode = '22023';
 end if;

 update public.saved_events x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.saved_events y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.saved_events where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('saved_events', n, 'saved_events_dup', d);

 update public.event_members x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_members y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.event_members where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_members', n, 'event_members_dup', d);

 update public.event_waitlist x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_waitlist y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.event_waitlist where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_waitlist', n, 'event_waitlist_dup', d);

 update public.event_ratings x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_ratings y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.event_ratings where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_ratings', n, 'event_ratings_dup', d);

 update public.event_messages set event_id = p_into where event_id = p_from;
 get diagnostics n = row_count;
 v := v || jsonb_build_object('event_messages', n);

 -- Скарги: унікальних ключів нема, переходять усі.
 update public.reports set event_id = p_into where event_id = p_from;
 get diagnostics n = row_count;
 v := v || jsonb_build_object('reports', n);

 -- Прочитане — пізніша з двох позначок.
 update public.chat_reads y set read_at = greatest(y.read_at, x.read_at) from public.chat_reads x
 where y.event_id = p_into and x.event_id = p_from and x.user_id = y.user_id;
 update public.chat_reads x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.chat_reads y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.chat_reads where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('chat_reads', n, 'chat_reads_dup', d);

 update public.event_artists x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_artists y where y.event_id = p_into and y.artist_id = x.artist_id);
 get diagnostics n = row_count; delete from public.event_artists where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_artists', n, 'event_artists_dup', d);

 update private.follow_announced x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from private.follow_announced y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from private.follow_announced where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('follow_announced', n, 'follow_announced_dup', d);

 update private.follow_seen x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from private.follow_seen y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from private.follow_seen where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('follow_seen', n, 'follow_seen_dup', d);

 -- Супутники йдуть за подією. Другий збір того самого організатора на ту саму подію заборонено
 -- (events_companion_once_idx): такий лишається на надгробку й рахується окремо.
 update public.events c set companion_of = p_into where c.companion_of = p_from
  and not (c.status = 'published' and exists (select 1 from public.events o where o.companion_of = p_into
           and o.organizer_id = c.organizer_id and o.status = 'published'));
 get diagnostics n = row_count;
 v := v || jsonb_build_object('companions', n,
  'companions_kept', (select count(*) from public.events c where c.companion_of = p_from));

 update public.event_offers set event_id = p_into where event_id = p_from;
 get diagnostics n = row_count;
 v := v || jsonb_build_object('offers', n);
 update public.events set merged_into = p_into where merged_into = p_from;     -- без ланцюгів надгробків

 update public.events set description = v_from.description, updated_at = now()
 where id = p_into and description = '' and v_from.description <> '';
 update public.events set image_url = v_from.image_url where id = p_into and image_url is null and v_from.image_url is not null;
 update public.events set merged_into = p_into, import_status = 'withdrawn', updated_at = now() where id = p_from;
 perform private.sync_event(p_into);
 insert into private.event_merges (from_id, into_id, reason, moved) values (p_from, p_into, p_reason, v);
 return v;
end $$;

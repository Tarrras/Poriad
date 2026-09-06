-- Attendee roster for the event page. Visibility deliberately follows the existing member policy:
-- only the organizer and confirmed members read identities, everyone else keeps the aggregate count
-- already returned by event_result. This adds no new exposure of who attends what.
create type public.attendee_result as (
 user_id uuid, display_name text, avatar_url text, joined_at timestamptz
);

-- Invoker, so members_read on event_members and profiles_read on profiles both apply unchanged.
create function public.event_attendees(p_event_id uuid, p_limit integer default 24)
 returns setof public.attendee_result language sql stable security invoker set search_path = '' as $$
 select m.user_id, p.display_name, p.avatar_url, m.joined_at
 from public.event_members m join public.profiles p on p.id = m.user_id
 where m.event_id = p_event_id
 order by m.joined_at, m.user_id
 limit greatest(1, least(coalesce(p_limit, 24), 100));
$$;

revoke all on function public.event_attendees(uuid, integer) from public, anon, authenticated;
grant execute on function public.event_attendees(uuid, integer) to authenticated;

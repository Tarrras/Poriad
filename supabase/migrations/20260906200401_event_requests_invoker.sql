-- The organizer already passes `can_view_members` for their own event, so the request list needs no
-- elevated rights: it reads under the caller's own policies, and its where-clause still limits it to
-- the organizer. One less SECURITY DEFINER function on the public API is one less thing to review.
create or replace function public.event_requests(p_event_id uuid,p_limit integer default 50) returns setof public.attendee_result language sql stable security invoker set search_path='' as $$
 select m.user_id,p.display_name,p.avatar_url,m.joined_at
 from public.event_members m join public.profiles p on p.id=m.user_id
 join public.events e on e.id=m.event_id
 where m.event_id=p_event_id and m.status='requested' and e.organizer_id=auth.uid()
 order by m.joined_at,m.user_id limit greatest(1,least(coalesce(p_limit,50),100));
$$;

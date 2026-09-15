-- Організатор і так проходить `can_view_members` для своєї події, тож список запитів читає під
-- його політиками. На одну SECURITY DEFINER функцію в публічному API менше.
create or replace function public.event_requests(p_event_id uuid,p_limit integer default 50) returns setof public.attendee_result language sql stable security invoker set search_path='' as $$
 select m.user_id,p.display_name,p.avatar_url,m.joined_at
 from public.event_members m join public.profiles p on p.id=m.user_id
 join public.events e on e.id=m.event_id
 where m.event_id=p_event_id and m.status='requested' and e.organizer_id=auth.uid()
 order by m.joined_at,m.user_id limit greatest(1,least(coalesce(p_limit,50),100));
$$;

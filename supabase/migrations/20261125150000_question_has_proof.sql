-- «Є скріншот» (docs/organizer-events.md): організатор онлайн-події бачить на заявці, у таблиці кабінету й у списку
-- розмов, хто вже надіслав скріншот оплати, не відкриваючи кожну розмову.
-- Тіло — з 20261116120000, додано: `has_proof` — у розмові є скріншот від самої людини.
alter type public.question_result add attribute has_proof boolean;

create or replace function public.event_questions(p_event_id uuid) returns setof public.question_result
language sql stable security invoker set search_path='' as $$
 select t.thread_user_id,p.display_name,p.avatar_url,l.body,l.created_at,l.author_id=auth.uid(),u.unread,
  exists(select 1 from public.event_messages m
   where m.event_id=p_event_id and m.thread_user_id=t.thread_user_id and m.author_id=t.thread_user_id and m.image is not null)
 from (select distinct m.thread_user_id from public.event_messages m where m.event_id=p_event_id and m.thread_user_id is not null) t
 join public.profiles p on p.id=t.thread_user_id
 left join public.question_reads r on r.user_id=auth.uid() and r.event_id=p_event_id and r.thread_user_id=t.thread_user_id
 cross join lateral (
  select m.body,m.created_at,m.author_id from public.event_messages m
  where m.event_id=p_event_id and m.thread_user_id=t.thread_user_id
  order by m.created_at desc,m.id desc limit 1
 ) l
 cross join lateral (
  select count(*)::integer as unread from public.event_messages m
  where m.event_id=p_event_id and m.thread_user_id=t.thread_user_id and m.author_id<>auth.uid()
  and m.created_at > coalesce(r.read_at,'-infinity'::timestamptz)
 ) u
 where auth.uid() is not null
 order by l.created_at desc;
$$;

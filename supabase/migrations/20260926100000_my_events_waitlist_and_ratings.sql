-- «Мої події» (docs/my-events.md). Подія, де я в черзі, — теж мій план: без неї вона зникала з
-- вкладки, щойно людина ставала в чергу. Черга читається під RLS (`waitlist_read`: лише свої рядки).
create or replace function public.my_events() returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e where e.organizer_id=auth.uid()
 or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid())
 or exists(select 1 from public.event_waitlist w where w.event_id=e.id and w.user_id=auth.uid())
 or exists(select 1 from public.saved_events s where s.user_id=auth.uid() and s.event_id=e.id))) r order by r.starts_at,r.id;
end $$;

-- Мої бали: список знає, де ще «Оцінити», а де вже «★ N». Definer, бо таблиця закрита
-- (див. 20260921120000_event_ratings.sql); віддає лише рядки автора.
create or replace function private.my_ratings() returns table(event_id uuid, score smallint)
language sql stable security definer set search_path='' as $$
 select r.event_id, r.score from public.event_ratings r where r.user_id=auth.uid();
$$;
create or replace function public.my_ratings() returns table(event_id uuid, score smallint)
language sql stable security invoker set search_path='' as $$ select * from private.my_ratings(); $$;

revoke all on function private.my_ratings(), public.my_ratings() from public, anon, authenticated;
grant execute on function private.my_ratings(), public.my_ratings() to authenticated;

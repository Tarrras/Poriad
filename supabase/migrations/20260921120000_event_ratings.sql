-- Оцінка завершеної кімнати: 1–5 і необов'язковий коментар. Ставить підтверджений учасник
-- протягом 14 днів після кінця, бачить організатор (без імен), учасник — лише свою.
create table if not exists public.event_ratings (
 event_id uuid not null references public.events(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 score smallint not null check (score between 1 and 5),
 comment text check (comment is null or char_length(comment) <= 500),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key (event_id, user_id)
);
alter table public.event_ratings enable row level security;
-- Лише через функції нижче: політик нема навмисно.
revoke all on table public.event_ratings from public, anon, authenticated;

create or replace function private.rate_event(p_event_id uuid, p_score integer, p_comment text default null) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_comment text := nullif(btrim(p_comment), '');
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_score is null or p_score not between 1 and 5 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 if char_length(v_comment) > 500 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 select * into v_event from public.events where id=p_event_id;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if not exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=v_user and m.status='approved') then
  raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 if v_event.ends_at > now() or v_event.ends_at < now() - interval '14 days' then
  raise exception 'RATING_CLOSED' using errcode='P0001'; end if;
 insert into public.event_ratings(event_id, user_id, score, comment) values (p_event_id, v_user, p_score, v_comment)
 on conflict (event_id, user_id) do update set score=excluded.score, comment=excluded.comment, updated_at=now();
end $$;

-- Організатор бачить усі оцінки без імен, учасник — лише свою. Решті порожньо.
create or replace function private.event_ratings(p_event_id uuid)
returns table(score smallint, comment text, created_at timestamptz, mine boolean)
language sql stable security definer set search_path='' as $$
 select r.score, r.comment, r.updated_at, r.user_id=auth.uid()
 from public.event_ratings r join public.events e on e.id=r.event_id
 where r.event_id=p_event_id and auth.uid() is not null and (e.organizer_id=auth.uid() or r.user_id=auth.uid())
 order by r.updated_at desc;
$$;

create or replace function public.rate_event(p_event_id uuid, p_score integer, p_comment text default null) returns void
language sql security invoker set search_path='' as $$ select private.rate_event(p_event_id, p_score, p_comment); $$;
create or replace function public.event_ratings(p_event_id uuid)
returns table(score smallint, comment text, created_at timestamptz, mine boolean)
language sql stable security invoker set search_path='' as $$ select * from private.event_ratings(p_event_id); $$;

revoke all on function private.rate_event(uuid,integer,text), private.event_ratings(uuid),
 public.rate_event(uuid,integer,text), public.event_ratings(uuid) from public, anon, authenticated;
grant execute on function private.rate_event(uuid,integer,text), private.event_ratings(uuid),
 public.rate_event(uuid,integer,text), public.event_ratings(uuid) to authenticated;

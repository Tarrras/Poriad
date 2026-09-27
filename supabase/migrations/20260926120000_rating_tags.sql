-- Оцінка з шторки «Як пройшло?»: до балу й коментаря — теги «Що сподобалось». Набір закритий,
-- ключі ті самі, що `RatingTag` у домені; організатор бачить їх так само без імен.
alter table public.event_ratings add column if not exists tags text[] not null default '{}'
 check (tags <@ array['atmosphere','music','organization','place','people','on_time']);

-- Нова сигнатура: старі трьохаргументні лишились би перевантаженням, і виклик із трьома
-- аргументами став би неоднозначним.
drop function if exists public.rate_event(uuid,integer,text);
drop function if exists private.rate_event(uuid,integer,text);
drop function if exists public.event_ratings(uuid);
drop function if exists private.event_ratings(uuid);

create function private.rate_event(p_event_id uuid, p_score integer, p_comment text default null, p_tags text[] default null) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_comment text := nullif(btrim(p_comment), '');
 v_tags text[] := array(select distinct t from unnest(coalesce(p_tags, '{}')) t order by t);
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_score is null or p_score not between 1 and 5 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 if char_length(v_comment) > 500 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 if not v_tags <@ array['atmosphere','music','organization','place','people','on_time'] then
  raise exception 'INVALID_RATING' using errcode='22023'; end if;
 perform private.assert_clean_text(v_comment);
 select * into v_event from public.events where id=p_event_id;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if not exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=v_user and m.status='approved') then
  raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 -- Блокування в будь-який бік: коментар інакше став би каналом до того, хто заблокував.
 if private.blocked_between(v_user, v_event.organizer_id) then raise exception 'BLOCKED' using errcode='42501'; end if;
 if v_event.ends_at > now() or v_event.ends_at < now() - interval '14 days' then
  raise exception 'RATING_CLOSED' using errcode='P0001'; end if;
 -- Новий текст — новий розгляд: позначка прихованого з попереднього коментаря не переноситься.
 insert into public.event_ratings as r (event_id, user_id, score, comment, tags) values (p_event_id, v_user, p_score, v_comment, v_tags)
 on conflict (event_id, user_id) do update set score=excluded.score, comment=excluded.comment, tags=excluded.tags, updated_at=now(),
  comment_hidden_at = case when r.comment is not distinct from excluded.comment then r.comment_hidden_at end;
end $$;

-- Прихований модерацією коментар організатор не бачить; автор бачить свій як є. Теги — не текст, їх видно завжди.
create function private.event_ratings(p_event_id uuid)
returns table(score smallint, comment text, created_at timestamptz, mine boolean, tags text[])
language sql stable security definer set search_path='' as $$
 select r.score,
  case when r.user_id=auth.uid() or (r.comment_hidden_at is null and not private.blocked_between(auth.uid(), r.user_id)) then r.comment end,
  r.updated_at, r.user_id=auth.uid(), r.tags
 from public.event_ratings r join public.events e on e.id=r.event_id
 where r.event_id=p_event_id and auth.uid() is not null and (e.organizer_id=auth.uid() or r.user_id=auth.uid())
 order by r.updated_at desc;
$$;

create function public.rate_event(p_event_id uuid, p_score integer, p_comment text default null, p_tags text[] default null) returns void
language sql security invoker set search_path='' as $$ select private.rate_event(p_event_id, p_score, p_comment, p_tags); $$;
create function public.event_ratings(p_event_id uuid)
returns table(score smallint, comment text, created_at timestamptz, mine boolean, tags text[])
language sql stable security invoker set search_path='' as $$ select * from private.event_ratings(p_event_id); $$;

revoke all on function private.rate_event(uuid,integer,text,text[]), private.event_ratings(uuid),
 public.rate_event(uuid,integer,text,text[]), public.event_ratings(uuid) from public, anon, authenticated;
grant execute on function private.rate_event(uuid,integer,text,text[]), private.event_ratings(uuid),
 public.rate_event(uuid,integer,text,text[]), public.event_ratings(uuid) to authenticated;

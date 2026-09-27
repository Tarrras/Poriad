-- Теги оцінки залежать від категорії події (`RatingRules.tagsFor`). Словник ширшає; який тег якій
-- категорії — вирішує клієнт: чужий для категорії тег нічого не ламає, тож сервер тримає лише словник.
-- Словник тепер в одному місці — в обмеженні колонки; `rate_event` його більше не дублює.
alter table public.event_ratings drop constraint if exists event_ratings_tags_check;
alter table public.event_ratings add constraint event_ratings_tags_check check (tags <@ array[
 'atmosphere','organization','place','people','on_time',
 'music','sound','humor','host','program','coach','workout','route','views','pace',
 'guide','stories','food','drinks','game_choice','rules','conversation',
 'kids_liked','safety','speakers','useful','networking']);

create or replace function private.rate_event(p_event_id uuid, p_score integer, p_comment text default null, p_tags text[] default null) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_event public.events; v_comment text := nullif(btrim(p_comment), '');
 v_tags text[] := array(select distinct t from unnest(coalesce(p_tags, '{}')) t order by t);
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_score is null or p_score not between 1 and 5 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 if char_length(v_comment) > 500 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 if cardinality(v_tags) > 6 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
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
 -- Тег поза словником відкидає обмеження колонки (check_violation).
 insert into public.event_ratings as r (event_id, user_id, score, comment, tags) values (p_event_id, v_user, p_score, v_comment, v_tags)
 on conflict (event_id, user_id) do update set score=excluded.score, comment=excluded.comment, tags=excluded.tags, updated_at=now(),
  comment_hidden_at = case when r.comment is not distinct from excluded.comment then r.comment_hidden_at end;
end $$;

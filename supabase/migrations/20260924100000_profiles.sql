-- Профіль: «Про себе», дата приходу, власне фото, картка людини з лічильниками, модерація профілю.
-- Див. docs/profile.md.

-- 1. Нові поля. created_at — з auth.users, щоб у старих акаунтів «з нами з» було правдою.
alter table public.profiles add column if not exists bio text;
alter table public.profiles drop constraint if exists profiles_bio_ck;
alter table public.profiles add constraint profiles_bio_ck check (bio is null or char_length(bio) between 1 and 300);
alter table public.profiles add column if not exists created_at timestamptz not null default now();
update public.profiles p set created_at=u.created_at from auth.users u where u.id=p.id and p.created_at<>u.created_at;
grant update(bio) on public.profiles to authenticated;

-- 2. Тригер перевіряє й bio. Фото — лише з теки avatar власника: так файл події не стане аватаром,
-- а видалення акаунта (усе під <uid>/) прибирає і його.
create or replace function private.on_profile_write() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  begin perform private.assert_clean_text(new.display_name);
  exception when sqlstate '22023' then new.display_name := 'Учасник'; end;
 elsif new.display_name is distinct from old.display_name then
  perform private.assert_clean_text(new.display_name);
 end if;
 if new.bio is not null and (tg_op='INSERT' or new.bio is distinct from old.bio) then
  perform private.assert_clean_text(new.bio);
 end if;
 if new.avatar_url is not null and (tg_op='INSERT' or new.avatar_url is distinct from old.avatar_url)
  and new.avatar_url !~ (private.image_url_prefix() || new.id::text || '/avatar/[^/?#[:space:]]+$') then
  raise exception 'INVALID_IMAGE_URL' using errcode='22023'; end if;
 return new;
end $$;
revoke all on function private.on_profile_write() from public, anon, authenticated;
drop trigger if exists profiles_validate on public.profiles;
create trigger profiles_validate before insert or update of display_name, avatar_url, bio on public.profiles
 for each row execute function private.on_profile_write();

-- 3. Storage: запис у <uid>/avatar/<файл> — свій аватар; решта шляхів, як і раніше, лише в теку власної події.
create or replace function private.owns_image_path(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and split_part(p_name,'/',1)=auth.uid()::text and (
  (split_part(p_name,'/',2)='avatar' and split_part(p_name,'/',3)<>'' and split_part(p_name,'/',4)='')
  or exists(select 1 from public.events e where e.id::text=split_part(p_name,'/',2) and e.organizer_id=auth.uid()));
$$;
revoke all on function private.owns_image_path(text) from public, anon, authenticated;
grant execute on function private.owns_image_path(text) to authenticated;

-- 4. Картка людини. Definer, бо лічильники читають чужі членства, яких RLS не віддає; видимість —
-- явно: та сама межа, що в profiles_read, плюс організатор опублікованої спільнотної події (його імʼя
-- й так на картці події). Блокування в будь-який бік і обмежений акаунт ховають картку; себе видно завжди.
-- Пошта — лише своя, з JWT: у публічні таблиці вона не копіюється.
create type public.profile_card_result as (
 user_id uuid, display_name text, avatar_url text, bio text, member_since timestamptz,
 organized integer, attended integer, email text
);

create or replace function private.profile_card(p_user_id uuid) returns setof public.profile_card_result
language sql stable security definer set search_path='' as $$
 select p.id, p.display_name, p.avatar_url, p.bio, p.created_at,
  (select count(*)::integer from public.events e
    where e.organizer_id=p.id and e.origin='community' and e.status='published'),
  (select count(*)::integer from public.event_members m join public.events e on e.id=m.event_id
    where m.user_id=p.id and m.status='approved' and e.status='published' and e.ends_at < now()),
  case when p.id=auth.uid() then auth.jwt()->>'email' end
 from public.profiles p
 where p.id=p_user_id and auth.uid() is not null and (
  p.id=auth.uid() or (
   private.account_active(p.id) and not private.blocked_between(auth.uid(), p.id) and (
    private.can_see_profile(p.id)
    or exists(select 1 from public.events e where e.organizer_id=p.id and e.origin='community' and e.status='published'))));
$$;
create or replace function public.profile_card(p_user_id uuid) returns setof public.profile_card_result
language sql stable security invoker set search_path='' as $$ select * from private.profile_card(p_user_id); $$;
revoke all on function private.profile_card(uuid), public.profile_card(uuid) from public, anon, authenticated;
grant execute on function private.profile_card(uuid), public.profile_card(uuid) to authenticated;

-- 5. Модерація профілю: clear_avatar / clear_bio / reset_name. Файл фото лишається в бакеті до
-- видалення акаунта: SQL не може видаляти з storage.objects (storage.protect_delete).
create or replace function public.moderate_profile(p_user_id uuid, p_action text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.assert_moderator();
 if p_action='clear_avatar' then update public.profiles set avatar_url=null where id=p_user_id;
 elsif p_action='clear_bio' then update public.profiles set bio=null where id=p_user_id;
 elsif p_action='reset_name' then update public.profiles set display_name='Учасник' where id=p_user_id;
 else raise exception 'INVALID_ACTION' using errcode='22023'; end if;
end $$;
revoke all on function public.moderate_profile(uuid,text) from public, anon, authenticated;
grant execute on function public.moderate_profile(uuid,text) to authenticated;

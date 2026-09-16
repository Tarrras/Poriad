-- Аудит 2026-09-16, K3. Видалення акаунту з застосунку — вимога Google Play (Account deletion)
-- і App Store 5.1.1(v). Клієнт із publishable key не може кликати auth.admin, тож видаляє definer
-- від postgres, який має DELETE на auth.users. Каскади FK роблять решту: profiles → user_preferences,
-- account_facts, event_members, saved_events, event_waitlist, user_blocks, reports(reporter),
-- event_messages(author), chat_reads, push_tokens; власні події зникають разом з їхніми членствами
-- й чатом (events.organizer_id … on delete cascade). Фото в публічному бакеті FK не має — прибираємо явно.

create or replace function private.delete_my_account() returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 delete from storage.objects where bucket_id='event-images' and name like v_user::text || '/%';
 delete from auth.users where id=v_user;
end $$;
create or replace function public.delete_my_account() returns void
language sql security invoker set search_path='' as $$ select private.delete_my_account(); $$;
revoke all on function private.delete_my_account(), public.delete_my_account() from public, anon, authenticated;
grant execute on function private.delete_my_account() to authenticated;
grant execute on function public.delete_my_account() to authenticated;

-- Копія своїх даних (GDPR ст. 20). Definer, бо to_jsonb(row) читає всі колонки events, а табличний грант
-- звужено до потрібних (20260917100300); кожен підзапит фільтрує по auth.uid(). status_note — нотатка модерації.
create or replace function public.export_my_data() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'exported_at', now(),
  'profile', (select to_jsonb(p) from public.profiles p where p.id=auth.uid()),
  'account', (select to_jsonb(a) - 'status_note' from public.account_facts a where a.user_id=auth.uid()),
  'preferences', (select to_jsonb(u) from public.user_preferences u where u.user_id=auth.uid()),
  'events', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from public.events e where e.organizer_id=auth.uid()),
  'memberships', (select coalesce(jsonb_agg(to_jsonb(m)), '[]') from public.event_members m where m.user_id=auth.uid()),
  'saved', (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from public.saved_events s where s.user_id=auth.uid()),
  'waitlist', (select coalesce(jsonb_agg(to_jsonb(w)), '[]') from public.event_waitlist w where w.user_id=auth.uid()),
  'blocks', (select coalesce(jsonb_agg(to_jsonb(b)), '[]') from public.user_blocks b where b.user_id=auth.uid()),
  'reports', (select coalesce(jsonb_agg(to_jsonb(r)), '[]') from public.reports r where r.reporter_id=auth.uid()),
  'messages', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.event_messages x where x.author_id=auth.uid())
 );
$$;
revoke all on function public.export_my_data() from public, anon, authenticated;
grant execute on function public.export_my_data() to authenticated;

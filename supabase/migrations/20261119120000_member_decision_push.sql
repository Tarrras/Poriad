-- Пуші учаснику про рішення щодо нього (docs/organizers-1.5.md, 1.1 «Листи»): організатор прийняв запит, не прийняв
-- його, або звільнилось місце й людину забрали з черги. Досі людина дізнавалась про це, лише відкривши застосунок.
-- Payload `{type:'decision', kind:'approved'|'declined'|'promoted', event_id, user_id}`. На пристрої — лише
-- застосункам, що знають ці види (`decision` у `push_tokens.features`); тим, у кого застосунку нема, — листом
-- (функція `push`). Транзакційні, тож тихі години їх не тримають.
--
-- Функцій рішень не переписуємо — тригери на `event_members` і `event_waitlist`:
-- - прийняв: `decide_member` міняє `requested` → `approved`;
-- - не прийняв: `decide_member` видаляє рядок `requested`. Видаляє його й сама людина (`leave_event`), блокування,
--   видалення події чи акаунта, тож рішення — лише коли видаляє організатор цієї події;
-- - з черги: `promote_waitlist` видаляє рядок черги, а тоді вставляє `approved`. Звичайний запис (`join_event`,
--   `company_match`) навпаки вставляє учасника першим і чистить чергу після, тож пара «вийшов з черги → став
--   учасником» в одній транзакції — це саме підтягування.
-- `company_match` (позначка `poruch.company_match`) пропускаємо: він сам шле пуш обом.

create function private.on_waitlist_left() returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- ponytail: пам'ятаємо лише останнього, хто вийшов з черги в цій транзакції; `promote_waitlist` вставляє його
 -- одразу після delete. Якщо колись між ними з'явиться ще одне видалення з черги, `promoted` загубиться.
 perform set_config('poruch.left_waitlist', old.event_id::text || ':' || old.user_id::text, true);
 return null;
end $$;

create function private.on_member_decided() returns trigger language plpgsql security definer set search_path='' as $$
declare v_kind text; v_event uuid; v_user uuid;
begin
 if current_setting('poruch.company_match', true) = 'on' then return null; end if;
 if tg_op = 'UPDATE' then
  v_kind := 'approved'; v_event := new.event_id; v_user := new.user_id;
 elsif tg_op = 'DELETE' then
  if not exists(select 1 from public.events e where e.id = old.event_id and e.organizer_id = auth.uid()) then return null; end if;
  v_kind := 'declined'; v_event := old.event_id; v_user := old.user_id;
 elsif current_setting('poruch.left_waitlist', true) = new.event_id::text || ':' || new.user_id::text then
  v_kind := 'promoted'; v_event := new.event_id; v_user := new.user_id;
 else
  return null;
 end if;
 perform private.notify_push(jsonb_build_object('type', 'decision', 'kind', v_kind, 'event_id', v_event, 'user_id', v_user));
 return null;
end $$;

create trigger event_waitlist_left after delete on public.event_waitlist
 for each row execute function private.on_waitlist_left();
create trigger event_members_approved after update of status on public.event_members
 for each row when (old.status = 'requested' and new.status = 'approved') execute function private.on_member_decided();
create trigger event_members_declined after delete on public.event_members
 for each row when (old.status = 'requested') execute function private.on_member_decided();
create trigger event_members_promoted after insert on public.event_members
 for each row when (new.status = 'approved') execute function private.on_member_decided();

revoke all on function private.on_waitlist_left(), private.on_member_decided() from public, anon, authenticated;

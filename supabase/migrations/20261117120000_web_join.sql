-- 1.5, хвиля 1: запис з вебу і галочка «Мені вже є 18» (docs/organizers-1.5.md, 1.1).
-- Людина з посилання організатора записується просто на poriad.app/e/{id}. Правила ті самі, що в застосунку,
-- тож веб кличе наявні функції, а звідки прийшов запис, позначає `via`: це головне мірило 1.5.

-- ───── Звідки запис
alter table public.event_members add column via text not null default 'app' check (via in ('app','web'));
alter table public.event_waitlist add column via text not null default 'app' check (via in ('app','web'));

-- Веб-обгортки ставлять `poruch.via` на транзакцію, а тригер позначає лише рядок самої людини: підтягування з
-- черги чи будь-чий інший рядок у тій самій транзакції не перейме чужого `via`.
create function private.mark_via() returns trigger language plpgsql set search_path='' as $$
begin
 if new.user_id=auth.uid() and current_setting('poruch.via',true)='web' then new.via := 'web'; end if;
 return new;
end $$;
revoke all on function private.mark_via() from public,anon,authenticated;
create trigger event_members_via before insert on public.event_members for each row execute function private.mark_via();
create trigger event_waitlist_via before insert on public.event_waitlist for each row execute function private.mark_via();

-- Позначку знімаємо одразу: інакше наступний виклик у тій самій транзакції теж став би «веб».
create function public.join_event_web(p_event uuid) returns void language plpgsql security invoker set search_path='' as $$
begin
 perform set_config('poruch.via','web',true);
 perform private.join_event(p_event);
 perform set_config('poruch.via','',true);
end $$;
create function public.join_waitlist_web(p_event uuid) returns void language plpgsql security invoker set search_path='' as $$
begin
 perform set_config('poruch.via','web',true);
 perform private.join_waitlist(p_event);
 perform set_config('poruch.via','',true);
end $$;
revoke all on function public.join_event_web(uuid),public.join_waitlist_web(uuid) from public,anon,authenticated;
grant execute on function public.join_event_web(uuid),public.join_waitlist_web(uuid) to authenticated;

-- Тіло — з 20260907150000, додано: людина з черги несе своє `via` в учасники.
create or replace function private.promote_waitlist(p_event_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_event public.events; v_next uuid; v_via text; v_allowed boolean;
begin
 select * into v_event from public.events where id=p_event_id and status='published';
 if not found or v_event.approval_required or v_event.capacity is null then return; end if;
 loop
  exit when (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity;
  select user_id,via into v_next,v_via from public.event_waitlist where event_id=p_event_id order by created_at,user_id limit 1;
  exit when v_next is null;
  delete from public.event_waitlist where event_id=p_event_id and user_id=v_next;
  begin perform private.assert_can_join(v_next,v_event); v_allowed := true;
  exception when others then v_allowed := false; end;
  if v_allowed then insert into public.event_members(event_id,user_id,status,via) values(p_event_id,v_next,'approved',v_via) on conflict do nothing; end if;
 end loop;
end $$;

-- ───── Галочка «Мені вже є 18» замість дати
-- Дата народження була потрібна лише для правила «платформа для дорослих»: на prod 01.11 жодна з 21 спільнотної
-- події не має віку від 19 чи верхньої межі. Дату ніхто не перевіряв, тож галочка захищає так само.
alter table public.account_facts add column adult_confirmed_at timestamptz;

-- Нижня межа віку: точний вік з дати, а для галочки — мінімум платформи. Перевірки «вік невідомий»
-- (запис, створення, компанія, оцінки) так пропускають людину з галочкою без змін.
create or replace function private.age_of(p_user uuid) returns integer language sql stable security definer set search_path='' as $$
 select coalesce(private.age_years(f.birth_date),
  case when f.adult_confirmed_at is not null then private.min_signup_age() end)
 from public.account_facts f where f.user_id=p_user;
$$;

-- Тіло — з 20260907120000, додано: без дати точний вік невідомий, тож для віку від 19 чи верхньої межі
-- просимо дату (`set_birth_date` дозволяє, поки її нема).
create or replace function private.assert_can_join(p_user uuid,p_event public.events) returns void language plpgsql stable security definer set search_path='' as $$
declare v_age integer;
begin
 if p_event.origin <> 'community' then raise exception 'IMPORTED_EVENT' using errcode='P0001'; end if;
 if not private.account_active(p_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.blocked_between(p_user,p_event.organizer_id) then raise exception 'BLOCKED' using errcode='42501'; end if;
 v_age := private.age_of(p_user);
 if v_age is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 if (p_event.min_age > private.min_signup_age() or p_event.max_age is not null)
  and (select f.birth_date from public.account_facts f where f.user_id=p_user) is null then
  raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 if v_age < p_event.min_age then raise exception 'TOO_YOUNG' using errcode='P0001'; end if;
 if p_event.max_age is not null and v_age > p_event.max_age then raise exception 'TOO_OLD' using errcode='P0001'; end if;
end $$;

-- ponytail: галочку не знімаємо, якщо згодом введена дата виявиться < 18 (`set_birth_date` дасть UNDERAGE і
-- нічого не запише) — це сигнал для модерації, а не для автоматики.
create function private.confirm_adult() returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 insert into public.account_facts(user_id,adult_confirmed_at) values (v_user,now())
 on conflict (user_id) do update set adult_confirmed_at=coalesce(public.account_facts.adult_confirmed_at,now()),updated_at=now();
end $$;
create function public.confirm_adult() returns void language sql security invoker set search_path='' as $$ select private.confirm_adult(); $$;
revoke all on function private.confirm_adult(),public.confirm_adult() from public,anon,authenticated;
grant execute on function private.confirm_adult(),public.confirm_adult() to authenticated;

-- Тіло — з 20261007120000, додано: реєстрація в застосунку з галочкою (хвиля 2) шле `adult_confirmed: true`
-- замість `birth_date`.
create or replace function private.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_raw text := btrim(coalesce(new.raw_user_meta_data->>'birth_date','')); v_birth date;
 v_adult boolean := coalesce(new.raw_user_meta_data->>'adult_confirmed','')='true';
begin
 if v_raw <> '' then
  begin v_birth := v_raw::date; exception when others then raise exception 'INVALID_BIRTH_DATE' using errcode='22023'; end;
  if v_birth > current_date then raise exception 'INVALID_BIRTH_DATE' using errcode='22023'; end if;
  if private.age_years(v_birth) < private.min_signup_age() then raise exception 'UNDERAGE' using errcode='P0001'; end if;
 end if;
 insert into public.profiles(id,display_name) values (new.id,coalesce(
  nullif(left(btrim(new.raw_user_meta_data->>'display_name'),80),''),
  nullif(left(btrim(new.raw_user_meta_data->>'full_name'),80),''),
  nullif(left(btrim(new.raw_user_meta_data->>'name'),80),''),
  'Учасник'));
 insert into public.user_preferences(user_id) values (new.id);
 insert into public.account_facts(user_id,birth_date,adult_confirmed_at) values (new.id,v_birth,case when v_adult then now() end);
 return new;
end $$;

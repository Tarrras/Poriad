-- Вхід через Google: GoTrue кладе імʼя з профілю Google у `full_name` / `name`, а не в наш
-- `display_name`. Без цього кожен такий акаунт ставав «Учасник». Apple імені в токені не дає —
-- клієнт зберігає його сам після першого входу. Решта тіла — як у 20260906195750.
create or replace function private.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_raw text := btrim(coalesce(new.raw_user_meta_data->>'birth_date','')); v_birth date;
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
 insert into public.account_facts(user_id,birth_date) values (new.id,v_birth);
 return new;
end $$;

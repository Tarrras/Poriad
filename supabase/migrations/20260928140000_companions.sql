-- «Шукаю компанію» на імпортованій події (docs/companions.md, п. 1.1 docs/growth-2026-09.md).
--
-- Супутник — звичайна спільнотна подія: місткість, запит на участь, черга, чат і оцінка вже є.
-- Нове лише посилання на батька (`companion_of`), коротка примітка «де зустрітись» і два RPC:
-- `create_companion` замість повного редактора й `companions` — картки супутників без імен.

alter table public.events add column companion_of uuid references public.events(id) on delete set null;
alter table public.events add column meet_note text;
alter table public.events add constraint events_companion_ck
 check (companion_of is null or origin = 'community');
alter table public.events add constraint events_meet_note_ck
 check (meet_note is null or char_length(meet_note) <= 140);
comment on column public.events.companion_of is
 'Імпортована подія, на яку йдуть разом. Лише для спільнотної події, створеної create_companion.';
comment on column public.events.meet_note is 'Де зустрітись, до 140 символів. Лише в супутника.';

-- Один живий супутник від людини на подію; скасувала — може створити новий.
create unique index events_companion_once_idx on public.events (companion_of, organizer_id)
 where companion_of is not null and status = 'published';

-- ---- Проєкція знає батька: рядок «Разом на: …» у застосунку й на сайті без другого запиту.

alter type public.event_result add attribute companion_of uuid;
alter type public.event_result add attribute companion_of_title text;

create or replace function private.event_rows(p_ids uuid[]) returns setof public.event_result language sql stable security definer set search_path = '' as $$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,
 coalesce(p.display_name, s.name),
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
 e.origin,s.name,e.canonical_url,e.import_status,e.price_min,e.is_free,
 -- Чат — лише своїм: організатору й підтвердженим. Запит і черга ще не всередині.
 case when e.organizer_id=auth.uid()
       or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved')
      then e.contact_url end,
 e.companion_of,
 (select pe.title from public.events pe where pe.id=e.companion_of)
 from public.events e
 left join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 where e.id=any(p_ids) and private.has_event_access(e.id)
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$$;

-- ---- Створення. Правила ті самі, що CompanionRules у клієнті.

create function private.create_companion(p_parent_id uuid, p_meet_at timestamptz, p_meet_note text default null, p_capacity integer default 4) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_parent public.events; v_note text := nullif(btrim(p_meet_note),''); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 -- Той самий замок, що в create_event: ліміт на добу рахується без гонки.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 select * into v_parent from public.events where id=p_parent_id;
 if not found or v_parent.origin <> 'import' or v_parent.status <> 'published' or v_parent.starts_at <= now() then
  raise exception 'COMPANION_UNAVAILABLE' using errcode='P0001'; end if;
 -- Повтор після непевної відповіді чи другий тап — той самий супутник, а не другий.
 select e.id into v_id from public.events e where e.companion_of=p_parent_id and e.organizer_id=v_user and e.status='published';
 if found then return v_id; end if;
 if p_meet_at is null or p_meet_at <= now() or p_meet_at > v_parent.starts_at or p_meet_at < v_parent.starts_at - interval '3 hours' then
  raise exception 'INVALID_MEET_TIME' using errcode='22023'; end if;
 if p_capacity is null or p_capacity not between 2 and 8 then raise exception 'INVALID_CAPACITY' using errcode='22023'; end if;
 if char_length(v_note) > 140 then raise exception 'INVALID_MEET_NOTE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_note);
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 v_id := pg_catalog.gen_random_uuid();
 -- Назву й опис складаємо тут: людина пише лише примітку. Місце, категорія й пояс — батьківські.
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
  capacity,min_age,approval_required,place_id,companion_of,meet_note)
 values(v_id,v_user,btrim(left('Йдемо разом: '||v_parent.title,120)),
  left('Йдемо разом на «'||v_parent.title||'».'||coalesce(' Збір: '||v_note,''),5000),
  v_parent.category,v_parent.city,v_parent.address,v_parent.latitude,v_parent.longitude,p_meet_at,v_parent.ends_at,v_parent.time_zone,
  p_capacity,18,true,v_parent.place_id,p_parent_id,v_note);
 return v_id;
end $$;

create function public.create_companion(p_parent_id uuid, p_meet_at timestamptz, p_meet_note text default null, p_capacity integer default 4) returns uuid
language sql set search_path='' as $$ select private.create_companion(p_parent_id,p_meet_at,p_meet_note,p_capacity); $$;

revoke all on function private.create_companion(uuid,timestamptz,text,integer), public.create_companion(uuid,timestamptz,text,integer) from public, anon, authenticated;
grant execute on function private.create_companion(uuid,timestamptz,text,integer), public.create_companion(uuid,timestamptz,text,integer) to authenticated;

-- Час, місце й місткість супутника тримає create_companion; update_event їх не переписує.
-- Статус, фото й посилання на чат змінюються як завжди. Сервіс і модерація (auth.uid() null) — без обмежень.
create function private.guard_companion() returns trigger language plpgsql set search_path='' as $$
begin
 if auth.uid() is null then return new; end if;
 if old.companion_of is null and new.companion_of is not null then raise exception 'COMPANION_LOCKED' using errcode='P0001'; end if;
 if old.companion_of is not null and (new.title,new.description,new.category,new.city,new.address,new.latitude,new.longitude,
   new.starts_at,new.ends_at,new.time_zone,new.capacity,new.min_age,new.max_age,new.approval_required,new.companion_of,new.meet_note)
   is distinct from (old.title,old.description,old.category,old.city,old.address,old.latitude,old.longitude,
   old.starts_at,old.ends_at,old.time_zone,old.capacity,old.min_age,old.max_age,old.approval_required,old.companion_of,old.meet_note) then
  raise exception 'COMPANION_LOCKED' using errcode='P0001';
 end if;
 return new;
end $$;
revoke all on function private.guard_companion() from public, anon, authenticated;
create trigger events_companion_guard before update on public.events for each row execute function private.guard_companion();

-- ---- Хто вже шукає компанію. Без імен: організатора видно на сторінці супутника, як у будь-якої
-- спільнотної події. Лише ті, куди ще можна подати запит, найближча зустріч першою.

create function public.companions(p_parent_id uuid)
returns table(id uuid, starts_at timestamptz, time_zone text, meet_note text, capacity integer, attendee_count integer, membership text, mine boolean)
language sql stable security definer set search_path='' as $$
 select e.id, e.starts_at, e.time_zone, e.meet_note, e.capacity,
  (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
  coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
  coalesce(e.organizer_id=auth.uid(), false)
 from public.events e
 where e.companion_of=p_parent_id and e.status='published' and e.starts_at > now()
  and private.has_event_access(p_parent_id)
  and (e.organizer_id=auth.uid() or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)))
 order by e.starts_at, e.created_at
 limit 20;
$$;
revoke all on function public.companions(uuid) from public, anon, authenticated;
grant execute on function public.companions(uuid) to anon, authenticated;

-- Аудит 2026-09-23, Б1 / Б2 / С4 і видалені повідомлення: видалення акаунта має реально проходити.
--
-- Б1. Основний шлях тепер Edge Function `delete-account` (Storage API + auth.admin.deleteUser).
-- RPC лишається для вже випущених збірок, але не падає: тригер storage.protect_delete забороняв
-- DELETE зі storage.objects, і вся транзакція разом із delete from auth.users відкочувалась.
-- Прапорець storage.allow_delete_query знімає цю заборону лише в цій транзакції: рядки зникають,
-- файли перестають віддаватися за URL, байти в S3 лишаються сиротами (Edge Function їх прибирає).
create or replace function private.delete_my_account() returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.set_config('storage.allow_delete_query','true',true);
 delete from storage.objects where bucket_id='event-images' and name like v_user::text || '/%';
 delete from auth.users where id=v_user;
end $$;

-- Б2. ON DELETE SET NULL на event_id / subject_user_id конфліктував із CHECK, що вимагав їх NOT NULL:
-- видалити людину, на яку скаржились, чи подію зі скаргою було неможливо. Скарга лишається з
-- subject_type і текстом як доказ; предмет при поданні перевіряє file_report.
-- 'rating' — скарга на коментар до оцінки (20260923100100).
alter table public.reports drop constraint if exists reports_subject;
alter table public.reports drop constraint if exists reports_subject_type_check;
alter table public.reports add constraint reports_subject_type_check check (subject_type in ('event','user','rating'));

create or replace function private.file_report(p_type text,p_event uuid,p_user uuid,p_reason text,p_details text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 -- Ліміти нижче — «порахував → вставив»: паралельні запити одного акаунта йдуть по черзі.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 -- Обмежений акаунт не голосує за приховування чужого.
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_reason is null or p_reason not in ('minors','safety','harassment','scam','spam','other') then
  raise exception 'INVALID_REASON' using errcode='22023'; end if;
 if (p_type='event' and p_event is null) or (p_type in ('user','rating') and p_user is null) then
  raise exception 'INVALID_SUBJECT' using errcode='22023'; end if;
 if p_type in ('user','rating') and p_user=v_user then raise exception 'CANNOT_REPORT_SELF' using errcode='P0001'; end if;
 -- Ліміт: скарга безкоштовна, і так чергу заливають, щоб сховати справжню.
 if (select count(*) from public.reports where reporter_id=v_user and created_at > now()-interval '1 hour') >= 10 then
  raise exception 'TOO_MANY_REPORTS' using errcode='P0001'; end if;
 -- Та сама скарга від тієї ж людини — одна, а не дві: не має виглядати як підтвердження.
 select id into v_id from public.reports
 where reporter_id=v_user and subject_type=p_type
 and event_id is not distinct from p_event and subject_user_id is not distinct from p_user
 and status in ('new','reviewing');
 if v_id is not null then return v_id; end if;
 insert into public.reports(reporter_id,subject_type,event_id,subject_user_id,reason,details)
 values (v_user,p_type,p_event,p_user,p_reason,nullif(btrim(p_details),''))
 returning id into v_id;
 return v_id;
end $$;

create or replace function private.file_report_message(p_event uuid, p_user uuid, p_reason text, p_details text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if (select count(*) from public.reports where reporter_id=v_user and created_at > now()-interval '1 hour') >= 10 then
  raise exception 'TOO_MANY_REPORTS' using errcode='P0001'; end if;
 insert into public.reports(reporter_id,subject_type,event_id,subject_user_id,reason,details)
 values (v_user,'user',p_event,p_user,p_reason,p_details) returning id into v_id;
 return v_id;
end $$;

-- Видалене повідомлення: текст стирається одразу, лишається лише факт і час (для ліміту 20/хв).
-- Доказ для модерації вже лежить у reports.details (перші 500 символів на момент скарги).
-- Модераторське moderate_message('delete') текст не чіпає — це рішення після розгляду.
alter table public.event_messages alter column body drop not null;
alter table public.event_messages drop constraint if exists event_messages_body_check;
alter table public.event_messages add constraint event_messages_body_check
 check ((body is null and deleted_at is not null) or char_length(body) between 1 and 2000);

create or replace function private.delete_message(p_message_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 update public.event_messages m set deleted_at=now(), body=null from public.events e
 where m.id=p_message_id and e.id=m.event_id and m.deleted_at is null and (m.author_id=v_user or e.organizer_id=v_user);
end $$;

-- Одноразово: те, що вже видалили автори чи організатори (модераторське видалення за скаргою
-- лишаємо — його може шукати розгляд).
update public.event_messages m set body=null
where m.deleted_at is not null and m.body is not null
 and not exists(select 1 from public.reports r where r.message_id=m.id);

-- С4. Копія своїх даних: плюс оцінки, прочитане, пристрої для пушів (без самого токена) і email.
create or replace function public.export_my_data() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'exported_at', now(),
  'email', (select u.email from auth.users u where u.id=auth.uid()),
  'profile', (select to_jsonb(p) from public.profiles p where p.id=auth.uid()),
  'account', (select to_jsonb(a) - 'status_note' from public.account_facts a where a.user_id=auth.uid()),
  'preferences', (select to_jsonb(u) from public.user_preferences u where u.user_id=auth.uid()),
  'events', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from public.events e where e.organizer_id=auth.uid()),
  'memberships', (select coalesce(jsonb_agg(to_jsonb(m)), '[]') from public.event_members m where m.user_id=auth.uid()),
  'saved', (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from public.saved_events s where s.user_id=auth.uid()),
  'waitlist', (select coalesce(jsonb_agg(to_jsonb(w)), '[]') from public.event_waitlist w where w.user_id=auth.uid()),
  'blocks', (select coalesce(jsonb_agg(to_jsonb(b)), '[]') from public.user_blocks b where b.user_id=auth.uid()),
  'reports', (select coalesce(jsonb_agg(to_jsonb(r)), '[]') from public.reports r where r.reporter_id=auth.uid()),
  'messages', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.event_messages x where x.author_id=auth.uid()),
  'ratings', (select coalesce(jsonb_agg(to_jsonb(g)), '[]') from public.event_ratings g where g.user_id=auth.uid()),
  'chat_reads', (select coalesce(jsonb_agg(to_jsonb(c)), '[]') from public.chat_reads c where c.user_id=auth.uid()),
  'push_devices', (select coalesce(jsonb_agg(jsonb_build_object('platform',t.platform,'updated_at',t.updated_at)), '[]')
                   from public.push_tokens t where t.user_id=auth.uid())
 );
$$;
revoke all on function public.export_my_data() from public, anon, authenticated;
grant execute on function public.export_my_data() to authenticated;

-- Журнал спроб приєднання без FK: чистимо все старше доби, а не лише свої рядки, —
-- інакше записи видаленого акаунта лежали б вічно.
create or replace function private.assert_join_rate(p_user uuid, p_event uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||p_user::text,0));
 if (select count(*) from private.join_attempts a where a.user_id=p_user and a.created_at > now()-interval '1 hour') >= 20 then
  raise exception 'TOO_MANY_JOINS' using errcode='P0001'; end if;
 insert into private.join_attempts(user_id,event_id) values (p_user,p_event);
 delete from private.join_attempts a where a.created_at < now()-interval '1 day';
end $$;
revoke all on function private.assert_join_rate(uuid,uuid) from public, anon, authenticated;

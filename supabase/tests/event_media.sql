-- Запускати адміністратором бази. Фікстури не зберігаються.
-- Фото й відео події, `created_via` і `via` в учасниках — 20261118120000_event_media.
begin;
select set_config('test.host',gen_random_uuid()::text,true),set_config('test.guest',gen_random_uuid()::text,true),
 set_config('test.event',gen_random_uuid()::text,true),set_config('test.bad',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.host')::uuid,'poruch-media-host-'||current_setting('test.host')||'@example.invalid',jsonb_build_object('display_name','Host','birth_date','1990-01-01')),
 (current_setting('test.guest')::uuid,'poruch-media-guest-'||current_setting('test.guest')||'@example.invalid',jsonb_build_object('display_name','Guest','adult_confirmed',true));
-- Без JWT префікс сховища — запасний шаблон *.supabase.co (20260923100200).
select set_config('test.dir','https://test.supabase.co/storage/v1/object/public/event-images/'||current_setting('test.host')||'/'||current_setting('test.event')||'/',true),
 set_config('test.vdir','https://test.supabase.co/storage/v1/object/public/event-videos/'||current_setting('test.host')||'/'||current_setting('test.event')||'/',true);

set local role authenticated;
do $$
declare v_dir text := current_setting('test.dir'); v_vdir text := current_setting('test.vdir');
 v_media jsonb := jsonb_build_array(
  jsonb_build_object('kind','video','url',v_vdir||'clip.mp4','poster',v_dir||'clip.jpg'),
  jsonb_build_object('kind','photo','url',v_dir||'one.jpg'));
begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 -- Чуже, забагато, відео без постера, невідоме джерело — відмова.
 begin perform public.create_event(current_setting('test.bad')::uuid,'Bad','Bad media','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,
  jsonb_build_array(jsonb_build_object('kind','photo','url',v_dir||'x.jpg')),'web'); raise exception 'foreign folder accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_MEDIA','media from another event folder'; end;
 begin perform public.create_event(current_setting('test.event')::uuid,'Six','Too many','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,
  (select jsonb_agg(jsonb_build_object('kind','photo','url',v_dir||i||'.jpg')) from generate_series(1,6) i),'web'); raise exception 'six accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_MEDIA','at most five'; end;
 begin perform public.create_event(current_setting('test.event')::uuid,'Posterless','Video only','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,
  jsonb_build_array(jsonb_build_object('kind','video','url',v_vdir||'clip.mp4')),'web'); raise exception 'posterless accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_MEDIA','video needs a poster'; end;
 begin perform public.create_event(current_setting('test.event')::uuid,'Via','Odd source','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,null,'bot'); raise exception 'odd via accepted';
 exception when sqlstate '22023' then assert sqlerrm='INVALID_VIA','via is app or web'; end;

 perform public.create_event(current_setting('test.event')::uuid,'Media','With clips','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,v_media,'web');

 -- Гість записується з вебу: організатор бачить звідки.
 perform set_config('request.jwt.claim.sub',current_setting('test.guest'),true);
 perform public.join_event_web(current_setting('test.event')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 assert (select via from public.event_attendees(current_setting('test.event')::uuid) where user_id=current_setting('test.guest')::uuid)='web',
  'roster shows web';
 assert (select jsonb_array_length(media) from public.event_details(current_setting('test.event')::uuid))=2,'details carry media';
end $$;
reset role;

do $$ begin
 assert (select image_url=current_setting('test.dir')||'one.jpg' and created_via='web' from public.events where id=current_setting('test.event')::uuid),
  'cover is the first photo; created from the web';
end $$;

set local role authenticated;
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 -- Старий клієнт без `p_media`: медіа не чіпаємо, обкладинку беремо як передав.
 perform public.update_event(current_setting('test.event')::uuid,'Media','Edited by 1.4','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,current_setting('test.dir')||'one.jpg');
end $$;
reset role;
do $$ begin
 assert (select jsonb_array_length(media)=2 and description='Edited by 1.4' from public.events where id=current_setting('test.event')::uuid),
  'old client keeps media';
end $$;

set local role authenticated;
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 -- Лише відео: обкладинка — його постер. Порожній список — обкладинка як передали.
 perform public.update_event(current_setting('test.event')::uuid,'Media','Video only','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,
  jsonb_build_array(jsonb_build_object('kind','video','url',current_setting('test.vdir')||'clip.mp4','poster',current_setting('test.dir')||'clip.jpg')));
end $$;
reset role;
do $$ begin
 assert (select image_url=current_setting('test.dir')||'clip.jpg' from public.events where id=current_setting('test.event')::uuid),'video poster is the cover';
end $$;

set local role authenticated;
do $$ begin
 perform set_config('request.jwt.claim.sub',current_setting('test.host'),true);
 perform public.update_event(current_setting('test.event')::uuid,'Media','Media cleared','social','Kyiv','Podil',50.46,30.52,
  now()+interval '2 days',now()+interval '2 days 3 hours','Europe/Kyiv',10,null,18,null,false,null,'[]'::jsonb);
end $$;
reset role;
do $$ begin
 assert (select media='[]'::jsonb and image_url is null from public.events where id=current_setting('test.event')::uuid),'cleared media, no cover';
end $$;
rollback;

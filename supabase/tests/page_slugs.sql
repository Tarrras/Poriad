-- Запускати адміністратором бази. Усе відкочується. Коротка адреса сторінки (20261128120000): ставить лише власник,
-- зайняту не взяти, формат перевіряє сервер, без власника адреса звільняється. Чужих рядків не чіпає.
begin;

select set_config('test.u1',gen_random_uuid()::text,true),set_config('test.u2',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-slug-'||id||'@example.invalid',jsonb_build_object('display_name','S','birth_date','1990-01-01')
from unnest(array[current_setting('test.u1'),current_setting('test.u2')]) id;
insert into public.places(name,city,address,latitude,longitude,source) values
 ('Кафе Slug','Ocean','Buoy, 5',-44.1,-34.1,'osm'),('Кафе Slug Два','Ocean','Buoy, 6',-44.2,-34.2,'osm'),('Кафе Slug Чуже','Ocean','Buoy, 7',-44.3,-34.3,'osm');
insert into public.artists(name,key,kind) values ('Slug Solo','slug solo test','person');
select set_config('test.p1',(select id::text from public.places where name='Кафе Slug'),true),
 set_config('test.p2',(select id::text from public.places where name='Кафе Slug Два'),true),
 set_config('test.p3',(select id::text from public.places where name='Кафе Slug Чуже'),true),
 set_config('test.artist',(select id::text from public.artists where key='slug solo test'),true);
do $$ begin
 perform private.set_place_owner(current_setting('test.p1')::uuid,current_setting('test.u1')::uuid);
 perform private.set_place_owner(current_setting('test.p2')::uuid,current_setting('test.u1')::uuid);
 perform private.set_place_owner(current_setting('test.p3')::uuid,current_setting('test.u2')::uuid);
 perform private.set_artist_owner(current_setting('test.artist')::uuid,current_setting('test.u1')::uuid);
end $$;

-- Гість: поставити не може, прочитати адресу може (воркер шукає сторінку за нею).
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.set_place_slug(current_setting('test.p1')::uuid,'poruch-test-slug'); raise exception 'anon set a slug'; exception when insufficient_privilege then null; end;
 begin perform public.set_artist_slug(current_setting('test.artist')::uuid,'poruch-test-slug'); raise exception 'anon set a slug'; exception when insufficient_privilege then null; end;
 assert (select slug is null from public.places where id = current_setting('test.p1')::uuid),'anon reads the column';
end $$;
reset role;

-- u1: ставить, формат, зайняте, той самий рядок в артиста, порожнє прибирає.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$
declare v jsonb; bad text;
begin
 v := public.set_place_slug(current_setting('test.p1')::uuid,'  Poruch-Test-Slug ');
 assert (select x->>'slug' from jsonb_array_elements(v->'places') x where x->>'id' = current_setting('test.p1')) = 'poruch-test-slug','trimmed and lowered';
 foreach bad in array array['ab','-poruch','poruch-','кафе','a b c','poruch_test',repeat('a',33),gen_random_uuid()::text] loop
  begin perform public.set_place_slug(current_setting('test.p1')::uuid,bad); raise exception 'accepted %', bad;
  exception when sqlstate '22023' then assert sqlerrm='INVALID_SLUG'; end;
 end loop;
 assert public.set_place_slug(current_setting('test.p1')::uuid,'poruch-test-slug') = v,'the same again is a no-op';
 begin perform public.set_place_slug(current_setting('test.p2')::uuid,'poruch-test-slug'); raise exception 'two places, one slug';
 exception when sqlstate 'P0001' then assert sqlerrm='SLUG_TAKEN'; end;
 v := public.set_artist_slug(current_setting('test.artist')::uuid,'poruch-test-slug');
 assert v->'artists'->0->>'slug' = 'poruch-test-slug','/a/ is a separate space';
 begin perform public.set_place_slug(current_setting('test.p3')::uuid,'poruch-test-other'); raise exception 'set a slug on someone else''s place';
 exception when sqlstate 'P0001' then assert sqlerrm='PLACE_NOT_FOUND'; end;
 begin perform public.set_artist_slug(gen_random_uuid(),'poruch-test-other'); raise exception 'unknown artist';
 exception when sqlstate 'P0001' then assert sqlerrm='ARTIST_NOT_FOUND'; end;
 v := public.set_place_slug(current_setting('test.p2')::uuid,'poruch-test-two');
 assert not ((select x from jsonb_array_elements(public.set_place_slug(current_setting('test.p2')::uuid,'')->'places') x
              where x->>'id' = current_setting('test.p2')) ? 'slug'),'empty removes the address';
end $$;

-- u2: зайняту адресу не взяти.
select set_config('request.jwt.claim.sub',current_setting('test.u2'),true);
do $$ begin
 begin perform public.set_place_slug(current_setting('test.p3')::uuid,'poruch-test-slug'); raise exception 'took a taken slug';
 exception when sqlstate 'P0001' then assert sqlerrm='SLUG_TAKEN'; end;
end $$;

-- Власник відмовився — адреса вільна, її бере інший.
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$ begin perform public.release_place(current_setting('test.p1')::uuid); perform public.release_artist(current_setting('test.artist')::uuid); end $$;
reset role;
do $$ begin
 assert (select slug is null from public.places where id = current_setting('test.p1')::uuid),'released place: no slug';
 assert (select slug is null from public.artists where id = current_setting('test.artist')::uuid),'released artist: no slug';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u2'),true);
do $$ begin
 assert (public.set_place_slug(current_setting('test.p3')::uuid,'poruch-test-slug')->'places'->0->>'slug') = 'poruch-test-slug','free again';
end $$;
reset role;

rollback;

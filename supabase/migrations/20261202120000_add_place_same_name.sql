-- «Ваш заклад» з мапи (кабінет, `/api/geocode?kind=venue`): імпорт ставить заклади всередині ТЦ у точку самого ТЦ, тож у
-- точці закладу з мапи часто вже стоїть інший — «SHIB Restaurant» у точці «Gagarinn Plaza». add_my_place (20261127120000)
-- брав будь-яке місце на тих самих координатах, і той, хто обрав ТЦ, ставав власником ресторану; так само новий заклад
-- «за адресою» ставав чужим, що вже мав цю адресу. Тепер наявне беремо лише з тією самою назвою (ключ, як в артиста), а
-- інакше новий заклад стає поруч: точка в places унікальна, тож крок ~1 м на північ до вільної.
create or replace function private.add_my_place(p_name text, p_city text, p_address text, p_latitude double precision, p_longitude double precision)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid := private.claimer(); v_name text := btrim(coalesce(p_name,'')); v_place uuid; v_same boolean;
 v_lat double precision := p_latitude;
begin
 if length(v_name) < 2 or length(v_name) > 120 then raise exception 'INVALID_PLACE_NAME' using errcode='22023'; end if;
 if p_latitude is null or p_longitude is null or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
   or nullif(btrim(coalesce(p_city,'')),'') is null then
  raise exception 'INVALID_PLACE' using errcode='22023';
 end if;
 perform private.assert_clean_text(v_name);
 loop
  select p.id, private.artist_key(p.name) = private.artist_key(v_name) into v_place, v_same
  from public.places p where p.latitude = v_lat and p.longitude = p_longitude;
  exit when v_place is null or v_same;
  v_lat := v_lat + 0.00001;
 end loop;
 if v_place is null then
  if (select count(*) from public.places p where p.owner_id = v_user) >= 3 then raise exception 'TOO_MANY_CLAIMS' using errcode='P0001'; end if;
  insert into public.places (name, city, address, latitude, longitude, source)
  values (v_name, btrim(p_city), nullif(btrim(coalesce(p_address,'')),''), v_lat, p_longitude, 'manual')
  returning id into v_place;
 end if;
 return private.claim_place(v_place);
end $$;

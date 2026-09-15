-- Рахує учасників, не розкриваючи список під RLS членства.
create function private.event_has_space(p_event_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.events e where e.id=p_event_id
 and private.has_event_access(e.id)
 and (select count(*) from public.event_members m where m.event_id=e.id)<e.capacity);
$$;
revoke all on function private.event_has_space(uuid) from public,anon,authenticated;
grant execute on function private.event_has_space(uuid) to anon,authenticated;

-- events_in_view лишається для старих клієнтів. Усі фільтри до стелі результату.
create function public.search_events_in_view(p_south double precision,p_west double precision,p_north double precision,p_east double precision,p_category text default null,p_from timestamptz default null,p_to timestamptz default null,p_text text default null,p_available boolean default false)
 returns setof public.event_result language plpgsql stable security invoker set search_path = '' as $$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text)>120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and e.starts_at > now()
 and (nullif(btrim(p_text),'') is null or strpos(lower(concat_ws(' ',e.title,e.description,e.city,e.address)),lower(btrim(p_text)))>0)
 and (not coalesce(p_available,false) or private.event_has_space(e.id))
 and (p_category is null or e.category=p_category)
 and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
 and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
 or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
 or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326))))
 order by e.starts_at,e.id limit 300)) r order by r.starts_at,r.id;
end $$;
revoke all on function public.search_events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean) from public,anon,authenticated;
grant execute on function public.search_events_in_view(double precision,double precision,double precision,double precision,text,timestamptz,timestamptz,text,boolean) to anon,authenticated;

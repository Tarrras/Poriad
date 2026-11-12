-- Запускати адміністратором бази. Усе відкочується. Список подій серії (20261201120000): організатор бачить усі дати
-- своєї серії за початком, зі станом; чужий і гість — нічого; подія поза серією — порожній список.
-- Чужих рядків не чіпає.
begin;

select set_config('test.u1',gen_random_uuid()::text,true),set_config('test.u2',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-series-'||id||'@example.invalid',jsonb_build_object('display_name','Кафе Series','birth_date','1990-01-01')
from unnest(array[current_setting('test.u1'),current_setting('test.u2')]) id;

-- Подія: ім'я фікстури, серія (id першої події) і через скільки днів.
create function pg_temp.make(p_name text, p_series uuid default null, p_days integer default 1) returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
 perform public.create_event(p_id => v_id, p_title => 'Вечір Series '||p_name, p_description => 'Test description',
  p_category => 'music', p_city => 'Ocean', p_address => 'Buoy, 12', p_latitude => -46.1, p_longitude => -36.1,
  p_starts_at => now()+make_interval(days => p_days), p_ends_at => now()+make_interval(days => p_days, hours => 2), p_time_zone => 'UTC',
  p_capacity => 20, p_via => 'web', p_series => p_series);
 perform set_config('test.'||p_name, v_id::text, true);
 return v_id;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.u1'),true);
do $$
declare v jsonb;
begin
 perform pg_temp.make('single');
 assert public.series_events(current_setting('test.single')::uuid) = '[]'::jsonb,'an event outside a series has no list';
 assert public.series_events(gen_random_uuid()) = '[]'::jsonb,'nothing for an unknown event';
 -- Третю дату створено раніше за другу: порядок — за початком, а не за створенням.
 perform pg_temp.make('head');
 perform pg_temp.make('third', current_setting('test.head')::uuid, 15);
 perform pg_temp.make('second', current_setting('test.head')::uuid, 8);
 perform public.cancel_event(current_setting('test.second')::uuid);
 v := public.series_events(current_setting('test.third')::uuid);
 assert v = public.series_events(current_setting('test.head')::uuid),'the same list from any date of the series';
 assert (select array_agg(x->>'id' order by n) from jsonb_array_elements(v) with ordinality t(x, n))
  = array[current_setting('test.head'),current_setting('test.second'),current_setting('test.third')],'by start: '||v::text;
 assert v->1->>'status' = 'cancelled' and v->0->>'status' = 'published' and v->2->>'status' = 'published','a cancelled date stays in the list';
 assert (v->0->>'starts_at')::timestamptz = (select starts_at from public.events where id = current_setting('test.head')::uuid)
  and v->0 ? 'ends_at' and v->0->>'time_zone' = 'UTC','dates and the zone';
end $$;

-- Чужий організатор і гість списку не бачать.
select set_config('request.jwt.claim.sub',current_setting('test.u2'),true);
do $$ begin
 assert public.series_events(current_setting('test.head')::uuid) = '[]'::jsonb,'someone else''s series is empty';
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.series_events(current_setting('test.head')::uuid); raise exception 'anon read a series';
 exception when insufficient_privilege then null; end;
end $$;
reset role;

rollback;

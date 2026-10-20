-- Запускати адміністратором бази. Усе відкочується. Борги фаз 1–2 (docs/event-offers.md, міграція
-- 20261030120000_offer_cleanup): адресна перевірка зливає двійників за кінцевою адресою і розбирає чергу від'єднання.
begin;

create or replace function private.notify_push(p_payload jsonb) returns void language plpgsql security definer
 set search_path='' as $$ begin end $$;

select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),
 set_config('test.run',gen_random_uuid()::text,true),
 set_config('test.t',(date_trunc('minute',now())+interval '10 days')::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,'poruch-cleanup-'||id||'@example.invalid',jsonb_build_object('display_name','C','birth_date','1990-01-01')
from unnest(array[current_setting('test.a'),current_setting('test.b')]) id;
insert into public.event_sources(slug,name,kind,base_url,weight,enabled) values
 ('test_clean_a','Продавець А','manual','https://example.invalid',0.8,true),
 ('test_clean_b','Продавець Б','manual','https://example.invalid',0.7,true);

-- Рядок дампу: переможець (окрема подія) чи копія (у подію переможця). Адреса — https://example.invalid/<uid>.
create function pg_temp.w(p_slug text, p_uid text, p_title text, p_start timestamptz) returns jsonb language sql as $$
 select jsonb_build_object('id',gen_random_uuid(),'slug',p_slug,'uid',p_uid,'url','https://example.invalid/'||p_uid,
  'title',p_title,'description','','category','music','city','Ocean','address','Buoy, 1','lat',-40.5,'lon',-30.5,
  'starts',p_start,'ends',p_start+interval '2 hours','tz','Europe/Kyiv','dedupe','x','quality',0.9,'price',300) $$;
create function pg_temp.c(p_slug text, p_uid text, p_title text, p_start timestamptz, p_wslug text, p_wuid text)
 returns jsonb language sql as $$
 select jsonb_build_object('slug',p_slug,'uid',p_uid,'url','https://example.invalid/'||p_uid,'title',p_title,
  'starts',p_start,'price',250,'winner_slug',p_wslug,'winner_uid',p_wuid) $$;
create function pg_temp.ingest(p_rows jsonb) returns integer language sql as $$
 select private.ingest_offers(current_setting('test.run')::uuid, p_rows) $$;
create function pg_temp.offer(p_uid text) returns uuid language sql stable as $$
 select id from public.event_offers where source_uid=p_uid and source_id in
  (select id from public.event_sources where slug like 'test_clean_%') $$;
create function pg_temp.ev(p_uid text) returns uuid language sql stable as $$
 select event_id from public.event_offers where id=pg_temp.offer(p_uid) $$;
-- Що сторінка сказала про пропозицію (як віддає offer-check).
create function pg_temp.chk(p_uid text, p_final text, p_verdict text, p_detail jsonb default '{}') returns jsonb
 language sql as $$
 select jsonb_build_object('offer_id',o.id,'why','vanished','expected',o.starts_at,'url',o.canonical_url,'http',200,
  'final_url',coalesce(p_final,o.canonical_url),'redirected',coalesce(p_final,o.canonical_url)<>o.canonical_url,
  'verdict',p_verdict,'detail',p_detail)
 from public.event_offers o where o.id=pg_temp.offer(p_uid) $$;
create function pg_temp.vanish(p_uid text) returns void language sql as $$
 update public.event_offers set status='withdrawn' where id=pg_temp.offer(p_uid) $$;

-- ── 1. Двійники: стара адреса знятої події перенаправляє на живу того ж продавця, та сама хвилина → одна подія.
select pg_temp.ingest(jsonb_build_array(
 pg_temp.w('test_clean_a','new-1','Тест Вистава',current_setting('test.t')::timestamptz),
 pg_temp.w('test_clean_a','old-1','Інша назва (Театр Тест)',current_setting('test.t')::timestamptz),
 -- не двійники: інша хвилина; заморожена подія
 pg_temp.w('test_clean_a','min-1','Тест Вистава',current_setting('test.t')::timestamptz+interval '1 minute'),
 pg_temp.w('test_clean_a','frz-1','Тест Вистава',current_setting('test.t')::timestamptz),
 -- «Шерлок»: обидві зняті, скасовані, стара адреса перенаправляє на нову; нова подія молодша
 pg_temp.w('test_clean_a','sh-old','Тест Шерлок (Театр)',current_setting('test.t')::timestamptz+interval '1 day'),
 pg_temp.w('test_clean_a','sh-new','Тест Шерлок',current_setting('test.t')::timestamptz+interval '1 day'),
 -- не двійники: дві різні події на ту саму хвилину, обидві перенаправляють на список
 pg_temp.w('test_clean_a','lst-1','Тест Один',current_setting('test.t')::timestamptz+interval '2 days'),
 pg_temp.w('test_clean_a','lst-2','Тест Два',current_setting('test.t')::timestamptz+interval '2 days')));
select pg_temp.vanish(u) from unnest(array['old-1','min-1','frz-1','sh-old','sh-new','lst-1','lst-2']) u;
update public.event_offers set linked='manual' where id=pg_temp.offer('frz-1');
update public.events set created_at=created_at-interval '1 day' where id=pg_temp.ev('sh-old');
select set_config('test.live',pg_temp.ev('new-1')::text,true), set_config('test.old',pg_temp.ev('old-1')::text,true),
 set_config('test.sh_old',pg_temp.ev('sh-old')::text,true), set_config('test.sh_new',pg_temp.ev('sh-new')::text,true);
insert into public.saved_events(user_id,event_id) values
 (current_setting('test.a')::uuid,current_setting('test.old')::uuid),
 (current_setting('test.b')::uuid,current_setting('test.old')::uuid),
 (current_setting('test.a')::uuid,current_setting('test.live')::uuid),
 (current_setting('test.a')::uuid,current_setting('test.sh_old')::uuid);

select private.record_offer_checks(jsonb_build_array(
 pg_temp.chk('old-1','https://example.invalid/new-1/','scheduled'),          -- «/» у кінці — та сама адреса
 pg_temp.chk('min-1','https://example.invalid/new-1','scheduled'),
 pg_temp.chk('frz-1','https://example.invalid/new-1','scheduled'),
 pg_temp.chk('sh-old','https://example.invalid/sh-new','cancelled'),
 pg_temp.chk('sh-new','https://example.invalid/sh-new','cancelled'),
 pg_temp.chk('lst-1','https://example.invalid/list','redirect_away'),
 pg_temp.chk('lst-2','https://example.invalid/list','redirect_away')));

do $$ declare l uuid := current_setting('test.live')::uuid; d uuid := current_setting('test.old')::uuid;
 a uuid := current_setting('test.a')::uuid; b uuid := current_setting('test.b')::uuid; begin
 assert (select merged_into from public.events where id=d)=l, 'withdrawn twin merged into the live event';
 assert (select reason from private.event_merges where from_id=d and into_id=l)='url_twin', 'merge logged';
 assert private.live_event_id(d)=l, 'old id opens the live event';
 assert (select array_agg(user_id order by user_id) from public.saved_events where event_id=l)
        =(select array_agg(x order by x) from unnest(array[a,b]) x), 'saves moved, duplicate dropped';
 assert not exists (select 1 from public.saved_events where event_id=d), 'nothing left on the tombstone';
 assert (select import_status from public.events where id=l)='live', 'still live';
 -- Фаза 4: продавець один, основна — жива адреса.
 assert jsonb_array_length(private.event_offers_json(l,'https://example.invalid/new-1'))=1, 'one seller';
 assert private.event_offers_json(l,'https://example.invalid/new-1')->0->>'url'='https://example.invalid/new-1', 'live url first';

 assert (select merged_into from public.events where id=pg_temp.ev('min-1')) is null
    and pg_temp.ev('min-1')<>l, 'another minute is another session';
 assert pg_temp.ev('frz-1')<>l and (select merged_into from public.events where id=pg_temp.ev('frz-1')) is null,
  'frozen event untouched';
 assert pg_temp.ev('lst-1')<>pg_temp.ev('lst-2'), 'redirect to a list page is not a twin';

 -- «Шерлок»: лишається та, чия адреса — кінцева, хоч вона й молодша; збереження переходять.
 assert (select merged_into from public.events where id=current_setting('test.sh_old')::uuid)
        =current_setting('test.sh_new')::uuid, 'older tombstoned, the current url wins';
 assert exists (select 1 from public.saved_events where event_id=current_setting('test.sh_new')::uuid and user_id=a),
  'sherlock save moved';
 assert (select state from private.event_state where event_id=current_setting('test.sh_new')::uuid)='cancelled',
  'state of the kept event from both pages';
end $$;

-- Повтор нічого не додає.
select private.record_offer_checks(jsonb_build_array(pg_temp.chk('old-1','https://example.invalid/new-1','scheduled')));
do $$ begin
 assert (select count(*) from private.event_merges where into_id=current_setting('test.live')::uuid)=1, 'no second merge';
end $$;

-- ── 2. Черга від'єднання.
-- K: жива пропозиція А + знята Б з чужою сторінкою (дата в slug ≠ дата сеансу). M: та сама чужа сторінка — єдина
-- пропозиція. W: обидві пропозиції зняті. N: чужа сторінка, але пропозиція жива. P: чужа, але сторінка потім показала
-- наш сеанс. Q: конфлікт.
select set_config('test.t2',(current_setting('test.t')::timestamptz+interval '5 days')::text,true),
 set_config('test.slug',to_char((current_setting('test.t')::timestamptz+interval '9 days') at time zone 'Europe/Kyiv','YYYY-MM-DD'),true);
select pg_temp.ingest(jsonb_build_array(
 pg_temp.w('test_clean_a','k-live','Тест Концерт',current_setting('test.t2')::timestamptz),
 pg_temp.c('test_clean_b','k-'||current_setting('test.slug'),'Тест Концерт',current_setting('test.t2')::timestamptz,'test_clean_a','k-live'),
 pg_temp.w('test_clean_b','m-'||current_setting('test.slug'),'Тест Соло',current_setting('test.t2')::timestamptz),
 pg_temp.w('test_clean_a','w-gone','Тест Ве',current_setting('test.t2')::timestamptz+interval '4 hours'),
 pg_temp.c('test_clean_b','w-'||current_setting('test.slug'),'Тест Ве',current_setting('test.t2')::timestamptz+interval '4 hours','test_clean_a','w-gone'),
 pg_temp.w('test_clean_a','n-live','Тест Нуль',current_setting('test.t2')::timestamptz+interval '1 hour'),
 pg_temp.c('test_clean_b','n-'||current_setting('test.slug'),'Тест Нуль',current_setting('test.t2')::timestamptz+interval '1 hour','test_clean_a','n-live'),
 pg_temp.w('test_clean_a','p-live','Тест Пе',current_setting('test.t2')::timestamptz+interval '2 hours'),
 pg_temp.c('test_clean_b','p-'||current_setting('test.slug'),'Тест Пе',current_setting('test.t2')::timestamptz+interval '2 hours','test_clean_a','p-live'),
 pg_temp.w('test_clean_a','q-live','Тест Кю',current_setting('test.t2')::timestamptz+interval '3 hours'),
 pg_temp.c('test_clean_b','q-agent','Тест Кю',current_setting('test.t2')::timestamptz+interval '3 hours','test_clean_a','q-live')));
select pg_temp.vanish(u) from unnest(array['k-'||current_setting('test.slug'),'m-'||current_setting('test.slug'),
 'p-'||current_setting('test.slug'),'q-agent','w-gone','w-'||current_setting('test.slug')]) u;
select set_config('test.k',pg_temp.ev('k-live')::text,true), set_config('test.n',pg_temp.ev('n-live')::text,true);
insert into public.saved_events(user_id,event_id) values (current_setting('test.a')::uuid,current_setting('test.k')::uuid);
-- Конфлікт (двічі поспіль) кладе в чергу перерахунок стану; тут — одразу рядком.
insert into private.offer_detach_queue(offer_id,event_id,evidence) values
 (pg_temp.offer('q-agent'),pg_temp.ev('q-agent'),jsonb_build_object('says','cancelled','linked','agent')),
 (pg_temp.offer('p-'||current_setting('test.slug')),pg_temp.ev('p-live'),jsonb_build_object('detach','misattached'));

-- Сторінка чужого сеансу: один сеанс на дату зі slug.
select private.record_offer_checks(jsonb_build_array(
 pg_temp.chk('k-'||current_setting('test.slug'),null,'moved_silent',
  jsonb_build_object('new_start',current_setting('test.t')::timestamptz+interval '9 days','name','Тест Концерт')),
 pg_temp.chk('m-'||current_setting('test.slug'),null,'moved_silent',
  jsonb_build_object('new_start',current_setting('test.t')::timestamptz+interval '9 days','name','Тест Соло')),
 pg_temp.chk('w-'||current_setting('test.slug'),null,'moved_silent',
  jsonb_build_object('new_start',current_setting('test.t')::timestamptz+interval '9 days','name','Тест Ве')),
 pg_temp.chk('n-'||current_setting('test.slug'),null,'moved_silent',
  jsonb_build_object('new_start',current_setting('test.t')::timestamptz+interval '9 days','name','Тест Нуль')),
 pg_temp.chk('p-'||current_setting('test.slug'),null,'scheduled')));

do $$ declare k uuid := current_setting('test.k')::uuid; x uuid := pg_temp.offer('k-'||current_setting('test.slug'));
 v uuid; a uuid := current_setting('test.a')::uuid; begin
 assert (select resolution from private.offer_detach_queue where offer_id=x)='detached', 'misattached detached';
 v := pg_temp.ev('k-'||current_setting('test.slug'));
 assert v<>k, 'offer left the event';
 assert (select linked from public.event_offers where id=x)='manual', 'frozen for the pipeline';
 assert (select import_status from public.events where id=k)='live', 'event still live';
 assert jsonb_array_length(private.event_offers_json(k,'https://example.invalid/k-live'))=1
    and private.event_offers_json(k,'https://example.invalid/k-live')->0->>'url'='https://example.invalid/k-live',
  'wrong seller gone from the list (phase 4)';
 assert exists (select 1 from public.saved_events where event_id=k and user_id=a)
    and not exists (select 1 from public.saved_events where event_id=v), 'saves stay on the old event';
 assert (select import_status from public.events where id=v)='withdrawn'
    and not (select private.is_discoverable(origin,import_status,quality) from public.events where id=v),
  'detached event is invisible';

 assert (select resolution from private.offer_detach_queue where offer_id=pg_temp.offer('m-'||current_setting('test.slug'))) is null
    and exists (select 1 from private.offer_detach_queue where offer_id=pg_temp.offer('m-'||current_setting('test.slug'))),
  'alone: queued, waits';
 assert (select resolution from private.offer_detach_queue where offer_id=pg_temp.offer('w-'||current_setting('test.slug'))) is null
    and pg_temp.ev('w-'||current_setting('test.slug'))=pg_temp.ev('w-gone'), 'no other live offer: waits';
 assert (select resolution from private.offer_detach_queue where offer_id=pg_temp.offer('n-'||current_setting('test.slug'))) is null
    and pg_temp.ev('n-'||current_setting('test.slug'))=current_setting('test.n')::uuid, 'live offer waits for a human';
 assert exists (select 1 from private.shadow_report(1) where section='черга від''єднання'
                and label='людині · '||current_setting('test.n')), 'report asks a human about the live one';
 assert (select resolution from private.offer_detach_queue where offer_id=pg_temp.offer('p-'||current_setting('test.slug'))) is null
    and pg_temp.ev('p-'||current_setting('test.slug'))=pg_temp.ev('p-live'), 'page shows our session again: kept';
 assert (select resolution from private.offer_detach_queue where offer_id=pg_temp.offer('q-agent'))='detached'
    and pg_temp.ev('q-agent')<>pg_temp.ev('q-live'), 'conflict detached';
end $$;

-- Повтор: від'єднана лишається від'єднаною, у черзі той самий рядок.
select private.record_offer_checks(jsonb_build_array(
 pg_temp.chk('k-'||current_setting('test.slug'),null,'moved_silent',
  jsonb_build_object('new_start',current_setting('test.t')::timestamptz+interval '9 days','name','Тест Концерт'))));
-- Рукою: від'єднання живої позначає рядок.
select private.detach_offer(pg_temp.offer('n-'||current_setting('test.slug')));
select private.process_offer_detach_queue();
do $$ begin
 assert (select count(*) from private.offer_detach_queue where offer_id=pg_temp.offer('k-'||current_setting('test.slug')))=1,
  'one row per offer';
 assert (select count(*) from public.event_offers where event_id=pg_temp.ev('k-'||current_setting('test.slug')))=1,
  'detached once';
 assert (select resolution from private.offer_detach_queue where offer_id=pg_temp.offer('n-'||current_setting('test.slug')))='detached',
  'manual detach resolves the row';
 assert exists (select 1 from private.shadow_report(1) where section='черга від''єднання' and label='від''єднано за період' and n>=3),
  'report counts detached';
 assert not exists (select 1 from private.shadow_report(1) where section='черга від''єднання'
                    and (label like '%'||current_setting('test.k')||'%'
                         or label like '%'||pg_temp.ev('k-'||current_setting('test.slug'))||'%')), 'resolved rows leave the report';
end $$;

rollback;
select 'PASS: url twins merged (saves, sherlock, not list/minute/frozen), detach queue: misattached and conflict detached, alone/no-live/live/confirmed wait, manual resolves, report' as result;

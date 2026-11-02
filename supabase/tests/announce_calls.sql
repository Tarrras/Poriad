-- Запускати адміністратором бази. Усе відкочується. Ліміт «Вставити анонс»: 20 на годину з адреси (IPv6 — з мережі /64),
-- 300 на годину на всіх, старі виклики не рахуються й прибираються, клієнтам функція недоступна.
begin;
-- Справжні виклики з бази не мають заважати стелі.
delete from private.announce_calls;

do $$ begin
 for i in 1..20 loop assert public.announce_call('192.0.2.1'), 'call ' || i || ' of 20 passes'; end loop;
 assert not public.announce_call('192.0.2.1'), 'the 21st call in an hour is refused';
 assert (select count(*) = 20 from private.announce_calls where ip = '192.0.2.1'), 'a refused call is not recorded';
 assert public.announce_call('192.0.2.2') and public.announce_call('2001:db8::1'), 'other addresses, IPv6 too, are separate';
 begin perform public.announce_call('not an ip'); raise exception 'bad address accepted';
 exception when invalid_text_representation then null; end;
 -- IPv6: уся мережа /64 — одна адреса, сусідня /64 — інша.
 for i in 2..19 loop assert public.announce_call('2001:db8::' || to_hex(i)), 'IPv6 call ' || i; end loop;
 assert public.announce_call('2001:db8:0:0:ffff::1'), 'the 20th call from the same /64';
 assert not public.announce_call('2001:db8::abcd'), 'the 21st from the same /64 is refused';
 assert public.announce_call('2001:db8:0:1::1'), 'the next /64 is separate';
 assert (select count(distinct ip) = 2 from private.announce_calls where family(ip) = 6), 'stored as networks';
end $$;

-- Стеля на всіх: 300 викликів з різних адрес за годину — далі ніхто.
insert into private.announce_calls(ip)
select ('10.' || (i / 65536) || '.' || (i / 256 % 256) || '.' || (i % 256))::inet
from generate_series(1, 300 - (select count(*)::integer from private.announce_calls)) i;
do $$ begin
 assert not public.announce_call('198.51.100.1'), 'a fresh address is refused over the global ceiling';
end $$;
delete from private.announce_calls where ip << '10.0.0.0/8';

-- Година минула: адреса знову може, а старі рядки прибирає cron.
update private.announce_calls set at = now() - interval '61 minutes' where ip = '192.0.2.1';
do $$ begin
 assert public.announce_call('192.0.2.1'), 'an hour later the address may call again';
 assert private.forget_announce_calls() >= 20, 'old calls are forgotten';
 assert (select count(*) = 1 from private.announce_calls where ip = '192.0.2.1'), 'the fresh call stays';
 assert not has_function_privilege('anon', 'public.announce_call(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.announce_call(text)', 'execute')
  and has_function_privilege('service_role', 'public.announce_call(text)', 'execute'), 'only the function key calls it';
end $$;

rollback;

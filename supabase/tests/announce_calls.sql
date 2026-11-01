-- Запускати адміністратором бази. Усе відкочується. Ліміт «Вставити анонс»: 20 на годину з адреси, старі виклики не
-- рахуються й прибираються, клієнтам функція недоступна.
begin;
delete from private.announce_calls where ip in ('192.0.2.1', '192.0.2.2', '2001:db8::1');

do $$ begin
 for i in 1..20 loop assert public.announce_call('192.0.2.1'), 'call ' || i || ' of 20 passes'; end loop;
 assert not public.announce_call('192.0.2.1'), 'the 21st call in an hour is refused';
 assert (select count(*) = 20 from private.announce_calls where ip = '192.0.2.1'), 'a refused call is not recorded';
 assert public.announce_call('192.0.2.2') and public.announce_call('2001:db8::1'), 'other addresses, IPv6 too, are separate';
 begin perform public.announce_call('not an ip'); raise exception 'bad address accepted';
 exception when invalid_text_representation then null; end;
end $$;

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

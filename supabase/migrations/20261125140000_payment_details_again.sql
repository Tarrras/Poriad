-- «Ті самі реквізити» (docs/organizer-events.md): організатор онлайн-події надсилає реквізити кожному, хто подав
-- заявку. Щоб не набирати їх щоразу, застосунок і кабінет пропонують вставити в поле його останнє повідомлення з
-- реквізитами в цій події. Лише своє, лише організатору події; видалене й приховане модерацією — ні.
create function public.my_payment_details(p_event_id uuid) returns text
language sql stable security invoker set search_path='' as $$
 select m.body from public.event_messages m
 where m.event_id=p_event_id and m.author_id=auth.uid() and m.payment_details and m.thread_user_id is not null
 and m.deleted_at is null and m.hidden_at is null and private.organizes(p_event_id)
 order by m.created_at desc,m.id desc limit 1;
$$;

revoke all on function public.my_payment_details(uuid) from public,anon,authenticated;
grant execute on function public.my_payment_details(uuid) to authenticated;

-- Публічні обгортки — invoker, тож викликачу потрібен execute і на приватну реалізацію, як у
-- join_event. promote_waitlist без гранту: її кличуть лише definer-функції.
grant execute on function private.join_waitlist(uuid), private.leave_waitlist(uuid) to authenticated;

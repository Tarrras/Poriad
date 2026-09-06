-- The public wrappers are invokers, so the caller needs execute on the private implementation too,
-- exactly as join_event and leave_event already do. promote_waitlist stays ungranted: it is only
-- reached from inside definer functions, which run as the owner.
grant execute on function private.join_waitlist(uuid), private.leave_waitlist(uuid) to authenticated;

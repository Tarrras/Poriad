-- Аудит 2026-09-16, інформаційне: account_facts.status_note — нотатка модерації для колег, а не
-- для власника акаунта. Клієнт читає лише birth_date,status; колонковий грант закриває решту.
revoke select on public.account_facts from authenticated;
grant select (user_id, birth_date, status, updated_at) on public.account_facts to authenticated;

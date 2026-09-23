-- Доповнення до 20260923100200: публічний лістинг бакета знято, але власнику лишаємо SELECT своїх
-- файлів: Storage API може читати щойно вставлений рядок (INSERT … RETURNING), а без політики
-- SELECT RLS такий запит відхиляє — завантаження фото не ризикуємо. Anon і чужі шляхи — нічого.
drop policy if exists poruch_image_owner_read on storage.objects;
create policy poruch_image_owner_read on storage.objects for select to authenticated
 using (bucket_id='event-images' and split_part(name,'/',1)=(select auth.uid())::text);

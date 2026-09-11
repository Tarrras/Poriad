-- Восьма категорія: comedy.
--
-- Стендап досі падав у `art`, поруч із виставами, виставками й кіно. Формально це не помилка —
-- `art` і є найближчою скринькою в наявному словнику. Але з появою internet-bilet стендап став
-- помітною часткою каталогу (33 ComedyEvent у Києві на 11 майданчиках), і головне — це та
-- пропозиція, на яку ходить цільова аудиторія продукту, 22–35. Змішувати її з ляльковим театром
-- означає ховати найпривабливіше під найзагальнішим фільтром.
--
-- Ціна рішення чесно велика: перелік категорій зашитий не лише тут, а й у спільному домені та
-- в семи місцях клієнтів (кольори, відтінки, іконки, мітки на обох платформах). Ця міграція —
-- лише перша з них; без клієнтських правок нова категорія показуватиметься без значка.
--
-- Порядок важливий: спершу розширюємо CHECK, і лише потім переносимо наявні події. Інакше
-- backfill упреться в старе обмеження.

alter table public.events drop constraint events_category_check;
alter table public.events add constraint events_category_check
 check (category in ('music','sport','art','food','games','outdoors','social','comedy'));

-- Уподобання користувача зберігають ті самі мітки, тож і тут перелік має збігатися — інакше
-- людина не змогла б підписатися на нову категорію.
alter table public.user_preferences drop constraint user_preferences_categories_check;
alter table public.user_preferences add constraint user_preferences_categories_check
 check (categories <@ array['music','sport','art','food','games','outdoors','social','comedy']::text[]);

-- Backfill: наявні імпортовані події, які насправді є стендапом чи гумористичним шоу.
--
-- Без цього нова категорія стартує майже порожньою й виглядає зламаною. Беремо лише `import` і
-- лише за явними словами в заголовку: спільнотні події створювали люди, і мовчки перекладати їх
-- з категорії, яку вони обрали самі, не можна.
update public.events
set category = 'comedy', updated_at = now()
where origin = 'import'
  and category = 'art'
  and (
    title ~* '(стендап|стенд-ап|stand.?up|імпровіз|импровиз|відкритий мікрофон|open mic)'
    or title ~* '(комік|comedy|гумористичн|жарт)'
  );

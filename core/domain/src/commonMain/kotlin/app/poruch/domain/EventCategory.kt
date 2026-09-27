package app.poruch.domain

/**
 * Категорія події. [key] — те, що лежить у `events.category`; CHECK-обмеження на сервері тримає той самий словник.
 * Рядок живе лише на межі з сервером і сховищем, всередині — цей тип: `when` без `else` змушує нову категорію
 * отримати колір, іконку й теги оцінки.
 */
enum class EventCategory(val key: String) {
    MUSIC("music"), SPORT("sport"), ART("art"), FOOD("food"), GAMES("games"), OUTDOORS("outdoors"),
    SOCIAL("social"), COMEDY("comedy"), KIDS("kids"),
    // Додані за звітом про прогалини: екскурсії тонули в «природі», конференції — у «зустрічах».
    TOURS("tours"), CONFERENCE("conference"),

    /**
     * Сервер новіший за застосунок і вже знає категорію, якої тут нема. Подію показуємо загальним
     * виглядом; у вибір (редактор, фільтри, інтереси) ця категорія не потрапляє, на сервер не йде.
     */
    UNKNOWN("");

    companion object {
        /** Те, що людина може обрати: усе, крім [UNKNOWN]. */
        val selectable: List<EventCategory> = entries - UNKNOWN

        fun fromKey(key: String?): EventCategory = selectable.firstOrNull { it.key == key } ?: UNKNOWN
    }
}

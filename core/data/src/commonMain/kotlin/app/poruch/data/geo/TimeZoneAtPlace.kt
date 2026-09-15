package app.poruch.data.geo

/**
 * Часовий пояс за координатами. Подія зберігає пояс місця, а не автора. Кожна платформа
 * визначає його по-своєму; null — не змогли, лишається пояс пристрою.
 */
expect suspend fun timeZoneAt(latitude: Double, longitude: Double): String?

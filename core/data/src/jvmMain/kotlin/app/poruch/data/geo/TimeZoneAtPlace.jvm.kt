package app.poruch.data.geo

/** У тестах геокодера нема: пояс лишається переданим. */
actual suspend fun timeZoneAt(latitude: Double, longitude: Double): String? = null

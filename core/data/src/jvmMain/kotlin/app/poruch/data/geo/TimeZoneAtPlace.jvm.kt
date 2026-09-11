package app.poruch.data.geo

/** Тести не мають ані геокодера, ані потреби в ньому: пояс лишається тим, що передали. */
actual suspend fun timeZoneAt(latitude: Double, longitude: Double): String? = null

package app.poruch.domain

/** Вид артиста з `artists.kind`. Сервер буває не знає виду: тоді null, а підписом нічого не показуємо. */
enum class ArtistKind(val key: String) {
    PERSON("person"), GROUP("group"), COMPANY("company"), SHOW("show");

    companion object {
        fun fromKey(key: String?): ArtistKind? = entries.firstOrNull { it.key == key }
    }
}

/** Роль у події з `event_artists.role`. Порядок складу вже серверний. */
enum class ArtistRole(val key: String) {
    HEADLINER("headliner"), SUPPORT("support"), HOST("host");

    companion object {
        /** Невідома роль (сервер новіший за застосунок) — звичайний учасник. */
        fun fromKey(key: String?): ArtistRole = entries.firstOrNull { it.key == key } ?: SUPPORT
    }
}

/**
 * Хто виступає в події: людина, гурт, ґастролююча трупа чи шоу-бренд (docs/artists-client-brief.md). Театр-майданчик
 * сюди не потрапляє, його сервер вже відсіяв.
 */
data class Artist(val id: String, val name: String, val kind: ArtistKind? = null, val role: ArtistRole = ArtistRole.SUPPORT)

/** Рядок видачі `search_artists`. [upcoming] — скільки майбутніх подій. */
data class ArtistHit(val id: String, val name: String, val kind: ArtistKind? = null, val upcoming: Int = 0)

package app.poruch.domain

/**
 * The numbers business logic used to spell out inline. They live here because the server enforces
 * the same limits: when a migration moves one, exactly one constant moves with it.
 */
object EventRules {
    /** The category vocabulary. The server's CHECK constraint holds the same seven values. */
    val categories = listOf("music", "sport", "art", "food", "games", "outdoors", "social")

    val titleLength = 3..120
    val descriptionLength = 10..5000
    val capacity = 1..10_000

    fun isCategory(value: String) = value in categories
}

/** Account input limits, matched to what Supabase Auth itself accepts. */
object AccountRules {
    val nameLength = 2..60
    const val MIN_PASSWORD = 8
    private val email = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

    fun isEmail(value: String) = email.matches(value.trim())
    fun isPassword(value: String) = value.length >= MIN_PASSWORD
    fun isName(value: String) = value.trim().length in nameLength
}

/** What Storage accepts for an event cover. The bucket policy enforces the same pair. */
object ImageRules {
    const val MAX_BYTES = 5 * 1024 * 1024
    /** MIME type to file extension; a type absent here is not an image we store. */
    val extensions = mapOf("image/jpeg" to "jpg", "image/png" to "png", "image/webp" to "webp")
}

/** Pacing and limits of search. Tuned for a hand on a map, not for the server. */
object DiscoveryRules {
    /** The server's page size. At this many results the view is too wide to be useful. */
    const val RESULT_CAP = 300
    const val SEARCH_TEXT_LIMIT = 120
    /** Long enough to outlast typing, short enough to feel like the map is keeping up. */
    const val SEARCH_DEBOUNCE_MS = 300L
    /** Geocoding is a third-party call, so it waits longer than our own search. */
    const val CITY_DEBOUNCE_MS = 400L
    const val MIN_CITY_QUERY = 2
}

/**
 * Where the map opens before anything is known about the user. A default, not a constant —
 * [AppConfig] carries it so a build for another region changes one value, not the code.
 */
data class HomeLocation(
    val city: String,
    val latitude: Double,
    val longitude: Double,
    /** Half-height and half-width of the first viewport, in degrees. */
    val spanLatitude: Double = 0.15,
    val spanLongitude: Double = 0.25
) {
    val south get() = latitude - spanLatitude
    val north get() = latitude + spanLatitude
    val west get() = longitude - spanLongitude
    val east get() = longitude + spanLongitude

    companion object {
        val Kyiv = HomeLocation("Київ", 50.4501, 30.5234)
    }
}

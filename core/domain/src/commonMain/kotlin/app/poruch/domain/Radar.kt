package app.poruch.domain

/** Найближча подія артиста в місті людини (docs/artist-radar.md). [startsAt] — ISO-8601, як у картці. */
data class RadarEvent(val eventId: String, val title: String, val startsAt: String, val timeZone: String) {
    /** Як у картці: капс і лапки причесані ([TitleRules]). */
    val displayTitle: String by lazy { TitleRules.display(title) }
}

/** Інше місто туру і найближча дата там. */
data class RadarCity(val city: String, val startsAt: String)

/** Рядок «Ваші артисти»: що в місті людини ([next], [inCity]) і де ще ([elsewhere], до трьох міст). */
data class ArtistRadar(
    val artistId: String,
    val name: String,
    val kind: ArtistKind?,
    val next: RadarEvent?,
    val inCity: Int,
    val elsewhere: List<RadarCity>
)

/** Хто їде в місто — для «Кого слухаєте?»: [upcoming] вечорів попереду (прокат — один), [firstAt] — найближчий. */
data class PopularArtist(val artistId: String, val name: String, val kind: ArtistKind?, val upcoming: Int, val firstAt: String?)

/** Артист, за яким гість стежить без акаунта. */
data class GuestArtist(val id: String, val name: String)

/**
 * Артисти гостя: на телефоні, як закладки (`device:artists`); після входу переїжджають в акаунт. Назви методів свої,
 * а не `read`/`write`: Kotlin/Native інакше перейменував би їх у протоколах, які вже реалізує iOS.
 */
interface GuestArtistStore {
    fun artists(): List<GuestArtist>
    fun saveArtists(artists: List<GuestArtist>)
}

object RadarRules {
    /** Скільки рядків «Ваші артисти» на головній; решта — «Усі N». */
    const val HOME_ROWS = 5

    /** Скільки артистів у шторці «Кого слухаєте?». */
    const val PICKER = 24

    /**
     * Порядок «Ваші артисти»: ті, хто їде в місто, найближчі першими; далі тур іншими містами за найближчою датою;
     * далі без анонсів — за іменем.
     */
    fun order(rows: List<ArtistRadar>): List<ArtistRadar> = rows.sortedWith(
        compareBy<ArtistRadar>(
            { if (it.next != null) 0 else if (it.elsewhere.isNotEmpty()) 1 else 2 },
            { it.next?.startsAt ?: it.elsewhere.firstOrNull()?.startsAt.orEmpty() },
            { it.name.lowercase() }
        )
    )
}

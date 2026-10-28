package app.poruch.domain

/** Найближча подія артиста в місті людини (docs/artist-radar.md). [startsAt] — ISO-8601, як у картці; [category] — плитка рядка. */
data class RadarEvent(
    val eventId: String,
    val title: String,
    val startsAt: String,
    val timeZone: String,
    val category: EventCategory = EventCategory.UNKNOWN
) {
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

/** Вечір у місті людини і хто з її артистів на ньому: рядок «Ваше» на подію, а не на кожного артиста. */
data class RadarDate(val event: RadarEvent, val artists: List<String>)

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
    /** Скільки дат артистів «Ваше» показує щонайбільше; решта — на екрані «Ви стежите». */
    const val HOME_ROWS = 3

    /**
     * Дати в місті людини по одній на подію, найближчі першими: троє артистів одного стендапу — один рядок з усіма
     * іменами, а не три рядки з тією самою назвою (критика довжини 28.10).
     */
    fun dates(rows: List<ArtistRadar>): List<RadarDate> =
        rows.mapNotNull { row -> row.next?.let { it to row.name } }
            .groupBy { it.first.eventId }
            .map { (_, pairs) -> RadarDate(pairs.first().first, pairs.map { it.second }.distinct()) }
            .sortedBy { it.event.startsAt }

    /** Скільки артистів у шторці «Кого слухаєте?». */
    const val PICKER = 24
}

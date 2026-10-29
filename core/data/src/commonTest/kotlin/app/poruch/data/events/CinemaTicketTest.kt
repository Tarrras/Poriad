package app.poruch.data.events

import app.poruch.domain.DuplicateEvents
import app.poruch.domain.EventSeries
import app.poruch.domain.TicketMatch
import app.poruch.domain.TicketReader
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.serialization.json.Json
import kotlin.test.*

/**
 * Квиток Multiplex проти справжньої видачі dev 28.10 (`discover_events(Київ, p_cinema=>true)`, рядки «Праймтайм»):
 * розбір рядків, згортання, як у застосунку, і `TicketMatch`. 30.10 о 19:20 той самий фільм іде в Respublika Park,
 * Lavina й Komod — квиток має знайти свій зал (docs/cinema-import.md, рішення 4).
 */
class CinemaTicketTest {
    private val json = Json { ignoreUnknownKeys = true }
    private val kyiv = TimeZone.of("Europe/Kyiv")

    private val rows = listOf(
        """["7c98587f-1590-5a0e-b64b-0b6a2c2a3a6f",50.453408,30.598488,"cinema","2026-10-30T17:20:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Komod"]""",
        """["f60ea17f-0990-5ff6-af5d-e432bfc01083",50.496766,30.357806,"cinema","2026-10-30T16:10:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Lavina"]""",
        """["1b57d14d-b9eb-53f3-bdff-6279e01262b7",50.496766,30.357806,"cinema","2026-10-30T17:20:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Lavina"]""",
        """["732f6c8e-a03e-5459-a0b2-ce99ae44a04a",50.375563,30.448754,"cinema","2026-10-28T18:40:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park"]""",
        """["0051a6a3-c68a-59cd-b016-154de8c4be1f",50.375563,30.448754,"cinema","2026-10-29T10:30:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park"]""",
        """["ac3d67a8-a7e7-5424-b9e9-746097f34f41",50.375563,30.448754,"cinema","2026-10-29T12:20:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park"]""",
        """["a53a2769-0c55-558f-a5e1-080254e692b8",50.375563,30.448754,"cinema","2026-10-29T15:20:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park"]""",
        """["88cf935c-d0d9-5c82-9597-64bef46db860",50.375563,30.448754,"cinema","2026-10-29T17:20:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park"]""",
        """["b7719066-b2aa-597f-aadc-0480b63d2e8d",50.375563,30.448754,"cinema","2026-10-30T10:30:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park"]""",
        """["07716482-a6de-567f-b8c8-bf04b8f9020e",50.375563,30.448754,"cinema","2026-10-30T12:20:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park"]""",
        """["a40b9f9a-43b7-5c5d-8cc8-5b9787c0f167",50.375563,30.448754,"cinema","2026-10-30T15:20:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park"]""",
        """["36153863-2c43-5172-813c-0002401979b3",50.375563,30.448754,"cinema","2026-10-30T17:20:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park"]""",
        """["be01c7c5-609f-5b50-9599-211106ff685a",50.503878,30.417157,"cinema","2026-10-30T17:00:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Retroville"]""",
        """["894dde75-713d-5952-a353-7bc7545d77b7",50.340956,30.551132,"cinema","2026-10-30T18:00:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Атмосфера"]""",
        """["f689bd49-15c3-529e-aec1-cb7a9eaa8eff",50.504666,30.472166,"cinema","2026-10-30T17:00:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Караван"]""",
        """["ea8ceeb7-f2d9-5c8f-a62d-c9433c44ff6c",50.455318,30.635022,"cinema","2026-10-30T17:00:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Проспект"]""",
        """["258690b1-f7b3-58e9-b8f9-528dc8deeed0",50.44545,30.52057,"cinema","2026-10-30T17:40:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex ЦУМ"]""",
        """["9906eff8-78ef-532f-8bf4-5eb6fe66ad16",50.404903,30.611872,"cinema","2026-10-30T17:30:00+00:00","Europe/Kyiv","Праймтайм","import","planeta_kino",null,0,0,"Планета Кіно River Mall"]""",
        """["dffcf1a9-0371-50dd-a399-4a773686e0f7",50.486248,30.519073,"cinema","2026-10-30T16:50:00+00:00","Europe/Kyiv","Праймтайм","import","planeta_kino",null,0,0,"Планета Кіно Блокбастер"]""",
        """["77941958-4612-50ad-96bf-cbde7b545e98",50.486248,30.519073,"cinema","2026-10-30T17:00:00+00:00","Europe/Kyiv","Праймтайм","import","planeta_kino",null,0,0,"Планета Кіно Блокбастер"]""",
    )

    /** Індекс, як його бачить `PoruchApp.ticketMatch`: дублі продавців, потім прокати. */
    private val index = EventSeries.fold(DuplicateEvents.fold(
        json.decodeFromString<DiscoveryEnvelope>("""{"total":${rows.size},"truncated":false,"index":[${rows.joinToString(",")}],"cards":[]}""")
            .domain().index
    ))

    private fun ticket(place: String?) = TicketReader.read(
        listOfNotNull(
            "MULTIPLEX", "Електронний квиток", "Фільм: Праймтайм", place?.let { "Кінотеатр: $it" }, "Зал: 5",
            "Дата: 30.10.2026", "Початок: 19:20", "Ряд 7 Місце 12", "Ціна: 250 грн", "Дата покупки: 28.10.2026 12:31"
        ).joinToString("\n"),
        LocalDate(2026, 10, 28)
    )

    @Test fun theTicketOpensItsOwnSession() {
        assertEquals(10, index.size, "10 залів — 10 карток: прокати Respublika Park, Lavina й Блокбастера згорнуто")
        assertEquals("36153863-2c43-5172-813c-0002401979b3", TicketMatch.match(ticket("Multiplex Respublika Park"), index, kyiv),
            "сеанс 30.10 19:20 у Respublika Park, а не Lavina чи Komod тієї ж хвилини")
        assertEquals("1b57d14d-b9eb-53f3-bdff-6279e01262b7", TicketMatch.match(ticket("Multiplex Lavina"), index, kyiv))
        assertEquals("77941958-4612-50ad-96bf-cbde7b545e98", TicketMatch.match(ticket("Планета Кіно Блокбастер"), index, kyiv),
            "з двох сеансів Блокбастера в межах вікна — 19:00, ближчий до 19:20")
    }

    @Test fun withoutTheHallItStaysOffTheListing() {
        assertNull(TicketMatch.match(ticket(null), index, kyiv), "10 залів у межах 45 хвилин — не вгадуємо")
    }

    /**
     * Сервер віддає кінопрокат уже зібраним: рядок на «фільм × зал», сеанси — 14-та позиція. Справжня відповідь dev
     * 28.10 на `p_text=>'Праймтайм'`, `p_from`/`p_to` — 30.10 за Києвом: фільтр дати звужує й сеанси.
     */
    private val serverRows = listOf(
        """["e3f0e53f-7b5c-532b-9460-eca48d676b91",50.453408,30.598488,"cinema","2026-10-30T11:40:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Komod",[["e3f0e53f-7b5c-532b-9460-eca48d676b91","2026-10-30T11:40:00+00:00"],["7c98587f-1590-5a0e-b64b-0b6a2c2a3a6f","2026-10-30T17:20:00+00:00"]]]""",
        """["513187e3-a9a2-55fa-b831-3ec1d0d43b5a",50.496766,30.357806,"cinema","2026-10-30T12:40:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Lavina",[["513187e3-a9a2-55fa-b831-3ec1d0d43b5a","2026-10-30T12:40:00+00:00"],["3e527b9c-51d7-5472-9bbc-6c7377986f50","2026-10-30T15:00:00+00:00"],["f60ea17f-0990-5ff6-af5d-e432bfc01083","2026-10-30T16:10:00+00:00"],["1b57d14d-b9eb-53f3-bdff-6279e01262b7","2026-10-30T17:20:00+00:00"]]]""",
        """["b7719066-b2aa-597f-aadc-0480b63d2e8d",50.375563,30.448754,"cinema","2026-10-30T10:30:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Respublika Park",[["b7719066-b2aa-597f-aadc-0480b63d2e8d","2026-10-30T10:30:00+00:00"],["07716482-a6de-567f-b8c8-bf04b8f9020e","2026-10-30T12:20:00+00:00"],["a40b9f9a-43b7-5c5d-8cc8-5b9787c0f167","2026-10-30T15:20:00+00:00"],["36153863-2c43-5172-813c-0002401979b3","2026-10-30T17:20:00+00:00"]]]""",
        """["d779fec4-e254-553a-9976-db9e4ea873e8",50.503878,30.417157,"cinema","2026-10-30T12:10:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Retroville",[["d779fec4-e254-553a-9976-db9e4ea873e8","2026-10-30T12:10:00+00:00"],["93fc8c47-e40c-5abc-9b25-fa09338cdf86","2026-10-30T14:30:00+00:00"],["be01c7c5-609f-5b50-9599-211106ff685a","2026-10-30T17:00:00+00:00"]]]""",
        """["894dde75-713d-5952-a353-7bc7545d77b7",50.340956,30.551132,"cinema","2026-10-30T18:00:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Атмосфера",[["894dde75-713d-5952-a353-7bc7545d77b7","2026-10-30T18:00:00+00:00"]]]""",
        """["d054652e-6587-5f2c-88da-d15789a113be",50.504666,30.472166,"cinema","2026-10-30T14:00:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Караван",[["d054652e-6587-5f2c-88da-d15789a113be","2026-10-30T14:00:00+00:00"],["f689bd49-15c3-529e-aec1-cb7a9eaa8eff","2026-10-30T17:00:00+00:00"]]]""",
        """["7a3274b2-30c6-50f4-89b2-3a548b1edf1d",50.455318,30.635022,"cinema","2026-10-30T14:40:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex Проспект",[["7a3274b2-30c6-50f4-89b2-3a548b1edf1d","2026-10-30T14:40:00+00:00"],["ea8ceeb7-f2d9-5c8f-a62d-c9433c44ff6c","2026-10-30T17:00:00+00:00"]]]""",
        """["af84b00f-b616-5557-a6e2-15c6cd978e9c",50.44545,30.52057,"cinema","2026-10-30T14:00:00+00:00","Europe/Kyiv","Праймтайм","import","multiplex",null,0,0,"Multiplex ЦУМ",[["af84b00f-b616-5557-a6e2-15c6cd978e9c","2026-10-30T14:00:00+00:00"],["258690b1-f7b3-58e9-b8f9-528dc8deeed0","2026-10-30T17:40:00+00:00"]]]""",
        """["fd689a9a-e747-5778-b50c-48257d149e9a",50.507859,30.498219,"cinema","2026-10-30T14:40:00+00:00","Europe/Kyiv","Праймтайм","import","planeta_kino",null,0,0,"Планета Кіно Dream Yellow",[["fd689a9a-e747-5778-b50c-48257d149e9a","2026-10-30T14:40:00+00:00"]]]""",
        """["9906eff8-78ef-532f-8bf4-5eb6fe66ad16",50.404903,30.611872,"cinema","2026-10-30T17:30:00+00:00","Europe/Kyiv","Праймтайм","import","planeta_kino",null,0,0,"Планета Кіно River Mall",[["9906eff8-78ef-532f-8bf4-5eb6fe66ad16","2026-10-30T17:30:00+00:00"]]]""",
        """["b67cf19f-5bde-5123-bdaf-00332f240c0b",50.486248,30.519073,"cinema","2026-10-30T11:00:00+00:00","Europe/Kyiv","Праймтайм","import","planeta_kino",null,0,0,"Планета Кіно Блокбастер",[["b67cf19f-5bde-5123-bdaf-00332f240c0b","2026-10-30T11:00:00+00:00"],["f9e4a9df-ba84-5e75-8a44-4f80e8ed7e95","2026-10-30T12:00:00+00:00"],["dffcf1a9-0371-50dd-a399-4a773686e0f7","2026-10-30T16:50:00+00:00"],["77941958-4612-50ad-96bf-cbde7b545e98","2026-10-30T17:00:00+00:00"]]]""",
    )

    @Test fun serverRunsOpenTheSameSession() {
        val runs = EventSeries.fold(DuplicateEvents.fold(
            json.decodeFromString<DiscoveryEnvelope>("""{"total":${serverRows.size},"truncated":false,"index":[${serverRows.joinToString(",")}],"cards":[]}""")
                .domain().index
        ))
        assertEquals(11, runs.size, "рядок на зал — картка на зал")
        assertEquals(4, runs.single { it.place == "Multiplex Respublika Park" }.sessions.size)
        assertTrue(runs.single { it.place == "Multiplex Атмосфера" }.sessions.isEmpty(), "один сеанс — не прокат")
        assertEquals("36153863-2c43-5172-813c-0002401979b3", TicketMatch.match(ticket("Multiplex Respublika Park"), runs, kyiv))
        assertEquals("1b57d14d-b9eb-53f3-bdff-6279e01262b7", TicketMatch.match(ticket("Multiplex Lavina"), runs, kyiv))
        assertEquals("77941958-4612-50ad-96bf-cbde7b545e98", TicketMatch.match(ticket("Планета Кіно Блокбастер"), runs, kyiv))
        assertNull(TicketMatch.match(ticket(null), runs, kyiv))
    }
}

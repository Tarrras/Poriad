package app.poruch.data.events

import app.poruch.domain.ArtistKind
import app.poruch.domain.ArtistRole
import app.poruch.domain.EventStatus
import app.poruch.domain.FollowKind
import app.poruch.domain.ImportStatus
import app.poruch.domain.Membership
import kotlinx.serialization.json.Json
import kotlin.test.*

/** Плоский рядок `event_result` розпадається на кімнату або оголошення тут, і далі `origin` ніхто не бачить. */
class EventDtoTest {
    private val json = Json { ignoreUnknownKeys = true; isLenient = false }

    private fun row(vararg extra: Pair<String, String>): String {
        val base = linkedMapOf(
            "id" to "\"e1\"", "title" to "\"Подія\"", "description" to "\"опис\"",
            "category" to "\"music\"", "city" to "\"Київ\"", "address" to "\"Поділ\"",
            "starts_at" to "\"2030-09-06T19:00:00Z\"", "ends_at" to "\"2030-09-06T22:00:00Z\"",
            "time_zone" to "\"Europe/Kyiv\"", "status" to "\"published\"",
            "latitude" to "50.45", "longitude" to "30.52"
        )
        extra.forEach { (k, v) -> base[k] = v }
        return base.entries.joinToString(",", "{", "}") { "\"${it.key}\":${it.value}" }
    }

    private fun parse(vararg extra: Pair<String, String>) =
        json.decodeFromString<EventDto>(row(*extra)).domain()

    @Test fun anImportedRowBecomesAListingAndNothingElse() {
        val event = parse(
            "origin" to "\"import\"", "organizer_id" to "null", "organizer_name" to "\"Karabas\"",
            "source_name" to "\"Karabas\"", "canonical_url" to "\"https://kyiv.karabas.com/e/1\"",
            "import_status" to "\"live\"", "price_min" to "350", "is_free" to "false",
            // Старий сервер віддає одиницю: до екранів вона долетіти не має.
            "capacity" to "1", "attendee_count" to "0"
        )
        assertNull(event.gathering)
        assertFalse(event.isCommunity)
        assertEquals("Karabas", event.listing?.sourceName)
        assertEquals("https://kyiv.karabas.com/e/1", event.listing?.canonicalUrl)
        assertEquals(350.0, event.listing?.priceMin)
        assertEquals(ImportStatus.LIVE, event.listing?.status)
    }

    @Test fun aCommunityRowBecomesARoomAndNothingElse() {
        val event = parse(
            "organizer_id" to "\"u1\"", "organizer_name" to "\"Оля\"", "capacity" to "10",
            "attendee_count" to "3", "joined" to "true", "membership" to "\"approved\"",
            "min_age" to "21", "approval_required" to "true"
        )
        assertNull(event.listing)
        assertEquals("u1", event.organizerId)
        assertEquals(7, event.gathering?.seatsLeft)
        assertTrue(event.gathering!!.joined)
        assertEquals(Membership.APPROVED, event.gathering!!.membership)
        assertTrue(event.gathering!!.hasAgeLimit)
        assertTrue(event.gathering!!.approvalRequired)
        assertEquals(EventStatus.PUBLISHED, event.status)
    }

    /** Афіша без місткості, як віддає сервер після 20260907150000. */
    @Test fun aListingWithoutCapacityParsesCleanly() {
        val event = parse("origin" to "\"import\"", "capacity" to "null", "source_name" to "\"concert.ua\"")
        assertNull(event.gathering)
        assertEquals("concert.ua", event.listing?.sourceName)
    }

    /** Зіпсований спільнотний рядок стає подією без дій, а список не падає. */
    @Test fun abrokenCommunityRowYieldsAnEventWithNeitherFace() {
        val event = parse("organizer_id" to "\"u1\"", "capacity" to "null")
        assertNull(event.gathering)
        assertNull(event.listing)
        assertNull(event.publisherName)
    }

    /** База без міграції імпорту не віддає `origin`: усе там спільнотне. */
    @Test fun anOlderServerWithoutOriginStillReadsAsCommunity() {
        val event = parse("organizer_id" to "\"u1\"", "organizer_name" to "\"Оля\"", "capacity" to "10")
        assertNotNull(event.gathering)
        assertNull(event.listing)
    }

    /** Картка афіші з міграції місць несе заклад; підпис картки бере його назву замість адреси. */
    @Test fun aListingCarriesItsPlace() {
        val event = parse(
            "origin" to "\"import\"", "source_name" to "\"Karabas\"",
            "place_id" to "\"p1\"", "place_name" to "\"Малевич\""
        )
        assertEquals("p1", event.placeId)
        assertEquals("Малевич", event.placeName)
        assertEquals("Малевич", event.placeLabel)
    }

    /** Спільнотна подія закладу не має: `jsonb_strip_nulls` поля не шле, підпис — адреса. */
    @Test fun aRowWithoutPlaceFallsBackToAddress() {
        val event = parse("origin" to "\"import\"", "source_name" to "\"Karabas\"")
        assertNull(event.placeId)
        assertEquals("Поділ", event.placeLabel)
    }

    /** Кеш, записаний до міграції місць: старі картки читаються, заклад просто відсутній. */
    @Test fun aCacheEntryFromBeforePlacesStillReads() {
        val card = row("origin" to "\"import\"", "source_name" to "\"Karabas\"")
        val stored = """{"total":1,"truncated":false,"index":[["e1",50.45,30.52,"music","2030-09-06T19:00:00Z","Europe/Kyiv","Подія","import","karabas",null,0]],"cards":[$card]}"""
        val page = json.decodeFromString<DiscoveryEnvelope>(stored).domain()
        assertEquals(listOf("e1"), page.index.map { it.id })
        assertNull(page.cards.single().placeId)
        assertEquals("Karabas", page.cards.single().listing?.sourceName)
    }

    @Test fun aPlaceRowParses() {
        val place = json.decodeFromString<List<PlaceDto>>(
            """[{"id":"p1","name":"Малевич","city":"Львів","address":"пр-т В'ячеслава Чорновола, 2, Львів","latitude":49.8475,"longitude":24.0263,"upcoming":26}]"""
        ).single().domain()
        assertEquals("Малевич", place.name)
        assertEquals(26, place.upcoming)
        assertTrue(place.isAt(49.8475, 24.0263))
        assertFalse(place.isAt(49.8476, 24.0263))
    }

    /** `my_follows`: `jsonb_strip_nulls` не шле порожнє, а невідомий рід (сервер новіший) — не рядок списку. */
    @Test fun followsParseAndDropUnknownKinds() {
        val follows = json.decodeFromString<List<FollowDto>>(
            """[{"kind":"place","id":"p1","name":"Клуб","city":"Київ","address":"Хрещатик, 1","latitude":50.45,"longitude":30.52,"upcoming":3,"since":"2026-09-28T10:00:00Z"},
               {"kind":"organizer","id":"u1","name":"Олена","avatar_url":"https://x.invalid/a.jpg","upcoming":1},
               {"kind":"group","id":"g1","name":"Нове"}]"""
        ).mapNotNull { it.domain() }
        assertEquals(listOf(FollowKind.PLACE, FollowKind.ORGANIZER), follows.map { it.kind })
        assertEquals("Клуб", follows[0].place?.name)
        assertEquals(3, follows[0].upcoming)
        assertNull(follows[1].place)
        assertEquals("https://x.invalid/a.jpg", follows[1].avatarUrl)
        assertEquals("", follows[1].city)
    }

    /** Картка несе склад у серверному порядку; `kind` буває відсутній, невідома роль — звичайний учасник. */
    @Test fun aCardCarriesItsArtists() {
        val event = parse(
            "origin" to "\"import\"", "source_name" to "\"Karabas\"",
            "artists" to """[{"id":"a1","name":"Андрій Бережко","kind":"person","role":"headliner"},
                {"id":"a2","name":"Дмитро Захарченко","role":"host"},{"id":"a3","name":"Гість","kind":"band","role":"opener"}]"""
        )
        assertEquals(listOf("a1", "a2", "a3"), event.artists.map { it.id })
        assertEquals(listOf(ArtistRole.HEADLINER, ArtistRole.HOST, ArtistRole.SUPPORT), event.artists.map { it.role })
        assertEquals(listOf(ArtistKind.PERSON, null, null), event.artists.map { it.kind })
    }

    /** Нема артистів — нема поля (`jsonb_strip_nulls`); так само відповідає старий сервер і prod без даних. */
    @Test fun aCardWithoutArtistsStillReads() {
        assertEquals(emptyList(), parse("origin" to "\"import\"", "source_name" to "\"Karabas\"").artists)
    }

    @Test fun anArtistSearchRowParses() {
        val hits = json.decodeFromString<List<ArtistHitDto>>(
            """[{"id":"a1","name":"Андрій Бережко","kind":"person","upcoming":23},{"id":"a2","name":"Театр","upcoming":1}]"""
        ).map { it.domain() }
        assertEquals(listOf(23, 1), hits.map { it.upcoming })
        assertEquals(listOf(ArtistKind.PERSON, null), hits.map { it.kind })
    }

    /** `my_follows`: артист несе `artist_kind` (не `kind`: там рід підписки) і лишається в списку. */
    @Test fun anArtistFollowKeepsItsKind() {
        val follows = json.decodeFromString<List<FollowDto>>(
            """[{"kind":"artist","id":"a1","name":"Андрій Бережко","artist_kind":"person","upcoming":23,"since":"2026-10-03T10:00:00Z"},
               {"kind":"artist","id":"a2","name":"Хтось","upcoming":0}]"""
        ).mapNotNull { it.domain() }
        assertEquals(listOf(FollowKind.ARTIST, FollowKind.ARTIST), follows.map { it.kind })
        assertEquals(listOf(ArtistKind.PERSON, null), follows.map { it.artistKind })
        assertNull(follows[0].place)
    }
}

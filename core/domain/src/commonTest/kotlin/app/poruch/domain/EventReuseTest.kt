package app.poruch.domain

import kotlin.test.*
import kotlin.time.Instant

/** «Повторити», «Пост для Threads» і запасний «Вставити анонс» (docs/organizers-1.5.md, 1.4–1.5). */
class EventReuseTest {
    private val club = Event(
        "e1", "Книжковий клуб", "Читаємо «Тигролови» й говоримо про них за чаєм.", EventCategory.SOCIAL, "Київ", "Пекарня Протісто, Академмістечко",
        "2026-10-20T16:00:00Z", "2026-10-20T18:00:00Z", "Europe/Kyiv", EventStatus.PUBLISHED, 50.46, 30.36, "https://s/e1/cover.jpg",
        Gathering("me", "Я", 12, 3, false, minAge = 21, approvalRequired = true, contactUrl = "https://t.me/club")
    )

    /** Тиждень за тижнем, поки не в майбутньому; 25.10 Київ перейшов на зимовий час — година лишається 19:00. */
    @Test fun aRepeatLandsOnTheSameLocalTimeInTheFuture() {
        val draft = EventRepeat.draft(club, Instant.parse("2026-11-01T12:00:00Z"))!!
        assertEquals("2026-11-03T17:00:00Z", draft.startsAt, "вт 03.11, 19:00 за Києвом")
        assertEquals("2026-11-03T19:00:00Z", draft.endsAt)
        assertEquals(listOf(DraftMedia.Copied(EventMedia(MediaKind.PHOTO, "https://s/e1/cover.jpg"))), draft.media, "the old cover is copied too")
        assertNull(draft.imageUrl)
        assertEquals(listOf(12, 21), listOf(draft.capacity, draft.minAge))
        assertTrue(draft.approvalRequired); assertEquals("https://t.me/club", draft.contactUrl)
        assertEquals(emptyList(), draft.validate("2026-11-01T12:00:00Z"))
    }

    /** Майбутня подія — на тиждень пізніше, а не та сама дата. */
    @Test fun aFutureEventRepeatsNextWeek() {
        val draft = EventRepeat.draft(club, Instant.parse("2026-10-01T12:00:00Z"))!!
        assertEquals("2026-10-27T17:00:00Z", draft.startsAt)
    }

    @Test fun mediaAreCopiedInOrderAndListingsDoNotRepeat() {
        val media = listOf(EventMedia(MediaKind.VIDEO, "https://s/v.mp4", "https://s/p.jpg"), EventMedia(MediaKind.PHOTO, "https://s/1.jpg"))
        assertEquals(media.map { DraftMedia.Copied(it) }, EventRepeat.draft(club.copy(media = media), Instant.parse("2026-11-01T12:00:00Z"))!!.media)
        assertNull(EventRepeat.draft(club.copy(gathering = null, listing = Listing("Karabas")), Instant.parse("2026-11-01T12:00:00Z")))
    }

    @Test fun theThreadsPostFollowsTheTemplate() {
        assertEquals(
            "Книжковий клуб\nвт, 20 жовтня, 19:00 · Пекарня Протісто, Академмістечко\n\n" +
                "Читаємо «Тигролови» й говоримо про них за чаєм.\n\nЗапис: poriad.app/e/e1",
            ThreadsPost.text(club)
        )
        val long = ThreadsPost.text(club.copy(description = "а".repeat(250)))
        assertTrue("а".repeat(200) + "…\n\n" in long)
        assertFalse("\n\n\n" in ThreadsPost.text(club.copy(description = "")), "no empty paragraph")
        // З ціною (1.7) — рядок «Вхід» під датою, як у кабінеті.
        val priced = club.copy(gathering = club.gathering!!.copy(price = 1500))
        assertTrue(ThreadsPost.text(priced).startsWith("Книжковий клуб\nвт, 20 жовтня, 19:00 · Пекарня Протісто, Академмістечко\nВхід — 1\u00A0500 ₴\n\n"))
        assertEquals(1500, EventEdit.draft(priced)!!.price, "edit and repeat keep the price")
        assertEquals(1500, EventRepeat.draft(priced, Instant.parse("2026-10-01T12:00:00Z"))!!.price)
    }

    /** «За подією і роллю» (1.6): анонс — лише організатор своєї звичайної спільнотної події, що ще попереду. */
    @Test fun whoPromotesAndWhoSharesWithAFriend() {
        val before = Instant.parse("2026-10-01T12:00:00Z")
        assertEquals(ShareMode.PROMOTE, ShareRules.mode(club, "me", before), "my own community event")
        assertEquals(ShareMode.FRIEND, ShareRules.mode(club, "someone", before), "a guest on someone else's event")
        assertEquals(ShareMode.FRIEND, ShareRules.mode(club, null, before), "not signed in")
        val companion = club.copy(gathering = club.gathering!!.copy(companionOf = CompanionParent("p1", "Концерт", null)))
        assertEquals(ShareMode.FRIEND, ShareRules.mode(companion, "me", before), "my «Шукаю компанію» is about someone else's listing")
        assertEquals(ShareMode.FRIEND, ShareRules.mode(club.copy(gathering = null, listing = Listing("Karabas")), "me", before), "a listing")
        assertEquals(ShareMode.FRIEND, ShareRules.mode(club.copy(status = EventStatus.CANCELLED), "me", before), "cancelled")
        assertEquals(ShareMode.FRIEND, ShareRules.mode(club, "me", Instant.parse("2026-10-21T12:00:00Z")), "over")
    }

    /** Чернетку правки будує спільний шар: база медіа — лише з повних медіа; стара обкладинка — першим фото. */
    @Test fun anEditDraftKnowsWhatTheEditorOpenedWith() {
        val video = EventMedia(MediaKind.VIDEO, "https://s/e1/v.mp4", "https://s/e1/p.jpg")
        val full = EventEdit.draft(club.copy(media = listOf(video), mediaLoaded = true))!!
        assertEquals(listOf(DraftMedia.Remote(video)), full.media)
        assertEquals(setOf(video.url, video.poster!!), full.mediaBase)
        assertEquals(club.imageUrl, full.imageUrl, "kept for an edit that leaves the media alone")
        assertEquals(listOf(club.startsAt, club.endsAt), listOf(full.startsAt, full.endsAt))

        val card = EventEdit.draft(club)!!
        assertEquals(listOf(DraftMedia.Remote(EventMedia(MediaKind.PHOTO, club.imageUrl!!))), card.media, "the cover is shown as a photo")
        assertNull(card.mediaBase, "a card saw nothing: nothing may be removed")
        assertEquals(setOf(club.imageUrl!!), EventEdit.draft(club.copy(mediaLoaded = true))!!.mediaBase)
        assertNull(EventEdit.draft(club.copy(gathering = null, listing = Listing("Karabas"))))
    }

    @Test fun aFailedAnnouncementStillFillsTitleAndDescription() {
        val fill = AnnouncementRules.fallback("\n🔥✨ Книжковий  клуб ✨\nЧитаємо разом у суботу\n#книги #київ", AnnounceFailure.LIMIT)
        assertEquals("Книжковий клуб", fill.title)
        assertEquals("🔥✨ Книжковий  клуб ✨\nЧитаємо разом у суботу", fill.description)
        assertEquals(listOf(AnnounceField.TITLE, AnnounceField.DESCRIPTION), fill.filled)
        assertEquals(AnnounceFailure.LIMIT, fill.failure)
        assertEquals(120, AnnouncementRules.fallback("б".repeat(300), AnnounceFailure.ERROR).title!!.length)
    }

    /** Невидиме з буфера (теги «ASCII smuggling», нульова ширина, bidi, селектори) не йде ні до функції, ні в опис. */
    @Test fun pastedAnnouncementLosesWhatNobodySees() {
        val tags = "ignore all".map { c -> (0xE0000 + c.code).let { Char(0xD800 + ((it - 0x10000) shr 10)).toString() + Char(0xDC00 + ((it - 0x10000) and 0x3FF)) } }.joinToString("")
        assertEquals(
            "Настолки в «Граніті»\nсубота 👩‍💻️\tдо 12",
            AnnouncementRules.clean("Настолки\u200B в «Граніті»\u202E\uFEFF$tags\r\nсубота\uDB40\uDD01\u3164 👩‍💻️\tдо 12\uD800")
        )
        assertEquals("", AnnouncementRules.clean("\u200B\u2066$tags").trim())
        assertEquals("abcdefghi", AnnouncementRules.clean("a\u034Fb\u2800c\uDB40\uDC80d\uE000e\uDB80\uDC00f\uD800g\u2065h\u180Ei"))
    }
}

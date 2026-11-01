package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import kotlin.test.*

/** «Вставити анонс», «Повторити» й «Пост для Threads» у застосунку (docs/organizers-1.5.md, хвиля 2). */
@OptIn(ExperimentalCoroutinesApi::class)
class OrganizerToolsTest {
    /** І гість: вхід лише на «Опублікувати». Ліміт — запасні назва й опис і причина в аналітиці. */
    @Test fun anAnnouncementFillsTheDraftEvenForAGuest()=runTest {
        val tracked=mutableListOf<Pair<String,Map<String,String>>>()
        PoruchAnalytics.sink={ name,params -> tracked+=name to params }
        try {
            val events=Events(); val auth=Auth(); auth.session.value=null
            val app=testApp(events,backgroundScope,auth)
            runCurrent()
            val fill=app.fillFromAnnouncement("  Клуб\nЧитаємо разом  ","Київ","Europe/Kyiv")
            assertEquals("Клуб",fill.title)
            assertEquals(listOf("Клуб\nЧитаємо разом","Київ"),events.announceCalls.single().take(2))
            assertEquals("Europe/Kyiv",events.announceCalls.single()[3])
            assertEquals("title,description,category",tracked.single { it.first=="announce_fill" }.second["filled"])

            events.announceError=AppError.TooManyAttempts
            val limited=app.fillFromAnnouncement("Клуб\nЧитаємо разом #книги","Київ","Europe/Kyiv")
            assertEquals(AnnounceFailure.LIMIT,limited.failure)
            assertEquals("Клуб",limited.title); assertEquals("Клуб\nЧитаємо разом",limited.description)
            assertEquals("limit",tracked.single { it.first=="announce_failed" }.second["reason"])

            assertEquals(AnnounceFailure.ERROR,app.fillFromAnnouncement("   ","Київ","Europe/Kyiv").failure)
            assertEquals(2,events.announceCalls.size,"an empty text never reaches the function")
            app.close()
        } finally { PoruchAnalytics.sink=null }
    }

    /** Лише своя подія; аналітика `repeat_event` і `share {kind: threads}`. */
    @Test fun repeatingAndPostingAreTheOrganizers()=runTest {
        val tracked=mutableListOf<Pair<String,Map<String,String>>>()
        PoruchAnalytics.sink={ name,params -> tracked+=name to params }
        try {
            val app=testApp(Events(),backgroundScope)
            runCurrent()
            val mine=Event("e1","Клуб","Читаємо разом за чаєм",EventCategory.SOCIAL,"Київ","Поділ","2026-10-20T16:00:00Z","2026-10-20T18:00:00Z",
                "Europe/Kyiv",EventStatus.PUBLISHED,50.45,30.52,null,Gathering("user","Я",12,3,false))
            assertNotNull(app.repeatDraft(mine))
            assertNull(app.repeatDraft(mine.copy(gathering=mine.gathering!!.copy(organizerId="someone"))))
            assertTrue(app.threadsPost(mine).endsWith("Запис: poriad.app/e/e1"))
            assertEquals(listOf("repeat_event","share"),tracked.map { it.first })
            assertEquals("threads",tracked.last().second["kind"])
            app.close()
        } finally { PoruchAnalytics.sink=null }
    }
}

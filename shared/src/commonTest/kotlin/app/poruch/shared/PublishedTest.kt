package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import kotlin.test.*

/** «Подію створено» і хто чим ділиться (docs/organizers-1.5.md, 1.6). */
@OptIn(ExperimentalCoroutinesApi::class)
class PublishedTest {
    private val walk=EventDraft("Прогулянка","Зустріч у центрі міста",EventCategory.OUTDOORS,"Київ","Поділ",50.45,30.5,"2090-01-06T17:00:00Z","2090-01-06T19:00:00Z","Europe/Kyiv",10)

    /** Після публікації — і з файлами: посилання, текст анонсу й календар; «Готово» закриває й рахується. */
    @Test fun aPublishedEventOpensTheScreen()=runTest {
        val tracked=mutableListOf<Pair<String,Map<String,String>>>()
        PoruchAnalytics.sink={ name,params -> tracked+=name to params }
        try {
            val events=Events().apply { detailsOfCreated=true }; val app=testApp(events,backgroundScope)
            runCurrent(); app.createEvent(walk.copy(media=listOf(DraftMedia.Local("a",MediaKind.PHOTO,{ "a".encodeToByteArray() })))); runCurrent()
            val id=events.createIds.single()
            val published=app.state.value.published!!
            assertEquals(id,published.id)
            assertEquals("https://poriad.app/e/$id",published.link)
            assertEquals(ShareMode.PROMOTE,published.shareMode)
            assertEquals("Прогулянка\nпт, 6 січня, 19:00 · Поділ\n\nЗустріч у центрі міста\n\nЗапис: poriad.app/e/$id",published.post)
            assertEquals(kotlin.time.Instant.parse("2090-01-06T17:00:00Z").toEpochMilliseconds(),published.startMillis)
            assertEquals(kotlin.time.Instant.parse("2090-01-06T19:00:00Z").toEpochMilliseconds(),published.endMillis)
            assertEquals("Europe/Kyiv",published.timeZone)
            assertEquals("Поділ, Київ",published.location)

            app.publishDone(PublishAction.COPY); app.publishDone(PublishAction.SHARE)
            assertNotNull(app.state.value.published,"actions keep the screen")
            app.publishDone(PublishAction.DONE)
            assertNull(app.state.value.published)
            assertEquals(listOf("copy","share","done"),tracked.filter { it.first=="publish_done" }.map { it.second["action"] })
            assertEquals("threads",tracked.single { it.first=="share" }.second["kind"])

            app.updateEvent(id,walk); runCurrent()
            assertNull(app.state.value.published,"an edit is not a new event")
            app.close()
        } finally { PoruchAnalytics.sink=null }
    }

    /** Гість: екран — після входу, коли подія сама опублікувалась; вихід з акаунта його закриває. */
    @Test fun aGuestSeesItAfterSigningIn()=runTest {
        val events=Events(); val auth=Auth(); auth.session.value=null
        val app=testApp(events,backgroundScope,auth)
        runCurrent(); app.createEvent(walk); runCurrent()
        assertNull(app.state.value.published)
        auth.session.value=UserSession("user","token","refresh",9999999999); advanceTimeBy(1000); runCurrent()
        assertEquals(events.createIds.single(),app.state.value.published?.id)
        app.signOut(); advanceTimeBy(1000); runCurrent()
        assertNull(app.state.value.published)
        app.close()
    }

    /** Деталі кажуть, яку «Поширити» показати: тим самим правилом, що й «Подію створено». */
    @Test fun theDetailScreenKnowsTheShareMode() {
        val mine=Event("e1","Клуб","Опис",EventCategory.SOCIAL,"Київ","Поділ","2090-01-06T17:00:00Z","2090-01-06T19:00:00Z","Europe/Kyiv",
            EventStatus.PUBLISHED,50.45,30.52,null,Gathering("me","Я",10,0,false))
        assertEquals(ShareMode.PROMOTE,DetailScreenState(event=mine,userId="me").shareMode)
        assertEquals(ShareMode.FRIEND,DetailScreenState(event=mine,userId="other").shareMode)
        assertEquals(ShareMode.FRIEND,DetailScreenState().shareMode)
    }
}

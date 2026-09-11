package app.poruch.shared

import app.poruch.domain.*
import app.poruch.events.EventActions
import app.poruch.account.AccountActions
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import kotlin.test.*

@OptIn(ExperimentalCoroutinesApi::class)
class PoruchAppTest {
    private class Auth: AuthRepository {
        override val session=MutableStateFlow<UserSession?>(UserSession("user","token","refresh",9999999999))
        override suspend fun signIn(email:String,password:String) {}
        override suspend fun signUp(email:String,password:String,name:String,birthDate:String)=true
        override suspend fun signOut() { session.value=null }
        override suspend fun accessToken()=session.value?.accessToken
        override suspend fun requestPasswordReset(email:String) {}
        override suspend fun updatePassword(password:String) {}
        override suspend fun handleCallback(url:String):Boolean { session.value=UserSession("recovered","new","refresh",9999999999); return true }
    }
    /**
     * Підробка реалізує всі п'ять граней, бо [PoruchApp] справді користується всіма. Тест на щось
     * вужче — на кнопку закладки, наприклад — тепер може реалізувати саму [SavedEvents] і не
     * писати двадцять порожніх методів заради двох потрібних.
     */
    private class Events: EventDiscovery, SavedEvents, EventAuthoring, EventParticipation, EventRequests {
        val queries=mutableListOf<EventQuery>()
        val cardRequests=mutableListOf<List<String>>()
        val createIds=mutableListOf<String>()
        val saves=mutableListOf<String>()
        val unsaves=mutableListOf<String>()
        var failCreate=false
        var failSave=false
        var results=emptyList<Event>()
        /** Скільки карток сервер кладе у відповідь одразу. Решта — окремим запитом, як у житті. */
        var inlineCards=Int.MAX_VALUE
        override suspend fun discover(query:EventQuery):DiscoveryPage { queries+=query; delay(100); return page(results,inlineCards) }
        override fun cached(query:EventQuery)=DiscoveryPage.Empty
        override suspend fun cards(ids:List<String>):List<Event> { cardRequests+=ids; return results.filter { it.id in ids } }
        override suspend fun details(id:String):Event?=null
        override suspend fun myEvents()=emptyList<Event>()
        override suspend fun attendees(id:String)=emptyList<Attendee>()
        override fun clearPrivateCache() {}
        override suspend fun savedIds()=emptyList<String>()
        override suspend fun save(id:String) { delay(100); saves+=id; if(failSave) fail(AppError.Network) }
        override suspend fun unsave(id:String) { delay(100); unsaves+=id; if(failSave) fail(AppError.Network) }
        override suspend fun create(id:String,draft:EventDraft):String { createIds+=id; if(failCreate) fail(AppError.Network); return id }
        override suspend fun update(id:String,draft:EventDraft)=id
        override suspend fun cancel(id:String) {}
        override suspend fun uploadImage(eventId:String,bytes:ByteArray,contentType:String)="https://test.invalid/image.jpg"
        override suspend fun join(id:String) {}
        override suspend fun leave(id:String) {}
        override suspend fun waitlistIds()=emptyList<String>()
        override suspend fun joinWaitlist(id:String) {}
        override suspend fun leaveWaitlist(id:String) {}
        override suspend fun joinRequests(id:String)=emptyList<Attendee>()
        override suspend fun approveMember(eventId:String,userId:String) {}
        override suspend fun declineMember(eventId:String,userId:String) {}
    }
    private fun app(events:Events,scope:CoroutineScope):PoruchApp {
        val auth=Auth()
        return PoruchApp(
            events=events, saved=events, authoring=events, participation=events, requests=events,
            auth=auth,
            geo=object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },
            eventActions=EventActions(events,events,auth), accountActions=AccountActions(auth),
            safety=safety, tasteStore=taste, scope=scope
        )
    }

    /** Reporting and blocking, recorded rather than sent. */
    private class Safety(var facts: AccountFacts = AccountFacts("1990-01-01")): SafetyRepository {
        val reports=mutableListOf<Triple<String,String,String?>>()
        val blocked=mutableListOf<String>()
        var declared: String? = null
        override suspend fun account()=facts
        override suspend fun declareBirthDate(date:String) { declared=date; facts=facts.copy(birthDate=date) }
        override suspend fun reportEvent(eventId:String,reason:String,details:String?) { reports+=Triple(eventId,reason,details) }
        override suspend fun reportUser(userId:String,reason:String,details:String?) { reports+=Triple(userId,reason,details) }
        override suspend fun block(userId:String) { blocked+=userId }
        override suspend fun unblock(userId:String) { blocked-=userId }
        override suspend fun blocked()=this.blocked.map { Attendee(it,"Заблокований",null) }
    }
    private var safety = Safety()

    /** The device's copy of the answers. Kept as a field so a test can read what was written. */
    private class Answers(var stored: Taste = Taste()): TasteStore {
        override fun read() = stored
        override fun write(taste: Taste) { stored = taste }
    }
    private var taste = Answers()

    private fun event(id:String,category:String,startsAt:String)=Event(
        id,id,"",category,"Київ","Поділ",startsAt,startsAt,"Europe/Kyiv",
        EventStatus.PUBLISHED,50.45,30.52,null,
        Gathering("organizer","Організатор",20,0,false)
    )
    @Test fun replacementQueryCancelsPreviousDiscovery()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        runCurrent(); app.searchArea(1.0,2.0,3.0,4.0); runCurrent()
        assertEquals(2,events.queries.size)
        assertEquals(1.0,events.queries.last().south)
        advanceTimeBy(101);runCurrent()
        assertFalse(app.state.value.loading);app.close()
    }
    /**
     * Стос майданчика — не початок стрічки.
     *
     * Вікно карток малює перші кілька подій у порядку показу, а пін віддає всі ідентифікатори під
     * пальцем. У київському майданчику на 32 події у вікно потрапляли дві: пін казав «32», а
     * карусель під ним — «Тут подій: 2», і решта стосу була недосяжна з мапи. Тест просить картки
     * для хвоста списку — тобто саме для того, чого у вікні бути не може.
     */
    @Test fun tappingAVenueStackAsksForItsOwnCardsNotTheStartOfTheList()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        val all=(1..40).map { event("e%02d".format(it),"music","2090-01-01T10:00:00Z") }
        events.results=all; events.inlineCards=2
        app.searchArea(1.0,2.0,3.0,4.0); advanceTimeBy(101); runCurrent()
        events.cardRequests.clear()

        val stack=all.takeLast(10).map { it.id }
        app.loadCards(stack); runCurrent()

        assertEquals(listOf(stack),events.cardRequests)
        assertTrue(stack.all { it in app.state.value.cards })
        app.close()
    }

    /** Те, що вже є, вдруге не питається: повторний тап по тому самому піну мовчить. */
    @Test fun aStackAlreadyInHandCostsNoRequest()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        val all=(1..10).map { event("e%02d".format(it),"music","2090-01-01T10:00:00Z") }
        events.results=all; events.inlineCards=10
        app.searchArea(1.0,2.0,3.0,4.0); advanceTimeBy(101); runCurrent()
        events.cardRequests.clear()

        app.loadCards(all.map { it.id }); runCurrent()

        assertEquals(emptyList(),events.cardRequests)
        app.close()
    }

    /**
     * Категорія не їде в запит — і саме тому фільтри екранів незалежні.
     *
     * Доки вона була частиною `EventQuery`, вона звужувала сам індекс: мапа, відфільтрована на
     * «музику», звужувала й те, що бачить головна. Два екрани ділили один фільтр, хоч кожен мав
     * свій перемикач. Тепер сервер віддає місто цілим, а категорію відбирає той екран, що спитав.
     */
    @Test fun pickingACategoryNarrowsTheScreenNotTheQuery()=runTest {
        val events=Events()
        events.results=listOf(event("m","music","2090-01-05T19:00:00Z"),event("a","art","2090-01-06T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        val searches=events.queries.size

        app.setCategory("music"); runCurrent(); advanceTimeBy(101); runCurrent()

        assertEquals(searches,events.queries.size,"категорія не має коштувати запиту")
        assertEquals("music",app.state.value.category)
        // Індекс лишається повним: звужує його екран, а не застосунок.
        assertEquals(listOf("m","a"),app.state.value.index.map { it.id })
        app.close()
    }

    @Test fun retryCreationReusesIdAfterUncertainNetworkFailure()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        val draft=EventDraft("Прогулянка","Зустріч у центрі міста","outdoors","Київ","Поділ",50.45,30.5,"2090-01-01T10:00:00Z","2090-01-01T12:00:00Z","Europe/Kyiv",10)
        events.failCreate=true;app.createEvent(draft);runCurrent()
        assertNull(app.state.value.completedEventId)
        events.failCreate=false;app.createEvent(draft);runCurrent()
        assertEquals(2,events.createIds.size)
        assertEquals(events.createIds.first(),events.createIds.last())
        assertEquals(events.createIds.last(),app.state.value.completedEventId)
        app.close()
    }
    @Test fun invalidCreationNeverReachesRepository()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        app.createEvent(EventDraft("","","social","Київ","Поділ",50.0,30.0,"2090-01-01T10:00:00Z","2090-01-01T12:00:00Z","Europe/Kyiv",0));runCurrent()
        assertTrue(events.createIds.isEmpty())
        // The draft is rejected by field, so the editor can point at the ones that failed.
        val notice=app.state.value.notice
        assertIs<AppNotice.Failed>(notice)
        val error=notice.error
        assertIs<AppError.InvalidDraft>(error)
        assertTrue(DraftField.TITLE in error.fields && DraftField.CAPACITY in error.fields)
        app.close()
    }
    @Test fun recoveryFlagSurvivesIdentityChange()=runTest {
        val app=app(Events(),backgroundScope)
        runCurrent();app.handleAuthCallback("poruch://auth/callback");runCurrent()
        assertTrue(app.state.value.passwordRecovery)
        app.close()
    }

    @Test fun textSearchDebouncesAndKeepsLatestQuery()=runTest {
        val events=Events();val app=app(events,backgroundScope)
        runCurrent();advanceTimeBy(101);runCurrent()
        val before=events.queries.size
        app.setSearchText("Муз");runCurrent();advanceTimeBy(100)
        app.setSearchText("Музика");runCurrent();advanceTimeBy(250);runCurrent()
        assertEquals(before,events.queries.size)
        advanceTimeBy(101);runCurrent()
        assertEquals("Музика",events.queries.last().text)
        assertEquals(before+1,events.queries.size);app.close()
    }
    @Test fun availabilityIsPartOfServerQuery()=runTest {
        val events=Events();val app=app(events,backgroundScope)
        runCurrent();app.setOnlyAvailable(true);runCurrent()
        assertTrue(events.queries.last().available)
        assertTrue(app.state.value.onlyAvailable);app.close()
    }

    @Test fun answeringTheOpeningQuestionsEndsThemAndReordersWhatWasFound()=runTest {
        val events=Events(); events.results=listOf(event("social-later","social","2090-01-06T19:00:00Z"),event("music-sooner","music","2090-01-05T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        assertTrue(app.state.value.needsOnboarding)
        assertEquals("music-sooner",app.state.value.index.first().id)
        // Subject only: what the slots do to the order is TasteRankingTest's subject, not this one.
        app.saveTaste(listOf("social"),emptyList(),Crowd.ANY); runCurrent()
        assertFalse(app.state.value.needsOnboarding)
        // Persisted for the next launch, and the chosen subject now leads the list.
        assertEquals(listOf("social"),taste.stored.interests)
        assertTrue(taste.stored.answered)
        assertEquals("social-later",app.state.value.index.first().id)
        assertEquals(listOf("social-later"),app.state.value.suggested.map { it.id })
        app.close()
    }

    /** A category the build no longer ships would rank against nothing, so it never gets stored. */
    @Test fun unknownAnswersAreDropped()=runTest {
        val app=app(Events(),backgroundScope); runCurrent()
        app.saveTaste(listOf("music","astrology"),listOf("never"),"enormous"); runCurrent()
        assertEquals(listOf("music"),taste.stored.interests)
        assertTrue(taste.stored.times.isEmpty())
        assertEquals(Crowd.ANY,taste.stored.crowd)
        app.close()
    }

    @Test fun skippingAnswersNothingButStillEndsTheQuestions()=runTest {
        val app=app(Events(),backgroundScope); runCurrent()
        app.skipOnboarding(); runCurrent()
        assertFalse(app.state.value.needsOnboarding)
        assertTrue(app.state.value.taste.isBlank)
        // Nothing was said, so nothing is suggested — the section stays away rather than filling up.
        assertTrue(app.state.value.suggested.isEmpty())
        app.close()
    }

    /** The answers are the device's, not the account's: signing out must not take them. */
    @Test fun signingOutKeepsTheAnswers()=runTest {
        val app=app(Events(),backgroundScope); runCurrent()
        app.saveTaste(listOf("music"),emptyList(),Crowd.ANY); runCurrent()
        app.signOut(); runCurrent()
        assertEquals(listOf("music"),app.state.value.interests)
        assertFalse(app.state.value.needsOnboarding)
        app.close()
    }

    @Test fun blockingHidesTheOpenEventAndAsksTheMapAgain()=runTest {
        val events=Events(); events.results=listOf(event("theirs","social","2090-01-05T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        val before=events.queries.size
        app.selectEvent("theirs"); runCurrent()
        app.blockUser("organizer"); runCurrent(); advanceTimeBy(101); runCurrent()
        assertEquals(listOf("organizer"),safety.blocked)
        assertTrue(app.state.value.hasBlocked("organizer"))
        // The block takes effect now, not on the next pan: the map is asked again straight away.
        assertTrue(events.queries.size > before)
        assertNull(app.state.value.selectedEvent)
        app.close()
    }

    @Test fun reportingNeedsAnAccountAndCarriesItsReason()=runTest {
        val app=app(Events(),backgroundScope); runCurrent()
        app.reportEvent("event-1",ReportReason.MINORS,"опис"); runCurrent()
        assertEquals(Triple("event-1",ReportReason.MINORS,"опис"),safety.reports.single())
        assertEquals(AppNotice.Told(AppMessage.REPORT_SENT),app.state.value.notice)
        app.close()
    }

    /** Stating an age is once and adult-only; the app refuses before the server has to. */
    @Test fun anUnderageDeclarationIsRefused()=runTest {
        val app=app(Events(),backgroundScope); runCurrent()
        app.declareBirthDate("2015-01-01"); runCurrent()
        assertNull(safety.declared)
        val notice=app.state.value.notice
        assertIs<AppNotice.Failed>(notice)
        assertEquals(AppError.Underage,notice.error)
        app.close()
    }

    /**
     * Закладка — найдешевша дія в застосунку, і чекати на мережу вона не має. Підробка навмисно
     * відповідає з затримкою: якби стан оновлювався лише після відповіді, `runCurrent` побачив би
     * порожній список.
     */
    @Test fun savingShowsUpBeforeTheNetworkAnswers()=runTest {
        val events=Events();val app=app(events,backgroundScope);runCurrent()
        app.toggleSaved("event-1");runCurrent()
        assertTrue(app.state.value.isSaved("event-1"),"закладка має спрацювати одразу")
        // І не через загальну мутацію: інакше вона блокувала б решту дій на весь час запиту.
        assertFalse(app.state.value.mutating)
        advanceTimeBy(200);runCurrent()
        assertEquals(listOf("event-1"),events.saves)
        assertTrue(app.state.value.isSaved("event-1"))

        app.toggleSaved("event-1");runCurrent()
        assertFalse(app.state.value.isSaved("event-1"),"зняття теж миттєве")
        advanceTimeBy(200);runCurrent()
        assertEquals(listOf("event-1"),events.unsaves)
        app.close()
    }

    /** Не вдалося — повертаємо як було й кажемо про це, а не лишаємо тиху брехню на екрані. */
    @Test fun aRefusedSaveRollsBackAndSaysSo()=runTest {
        val events=Events().apply { failSave=true };val app=app(events,backgroundScope);runCurrent()
        app.toggleSaved("event-1");runCurrent()
        assertTrue(app.state.value.isSaved("event-1"))
        advanceTimeBy(200);runCurrent()
        assertFalse(app.state.value.isSaved("event-1"),"після відмови стан повертається")
        assertIs<AppNotice.Failed>(app.state.value.notice)
        app.close()
    }

    @Test fun wrappedMapBoundsPreserveAntimeridianAndWholeWorld()=runTest {
        val events=Events();val app=app(events,backgroundScope)
        runCurrent();app.searchArea(-10.0,170.0,10.0,190.0);runCurrent()
        assertEquals(170.0,events.queries.last().west)
        assertEquals(-170.0,events.queries.last().east)
        app.searchArea(-90.0,-230.0,90.0,230.0);runCurrent()
        assertEquals(-180.0,events.queries.last().west)
        assertEquals(180.0,events.queries.last().east);app.close()
    }

}

/**
 * Сервер віддає індекс і перші картки однією відповіддю; підробка робить те саме зі свого списку
 * подій, щоб тест лишався про поведінку застосунку, а не про форму RPC.
 */
private fun page(events: List<Event>, inlineCards: Int = Int.MAX_VALUE) = DiscoveryPage(
    index = events.map {
        EventIndexEntry(
            id = it.id, latitude = it.latitude, longitude = it.longitude, category = it.category,
            startsAt = it.startsAt, timeZone = it.timeZone, title = it.title,
            origin = if (it.isCommunity) EventOrigin.COMMUNITY else EventOrigin.IMPORT,
            capacity = it.gathering?.capacity, attendeeCount = it.gathering?.attendeeCount ?: 0
        )
    },
    total = events.size, truncated = false, cards = events.take(inlineCards)
)

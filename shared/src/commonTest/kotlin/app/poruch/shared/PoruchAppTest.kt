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
        /** Чи повертає бекенд сесію одразу; без підтвердження пошти — ні. */
        var signUpSignsIn=true
        override suspend fun signUp(email:String,password:String,name:String,birthDate:String):Boolean {
            if(signUpSignsIn) session.value=UserSession("fresh","token","refresh",9999999999)
            return signUpSignsIn
        }
        override suspend fun signOut() { session.value=null }
        override suspend fun accessToken()=session.value?.accessToken
        override suspend fun requestPasswordReset(email:String) {}
        override suspend fun updatePassword(password:String) {}
        override suspend fun handleCallback(url:String):Boolean { session.value=UserSession("recovered","new","refresh",9999999999); return true }
    }
    /** Підробка реалізує всі п'ять інтерфейсів, бо [PoruchApp] користується всіма. */
    private class Events: EventDiscovery, SavedEvents, EventAuthoring, EventParticipation, EventRequests {
        val queries=mutableListOf<EventQuery>()
        val cardRequests=mutableListOf<List<String>>()
        val createIds=mutableListOf<String>()
        val saves=mutableListOf<String>()
        val unsaves=mutableListOf<String>()
        var failCreate=false
        var failSave=false
        var failDetails=false
        var results=emptyList<Event>()
        /** Скільки карток сервер кладе у відповідь одразу. Решта окремим запитом. */
        var inlineCards=Int.MAX_VALUE
        override suspend fun discover(query:EventQuery):DiscoveryPage { queries+=query; delay(100); return page(results,inlineCards) }
        override fun cached(query:EventQuery)=DiscoveryPage.Empty
        override suspend fun cards(ids:List<String>):List<Event> { cardRequests+=ids; return results.filter { it.id in ids } }
        override suspend fun details(id:String):Event? { if(failDetails) fail(AppError.ServiceUnavailable); return null }
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
    private fun app(events:Events,scope:CoroutineScope,auth:Auth=Auth()):PoruchApp {
        return PoruchApp(
            events=events, saved=events, authoring=events, participation=events, requests=events,
            auth=auth,
            geo=object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },
            eventActions=EventActions(events,events,auth), accountActions=AccountActions(auth),
            safety=safety, tasteStore=taste, scope=scope
        )
    }

    /** Скарги й блокування записуються, а не надсилаються. */
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

    /** Копія відповідей на пристрої. Поле, щоб тест міг прочитати записане. */
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
    /** Стос майданчика — не початок стрічки: просимо картки для хвоста списку, якого у вікні нема. */
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

    /** Повторний тап по тому самому піну нічого не питає. */
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

    /** Категорія не їде в запит, тому фільтри екранів незалежні. */
    @Test fun pickingACategoryNarrowsTheScreenNotTheQuery()=runTest {
        val events=Events()
        events.results=listOf(event("m","music","2090-01-05T19:00:00Z"),event("a","art","2090-01-06T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        val searches=events.queries.size

        app.setCategory("music"); runCurrent(); advanceTimeBy(101); runCurrent()

        assertEquals(searches,events.queries.size,"категорія не має коштувати запиту")
        assertEquals("music",app.state.value.category)
        // Індекс лишається повним: звужує екран.
        assertEquals(listOf("m","a"),app.state.value.index.map { it.id })
        app.close()
    }

    /** Прокат: одна картка в стрічці, але `sessionsOf` віддає всі сеанси, включно з прибраними зі списку. */
    @Test fun aRunIsOneCardButEveryDateStaysReachable()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        // Прокат буває лише в афіші: `gathering` має бути порожнім.
        events.results=listOf("s1" to "2090-12-22T18:00:00Z", "s2" to "2090-12-23T18:00:00Z",
                              "s3" to "2090-12-30T18:00:00Z").map { (id,at) ->
            event(id,"art",at).copy(title="Лускунчик", gathering=null) }
        app.searchArea(1.0,2.0,3.0,4.0); advanceTimeBy(101); runCurrent()

        assertEquals(1,app.state.value.index.size,"прокат — одна картка")
        assertEquals("s1",app.state.value.index[0].id,"показуємо найближчу дату")
        assertEquals(3,app.state.value.index[0].sessionCount)

        // Карусель однакова з будь-якого сеансу, не лише з представника.
        assertEquals(listOf("s1","s2","s3"),app.sessionsOf("s1").map { it.id })
        assertEquals(listOf("s1","s2","s3"),app.sessionsOf("s3").map { it.id })
        assertEquals(emptyList(),app.sessionsOf("невідомий"))

        // Мапа шукає пін за карткою: друга дата веде на представника, подія без прокату — на себе.
        assertEquals("s1",app.cardIdOf("s3"))
        assertEquals("невідомий",app.cardIdOf("невідомий"))
        app.close()
    }

    /** Позначка «ще 2 дати» є в `cards`, а не лише в стрічці: головна і стос читають картки за id. */
    @Test fun aRunCardCarriesItsSessionsWhereverItIsRead()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        events.results=listOf("s1" to "2090-12-22T18:00:00Z","s2" to "2090-12-23T18:00:00Z").map { (id,at) ->
            event(id,"art",at).copy(title="Лускунчик",gathering=null) }
        app.searchArea(1.0,2.0,3.0,4.0); advanceTimeBy(101); runCurrent()

        assertEquals(listOf("s1","s2"),app.state.value.cards.getValue("s1").sessions.map { it.id })
        assertTrue(app.state.value.events.single().isSeries)
        assertTrue(app.state.value.cards.getValue("s2").sessions.isEmpty(),"поглинутий сеанс сам прокатом не є")
        app.close()
    }

    /** Перемикання дати в каруселі не гасить екран: картку беремо з `cards`, а не лише зі стрічки. */
    @Test fun switchingTheDateShowsTheCardAtOnce()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        events.results=listOf("s1" to "2090-12-22T18:00:00Z","s2" to "2090-12-23T18:00:00Z","s3" to "2090-12-30T18:00:00Z").map { (id,at) ->
            event(id,"art",at).copy(title="Лускунчик",gathering=null) }
        events.inlineCards=1
        app.searchArea(1.0,2.0,3.0,4.0); advanceTimeBy(101); runCurrent()
        events.cardRequests.clear()

        app.openEvent("s1"); runCurrent()
        assertEquals(listOf(listOf("s2","s3")),events.cardRequests,"решта дат — одним запитом на відкриття")

        app.openEvent("s2")
        assertEquals("s2",app.state.value.selectedEvent?.id,"картка обраної дати одразу, без порожнього екрана")
        runCurrent()
        assertEquals(1,events.cardRequests.size,"вдруге за тими самими картками не питаємо")
        app.close()
    }

    /** Дата без картки, а сервер лежить: людина лишається на вечорі, який бачила, з банером. */
    @Test fun aDateWhoseCardFailsToArriveKeepsTheCurrentOneOnScreen()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        events.results=listOf("s1" to "2090-12-22T18:00:00Z","s2" to "2090-12-23T18:00:00Z").map { (id,at) ->
            event(id,"art",at).copy(title="Лускунчик",gathering=null) }
        events.inlineCards=1
        app.searchArea(1.0,2.0,3.0,4.0); advanceTimeBy(101); runCurrent()
        app.selectEvent("s1")
        events.failDetails=true

        // Картка другої дати ще не приїхала.
        app.openEvent("s2")
        assertEquals("s1",app.state.value.selectedEvent?.id,"до відповіді на екрані лишається поточна дата")
        runCurrent()
        assertEquals("s1",app.state.value.selectedEvent?.id,"і після відмови сервера теж")
        assertNotNull(app.state.value.notice)

        // Подія без прокату так не поводиться: чужа картка на екрані була б неправдою.
        app.selectEvent("s1"); app.openEvent("невідомий")
        assertNull(app.state.value.selectedEvent)
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
        // Чернетку відхилено по полях, щоб редактор підсвітив потрібні.
        val notice=app.state.value.notice
        assertIs<AppNotice.Failed>(notice)
        val error=notice.error
        assertIs<AppError.InvalidDraft>(error)
        assertTrue(DraftField.TITLE in error.fields && DraftField.CAPACITY in error.fields)
        app.close()
    }
    /** Реєстрація без сесії — це крок «перевірте пошту», а не банер на три секунди. */
    @Test fun signUpWithoutSessionOpensConfirmationStep()=runTest {
        val auth=Auth(); auth.session.value=null; auth.signUpSignsIn=false
        val app=app(Events(),backgroundScope,auth)
        runCurrent();app.signUp(" new@poruch.app ","password1","Імʼя","1990-01-01");runCurrent()
        assertEquals("new@poruch.app",app.state.value.awaitingConfirmation)
        assertNull(app.state.value.notice)
        app.dismissConfirmationStep()
        assertNull(app.state.value.awaitingConfirmation)
        app.close()
    }
    @Test fun signUpWithSessionSkipsConfirmationStep()=runTest {
        val auth=Auth(); auth.session.value=null
        val app=app(Events(),backgroundScope,auth)
        runCurrent();app.signUp("new@poruch.app","password1","Імʼя","1990-01-01");runCurrent()
        assertNull(app.state.value.awaitingConfirmation)
        assertEquals(AppNotice.Told(AppMessage.ACCOUNT_CREATED),app.state.value.notice)
        assertTrue(app.state.value.signedIn)
        app.close()
    }
    /** Лист підтверджено або людина увійшла інакше: крок закривається сам. */
    @Test fun signingInClearsConfirmationStep()=runTest {
        val auth=Auth(); auth.session.value=null; auth.signUpSignsIn=false
        val app=app(Events(),backgroundScope,auth)
        runCurrent();app.signUp("new@poruch.app","password1","Імʼя","1990-01-01");runCurrent()
        assertNotNull(app.state.value.awaitingConfirmation)
        app.handleAuthCallback("poruch://auth/callback");runCurrent()
        assertNull(app.state.value.awaitingConfirmation)
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
        // Лише інтереси: вплив слотів на порядок — предмет TasteRankingTest.
        app.saveTaste(listOf("social"),emptyList(),Crowd.ANY); runCurrent()
        assertFalse(app.state.value.needsOnboarding)
        // Збережено на наступний запуск, обрана категорія веде список.
        assertEquals(listOf("social"),taste.stored.interests)
        assertTrue(taste.stored.answered)
        assertEquals("social-later",app.state.value.index.first().id)
        assertEquals(listOf("social-later"),app.state.value.suggested.map { it.id })
        app.close()
    }

    /** Невідома категорія не зберігається. */
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
        // Нічого не сказано — нічого не запропоновано.
        assertTrue(app.state.value.suggested.isEmpty())
        app.close()
    }

    /** Відповіді належать пристрою: вихід з акаунта їх не забирає. */
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
        // Блок діє одразу: мапу перепитуємо, не чекаючи наступного руху.
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

    /** Вік вказують раз і лише дорослий; застосунок відмовляє до сервера. */
    @Test fun anUnderageDeclarationIsRefused()=runTest {
        val app=app(Events(),backgroundScope); runCurrent()
        app.declareBirthDate("2015-01-01"); runCurrent()
        assertNull(safety.declared)
        val notice=app.state.value.notice
        assertIs<AppNotice.Failed>(notice)
        assertEquals(AppError.Underage,notice.error)
        app.close()
    }

    /** Закладка не чекає на мережу. Підробка відповідає з затримкою, щоб це було видно. */
    @Test fun savingShowsUpBeforeTheNetworkAnswers()=runTest {
        val events=Events();val app=app(events,backgroundScope);runCurrent()
        app.toggleSaved("event-1");runCurrent()
        assertTrue(app.state.value.isSaved("event-1"),"закладка має спрацювати одразу")
        // І не через загальну мутацію, інакше блокувала б решту дій.
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

    /** Не вдалося — повертаємо як було й показуємо помилку. */
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

/** Підробка віддає індекс і перші картки однією відповіддю, як сервер. */
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

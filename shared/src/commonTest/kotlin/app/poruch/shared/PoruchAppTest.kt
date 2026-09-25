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
        /** Сервер не впізнав прострочений токен: локально вихід усе одно відбувся. */
        var signOutRefused=false
        override suspend fun signOut() { session.value=null; if(signOutRefused) fail(AppError.SessionRequired) }
        override suspend fun accessToken()=session.value?.accessToken
        override suspend fun requestPasswordReset(email:String) {}
        var updated=false
        override suspend fun updatePassword(password:String) { updated=true }
        override suspend fun handleCallback(url:String):Boolean { session.value=UserSession("recovered","new","refresh",9999999999); return true }
        /** Єдиний пароль, який підробка вважає правильним; null — приймає будь-який. */
        var currentPassword:String?=null
        override suspend fun verifyPassword(password: String) { if(currentPassword!=null&&password!=currentPassword) fail(AppError.InvalidCredentials) }
        override suspend fun deleteAccount() { session.value = null }
    }
    /** Підробка реалізує всі п'ять інтерфейсів, бо [PoruchApp] користується всіма. */
    private class Events: EventDiscovery, SavedEvents, EventAuthoring, EventParticipation, EventRequests, EventChat {
        val sent=mutableListOf<Pair<String,String>>()
        var chatMessages=emptyList<ChatMessage>()
        override suspend fun messages(eventId:String,after:String?)=chatMessages.filter { after==null || it.createdAt>after }
        var failSend=false
        var slowSend=false
        override suspend fun send(eventId:String,body:String):String { if(slowSend) delay(100); if(failSend) fail(AppError.Network); sent+=eventId to body; val m=ChatMessage("m${sent.size}",eventId,"user","Я",null,body,"2026-09-16T10:0${sent.size}:00Z"); chatMessages=chatMessages+m; return m.id }
        override suspend fun delete(messageId:String) { chatMessages=chatMessages.filterNot { it.id==messageId } }
        var unreadChats=emptyList<ChatUnread>()
        val readMarks=mutableListOf<String>()
        override suspend fun unread()=unreadChats
        override suspend fun markRead(eventId:String) { readMarks+=eventId }
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
        override suspend fun discover(query:EventQuery):DiscoveryPage { queries+=query; delay(100); return page(results.filter { e -> query.text.let { it==null || it in e.title } },inlineCards) }
        override fun cached(query:EventQuery)=DiscoveryPage.Empty
        override suspend fun cards(ids:List<String>):List<Event> { cardRequests+=ids; return results.filter { it.id in ids } }
        var failPending=false
        var failFacts=false
        var detailsById=emptyMap<String,Event>()
        override suspend fun details(id:String):Event? { if(failDetails) fail(AppError.ServiceUnavailable); return detailsById[id] }
        var places=emptyList<Place>()
        val placeQueries=mutableListOf<Pair<String,EventQuery?>>()
        override suspend fun searchPlaces(text:String,city:String?,bounds:EventQuery?):List<Place> { placeQueries+=text to bounds; delay(50); return places.filter { it.name.lowercase().startsWith(text.lowercase()) } }
        var atPlace=emptyMap<String,List<Event>>()
        var failPlaceEvents=false
        override suspend fun placeEvents(placeId:String):List<Event> { if(failPlaceEvents) fail(AppError.Network); return atPlace[placeId].orEmpty() }
        var mine=emptyList<Event>()
        override suspend fun myEvents()=mine
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
        override suspend fun ratings(id:String) = emptyList<EventRating>()
        override suspend fun rate(id:String, score:Int, comment:String?) {}
        override suspend fun joinRequests(id:String)=emptyList<Attendee>()
        var pending=emptyList<JoinRequest>()
        override suspend fun pendingRequests()=if(failPending) fail(AppError.ServiceUnavailable) else pending
        override suspend fun approveMember(eventId:String,userId:String) {}
        override suspend fun declineMember(eventId:String,userId:String) {}
    }
    /** Місто в пам'яті замість бази пристрою. */
    private class Cities(var stored:CityResult?=null): CityStore {
        override fun read()=stored
        override fun write(city:CityResult) { stored=city }
    }
    private fun app(events:Events,scope:CoroutineScope,auth:Auth=Auth(),cities:CityStore?=null):PoruchApp {
        return PoruchApp(
            events=events, saved=events, authoring=events, participation=events, requests=events, chat=events,
            auth=auth, cityStore=cities,
            geo=object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },
            eventActions=EventActions(events,events,auth), accountActions=AccountActions(auth),
            safety=safety, profiles=profiles, tasteStore=taste, reminderStore=reminders, scope=scope
        )
    }

    /** Профілі в пам'яті: свій — [mine], чужі — [cards]; видалені файли записуються. */
    private class Profiles: ProfileRepository {
        var mine=Profile("user","Я",null,null,"2026-09-01T00:00:00Z",0,0,"me@example.invalid")
        var cards=mapOf<String,Profile>()
        var slow=emptySet<String>()
        val deleted=mutableListOf<String>()
        var uploads=0
        override suspend fun profile(userId:String):Profile? { if(userId in slow) delay(100); return if(userId==mine.userId) mine else cards[userId] }
        override suspend fun update(name:String,bio:String?) { mine=mine.copy(name=name.trim(),bio=ProfileRules.normalizeBio(bio)) }
        override suspend fun setAvatar(bytes:ByteArray,contentType:String):String { uploads++; return "https://test.invalid/avatar/$uploads.jpg".also { mine=mine.copy(avatarUrl=it) } }
        override suspend fun removeAvatar() { mine=mine.copy(avatarUrl=null) }
        override suspend fun deleteImage(url:String) { deleted+=url }
    }
    private var profiles = Profiles()

    /** Скарги й блокування записуються, а не надсилаються. */
    private class Safety(var facts: AccountFacts = AccountFacts("1990-01-01")): SafetyRepository {
        var fail=false
        val reports=mutableListOf<Triple<String,String,String?>>()
        val blocked=mutableListOf<String>()
        var declared: String? = null
        override suspend fun account()=if(fail) fail(AppError.ServiceUnavailable) else facts
        override suspend fun declareBirthDate(date:String) { declared=date; facts=facts.copy(birthDate=date) }
        override suspend fun reportEvent(eventId:String,reason:String,details:String?) { reports+=Triple(eventId,reason,details) }
        override suspend fun reportUser(userId:String,reason:String,details:String?) { reports+=Triple(userId,reason,details) }
        override suspend fun reportMessage(messageId:String,reason:String,details:String?) { reports+=Triple(messageId,reason,details) }
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

    /** Прапорець нагадувань пристрою в пам'яті. */
    private class Reminders(var on: Boolean = false): ReminderPreferenceStore {
        override fun enabled() = on
        override fun setEnabled(enabled: Boolean) { on = enabled }
    }
    private var reminders = Reminders()

    private fun event(id:String,category:String,startsAt:String)=Event(
        id,id,"",category,"Київ","Поділ",startsAt,startsAt,"Europe/Kyiv",
        EventStatus.PUBLISHED,50.45,30.52,null,
        Gathering("organizer","Організатор",20,0,false)
    )
    /** Афіша в закладі: `event_details` місця не несе, тож воно приходить з картки. */
    private fun listed(id:String,startsAt:String,placeId:String?="p1")=event(id,"music",startsAt).copy(
        title=id,gathering=null,listing=Listing("Karabas",placeId=placeId,placeName=placeId?.let { "Малевич" })
    )
    private val malevych=Place("p1","Малевич","Київ","вул. Велика Васильківська, 1",50.45,30.52,3)

    /** «Ще в цьому місці» з `place_events`: сервер знає події закладу, яких нема в завантаженому індексі. */
    @Test fun othersAtTheVenueComeFromPlaceEvents()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        val opened=listed("b","2090-12-23T18:00:00Z")
        events.results=listOf(opened)
        // Картка деталей без закладу, як старий композит `event_details`.
        events.detailsById=mapOf("b" to opened.copy(listing=opened.listing!!.copy(placeId=null,placeName=null)))
        events.atPlace=mapOf("p1" to listOf(listed("a","2090-12-22T18:00:00Z"),opened,listed("c","2090-12-30T18:00:00Z")))
        runCurrent(); advanceTimeBy(101); runCurrent()

        app.openEvent("b"); advanceTimeBy(1000); runCurrent()
        val detail=app.state.value.detail.event!!
        assertEquals("p1",detail.placeId,"заклад узято з картки")
        assertEquals("Малевич",detail.placeLabel)
        assertEquals(listOf("a","c"),app.othersAt(detail).map { it.id })
        app.close()
    }

    /** Без мережі для `place_events` секція лишається на індексі мапи. */
    @Test fun othersAtFallsBackToTheIndexWhenPlaceEventsFail()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        events.results=listOf(listed("a","2090-12-22T18:00:00Z"),listed("b","2090-12-23T18:00:00Z"))
        events.detailsById=events.results.associateBy { it.id }
        events.failPlaceEvents=true
        runCurrent(); advanceTimeBy(101); runCurrent()
        app.openEvent("b"); advanceTimeBy(1000); runCurrent()
        assertNull(app.state.value.detail.placeEvents)
        assertEquals(listOf("a"),app.othersAt(app.state.value.detail.event!!).map { it.id })
        app.close()
    }

    /** Пошук мапи шукає й заклади, у тій самій області; порожній текст їх прибирає. */
    @Test fun mapSearchFindsPlaces()=runTest {
        val events=Events(); events.places=listOf(malevych)
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        app.setSearchText("мал"); advanceTimeBy(1000); runCurrent()
        assertEquals(listOf("p1"),app.state.value.map.places.map { it.id })
        val (text,bounds)=events.placeQueries.last()
        assertEquals("мал",text)
        assertEquals(HomeLocation.Kyiv.south,bounds?.south)
        app.setSearchText(""); runCurrent()
        assertEquals(emptyList(),app.state.value.map.places)
        app.close()
    }

    /** Пошук головної «усюди» питає заклади без рамки; скасування пошуку їх прибирає. */
    @Test fun homeSearchFindsPlacesEverywhere()=runTest {
        val events=Events(); events.places=listOf(malevych)
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        app.setHomeSearchText("мал"); advanceTimeBy(1000); runCurrent()
        assertEquals(listOf("p1"),app.state.value.home.places.map { it.id })
        assertNotNull(events.placeQueries.last().second)
        app.setHomeSearchEverywhere(true); advanceTimeBy(1000); runCurrent()
        assertNull(events.placeQueries.last().second)
        app.cancelHomeSearch(); runCurrent()
        assertEquals(emptyList(),app.state.value.home.places)
        app.close()
    }

    /** Тап по закладу: пошук мапи знято, а перша видача каже, які події на його піні. */
    @Test fun focusPlaceResolvesItsStack()=runTest {
        val events=Events(); events.places=listOf(malevych)
        events.results=listOf(listed("c","2090-12-24T18:00:00Z"),listed("a","2090-12-22T18:00:00Z"),
            listed("far","2090-12-22T18:00:00Z",placeId="p2").copy(latitude=50.46))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        app.setSearchText("мал"); advanceTimeBy(1000); runCurrent()

        app.focusPlace(malevych); runCurrent()
        assertEquals("",app.state.value.map.searchText)
        assertNull(app.state.value.map.placeFocus?.eventIds,"видача ще їде")
        advanceTimeBy(1000); runCurrent()
        val focus=app.state.value.map.placeFocus!!
        assertEquals(listOf("a","c"),focus.eventIds)
        assertNull(events.queries.last().text)

        app.placeFocusShown()
        assertNull(app.state.value.map.placeFocus)
        app.close()
    }

    /** «Ще в цьому місці»: інші картки на тій самій точці, без відкритої. */
    @Test fun othersAtTheVenueComeFromTheMapIndex()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        events.results=listOf("a" to "2090-12-22T18:00:00Z","b" to "2090-12-23T18:00:00Z","c" to "2090-12-24T18:00:00Z")
            .map { (id,at) -> event(id,"art",at).copy(title=id) }+
            event("far","art","2090-12-22T18:00:00Z").copy(latitude=50.46)
        app.searchArea(1.0,2.0,3.0,4.0); advanceTimeBy(101); runCurrent()
        val opened=app.state.value.cards.getValue("b")
        assertEquals(listOf("a","c"),app.othersAt(opened).map { it.id })
        // Пошук звузив мапу до однієї картки: решту місця досі видно з індексу головної.
        app.setSearchText("c"); advanceTimeBy(101); runCurrent()
        assertEquals(listOf("a","c"),app.othersAt(opened).map { it.id })
        app.close()
    }

    @Test fun replacementQueryCancelsPreviousDiscovery()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        runCurrent(); app.searchArea(1.0,2.0,3.0,4.0); runCurrent()
        // Скасований стартовий запит ніс і головну: вона їде сама, на цілому місті.
        assertEquals(3,events.queries.size)
        assertEquals(HomeLocation.Kyiv.south,events.queries[1].south)
        assertEquals(1.0,events.queries.last().south)
        advanceTimeBy(101);runCurrent()
        assertFalse(app.state.value.map.loading);app.close()
    }
    /** Потяг вниз повертається лише коли пошук і «мої» доїхали: індикатор ховається разом із відповіддю, не раніше. */
    @Test fun pullToRefreshWaitsForTheAnswersBeforeReturning()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        runCurrent(); advanceTimeBy(101); runCurrent()
        val before=events.queries.size
        var returned=false
        backgroundScope.launch { app.reloadAll(); returned=true }
        runCurrent()
        assertEquals(before+1,events.queries.size)
        assertTrue(app.state.value.map.loading); assertFalse(returned)
        advanceTimeBy(101); runCurrent()
        assertFalse(app.state.value.map.loading); assertTrue(returned); app.close()
    }
    /** Стос майданчика — не початок стрічки: просимо картки для хвоста списку, якого у вікні нема. */
    @Test fun tappingAVenueStackAsksForItsOwnCardsNotTheStartOfTheList()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        val all=(1..40).map { event("e${it.toString().padStart(2,'0')}","music","2090-01-01T10:00:00Z") }
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
        val all=(1..10).map { event("e${it.toString().padStart(2,'0')}","music","2090-01-01T10:00:00Z") }
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
        assertEquals("music",app.state.value.map.category)
        // Індекс лишається повним: звужує екран.
        assertEquals(listOf("m","a"),app.state.value.map.index.map { it.id })
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

        assertEquals(1,app.state.value.map.index.size,"прокат — одна картка")
        assertEquals("s1",app.state.value.map.index[0].id,"показуємо найближчу дату")
        assertEquals(3,app.state.value.map.index[0].sessionCount)

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
        assertTrue(app.state.value.map.events.single().isSeries)
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
        assertEquals("s2",app.state.value.detail.event?.id,"картка обраної дати одразу, без порожнього екрана")
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
        assertEquals("s1",app.state.value.detail.event?.id,"до відповіді на екрані лишається поточна дата")
        runCurrent()
        assertEquals("s1",app.state.value.detail.event?.id,"і після відмови сервера теж")
        assertNotNull(app.state.value.notice)

        // Подія без прокату так не поводиться: чужа картка на екрані була б неправдою.
        app.selectEvent("s1"); app.openEvent("невідомий")
        assertNull(app.state.value.detail.event)
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
        runCurrent();app.signUp(" new@poriad.app ","password1","Імʼя","1990-01-01");runCurrent()
        assertEquals("new@poriad.app",app.state.value.session.awaitingConfirmation)
        assertNull(app.state.value.notice)
        app.dismissConfirmationStep()
        assertNull(app.state.value.session.awaitingConfirmation)
        app.close()
    }
    @Test fun signUpWithSessionSkipsConfirmationStep()=runTest {
        val auth=Auth(); auth.session.value=null
        val app=app(Events(),backgroundScope,auth)
        runCurrent();app.signUp("new@poriad.app","password1","Імʼя","1990-01-01");runCurrent()
        assertNull(app.state.value.session.awaitingConfirmation)
        assertEquals(AppNotice.Told(AppMessage.ACCOUNT_CREATED),app.state.value.notice)
        assertTrue(app.state.value.signedIn)
        app.close()
    }
    /** Лист підтверджено або людина увійшла інакше: крок закривається сам. */
    @Test fun signingInClearsConfirmationStep()=runTest {
        val auth=Auth(); auth.session.value=null; auth.signUpSignsIn=false
        val app=app(Events(),backgroundScope,auth)
        runCurrent();app.signUp("new@poriad.app","password1","Імʼя","1990-01-01");runCurrent()
        assertNotNull(app.state.value.session.awaitingConfirmation)
        app.handleAuthCallback("poriad://auth/callback");runCurrent()
        assertNull(app.state.value.session.awaitingConfirmation)
        app.close()
    }
    /** Хибний поточний пароль зупиняє зміну до виклику updatePassword. */
    @Test fun changePasswordVerifiesCurrentFirst()=runTest {
        val auth=Auth().apply { currentPassword="right-one" }
        val app=app(Events(),backgroundScope,auth)
        runCurrent();app.changePassword("wrong-one","password1");runCurrent()
        assertFalse(auth.updated)
        assertEquals(AppNotice.Failed(AppError.InvalidCredentials),app.state.value.notice)
        app.changePassword("right-one","password1");runCurrent()
        assertTrue(auth.updated)
        assertEquals(AppNotice.Told(AppMessage.PASSWORD_CHANGED),app.state.value.notice)
        app.close()
    }
    @Test fun recoveryFlagSurvivesIdentityChange()=runTest {
        val app=app(Events(),backgroundScope)
        runCurrent();app.handleAuthCallback("poriad://auth/callback");runCurrent()
        assertTrue(app.state.value.session.passwordRecovery)
        app.close()
    }
    /** Перемикач профілю пише і в стан, і на пристрій, щоб пережити перезапуск. */
    @Test fun remindersToggleIsStoredOnTheDevice()=runTest {
        val app=app(Events(),backgroundScope)
        app.setRemindersEnabled(true)
        assertTrue(app.state.value.remindersEnabled); assertTrue(reminders.on)
        app.setRemindersEnabled(false)
        assertFalse(app.state.value.remindersEnabled); assertFalse(reminders.on)
        app.close()
    }
    /** Вихід чистить те саме, що й зміна акаунта: раніше крок нового пароля переживав вихід. */
    @Test fun signingOutForgetsTheRecoveryStep()=runTest {
        val app=app(Events(),backgroundScope)
        runCurrent();app.handleAuthCallback("poriad://auth/callback");runCurrent()
        app.signOut();runCurrent()
        assertFalse(app.state.value.session.passwordRecovery)
        assertEquals(null,app.state.value.session.userId)
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
    /** Фільтри й пошук мапи звужують лише мапу: головна лишається цілою і не перепитує сервер. */
    @Test fun mapFiltersLeaveHomeWhole()=runTest {
        val events=Events(); events.results=listOf(event("jazz","music","2090-01-05T19:00:00Z"),event("yoga","sport","2090-01-06T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        assertEquals(1,events.queries.size)
        assertEquals(2,app.state.value.home.index.size)

        app.setSearchText("jazz"); advanceTimeBy(1000); runCurrent()
        app.setOnlyAvailable(true); advanceTimeBy(1000); runCurrent()
        app.setDateFilter(DateFilter.TODAY); advanceTimeBy(1000); runCurrent()

        assertEquals(listOf("jazz"),app.state.value.map.index.map { it.id })
        assertEquals(setOf("jazz","yoga"),app.state.value.home.index.map { it.id }.toSet())
        assertTrue(events.queries.drop(1).all { it.text=="jazz" },"мапа без головної: ${events.queries}")
        assertTrue(app.state.value.home.index.all { it.id in app.state.value.cards },"картки головної пережили видачу мапи")
        app.close()
    }

    /** Пошук головної — свій запит в тій самій області; мапа його не бачить. */
    @Test fun homeSearchIsItsOwnQuery()=runTest {
        val events=Events(); events.results=listOf(event("jazz","music","2090-01-05T19:00:00Z"),event("yoga","sport","2090-01-06T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()

        app.setHomeSearchText("yoga"); advanceTimeBy(1000); runCurrent()

        val home=app.state.value.home
        assertEquals(listOf("yoga"),home.results.map { it.id })
        assertEquals(1,home.resultsTotal)
        assertFalse(home.searchLoading)
        assertEquals("yoga",events.queries.last().text)
        assertEquals("",app.state.value.map.searchText)
        assertEquals(2,app.state.value.map.index.size)

        app.setHomeSearchText(""); runCurrent()
        assertEquals(emptyList(),app.state.value.home.results)
        app.close()
    }

    /** Фільтри пошуку головної: «Усюди» — весь світ, категорія й дата йдуть на сервер; стрічка не звужується. */
    @Test fun homeSearchFiltersAndScope()=runTest {
        val events=Events(); events.results=listOf(event("jazz","music","2090-01-05T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        app.setHomeSearchEverywhere(true); runCurrent()
        val idle=events.queries.size
        assertEquals(idle,events.queries.size,"без тексту фільтр лише запам'ятовується")

        app.setHomeSearchText("jazz"); advanceTimeBy(1000); runCurrent()
        val world=events.queries.last()
        assertEquals(-90.0,world.south); assertEquals(180.0,world.east); assertEquals(null,world.category)

        app.setHomeSearchCategory("music"); runCurrent()
        assertEquals("music",events.queries.last().category)
        app.setHomeSearchDate(DateFilter.TODAY); runCurrent()
        assertTrue(events.queries.last().from!=null && events.queries.last().to!=null)

        app.setHomeSearchEverywhere(false); runCurrent()
        assertTrue(events.queries.last().south > -90.0,"назад до міста")
        assertEquals(1,app.state.value.home.index.size,"стрічка без фільтрів пошуку")

        app.setHomeSearchEverywhere(true); runCurrent()
        app.cancelHomeSearch(); runCurrent()
        val home=app.state.value.home
        assertEquals("",home.searchText); assertFalse(home.searchEverywhere)
        assertEquals(ALL_CATEGORIES,home.searchCategory); assertEquals(DateFilter.ANY,home.searchDate)
        assertEquals(emptyList(),home.results)
        app.close()
    }

    /** «Шукати тут» рухає лише мапу: головна лишається на цілому місті й не перепитує сервер. */
    @Test fun searchHereMovesOnlyTheMap()=runTest {
        val events=Events(); events.results=listOf(event("jazz","music","2090-01-05T19:00:00Z"),event("yoga","sport","2090-01-06T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        app.setHomeSearchText("yoga"); advanceTimeBy(1000); runCurrent()
        val before=events.queries.size

        app.searchArea(1.0,2.0,3.0,4.0); advanceTimeBy(1000); runCurrent()

        val fresh=events.queries.drop(before)
        assertEquals(1,fresh.size,"лише мапа: $fresh")
        assertEquals(1.0,fresh.single().south)
        assertTrue(app.state.value.city.custom)
        assertEquals(2,app.state.value.home.index.size)
        assertEquals(listOf("yoga"),app.state.value.home.results.map { it.id })
        app.close()
    }

    /** Нове місто при звуженій мапі: головна їде окремим запитом міста без фільтрів, пошук головної — теж. */
    @Test fun newCityReloadsHomeWithoutMapFilters()=runTest {
        val events=Events(); events.results=listOf(event("jazz","music","2090-01-05T19:00:00Z"),event("yoga","sport","2090-01-06T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        app.setSearchText("jazz"); advanceTimeBy(1000); runCurrent()
        app.setHomeSearchText("yoga"); advanceTimeBy(1000); runCurrent()
        app.searchArea(1.0,2.0,3.0,4.0); advanceTimeBy(1000); runCurrent()
        val before=events.queries.size

        val kharkiv=HomeLocation.covered.first { it.city=="Харків" }
        app.selectCity(CityResult(kharkiv.city,kharkiv.latitude,kharkiv.longitude)); advanceTimeBy(1000); runCurrent()

        val fresh=events.queries.drop(before)
        assertEquals(setOf("jazz",null,"yoga"),fresh.map { it.text }.toSet())
        assertTrue(fresh.all { it.south==kharkiv.south && it.north==kharkiv.north })
        assertFalse(app.state.value.city.custom)
        assertEquals(2,app.state.value.home.index.size)
        app.close()
    }

    /** Фільтр, поставлений до першої відповіді, не лишає головну без стрічки. */
    @Test fun filterDuringSharedLoadStillFillsHome()=runTest {
        val events=Events(); events.results=listOf(event("jazz","music","2090-01-05T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent()
        app.setOnlyAvailable(true); advanceTimeBy(1000); runCurrent()
        assertEquals(1,app.state.value.home.index.size)
        assertFalse(app.state.value.home.loading)
        assertTrue(events.queries.any { !it.available })
        app.close()
    }

    /** Мапа й головна просять той самий початок видачі: кожну картку питаємо раз. */
    @Test fun mapAndHomeDoNotAskForTheSameCardsTwice()=runTest {
        val events=Events(); events.results=(1..40).map { event("e${it.toString().padStart(2,'0')}","music","2090-01-01T10:00:00Z") }; events.inlineCards=0
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        val asked=events.cardRequests.flatten()
        assertEquals(asked.distinct(),asked)
        assertEquals(DiscoveryRules.FIRST_CARDS,app.state.value.home.events.size)
        app.close()
    }

    /** Перечитування «моїх» без зміни смаку не пересортовує видачу: піни не перебудовуються. */
    @Test fun reloadingMineKeepsTheIndexWhenTasteIsTheSame()=runTest {
        val events=Events(); events.results=listOf(event("a","music","2090-01-05T19:00:00Z"),event("b","art","2090-01-06T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        val version=app.state.value.map.indexVersion
        app.loadMyEvents(); advanceTimeBy(1000); runCurrent()
        assertEquals(version,app.state.value.map.indexVersion)
        app.close()
    }

    /** Платформа кличе resume одразу після старту: запит у дорозі не скасовується й не дублюється. */
    @Test fun resumeRightAfterLaunchDoesNotRepeatTheSearch()=runTest {
        val events=Events(); events.results=listOf(event("jazz","music","2090-01-05T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent()
        app.resume(); advanceTimeBy(1000); runCurrent()
        app.resume(); advanceTimeBy(1000); runCurrent()
        assertEquals(1,events.queries.size)
        assertEquals(1,app.state.value.map.index.size)

        backgroundScope.launch { app.reloadAll() }; advanceTimeBy(1000); runCurrent()
        assertEquals(2,events.queries.size,"потяг униз перечитує завжди")
        app.close()
    }

    /** Наступний запуск починає з останнього обраного міста: перший запит — уже туди. */
    @Test fun launchStartsFromTheRememberedCity()=runTest {
        val odesa=HomeLocation.covered.first { it.city=="Одеса" }
        val cities=Cities(CityResult(odesa.city,odesa.latitude,odesa.longitude))
        val events=Events(); val app=app(events,backgroundScope,cities=cities); runCurrent()
        assertEquals("Одеса",app.state.value.city.name)
        assertEquals(odesa.south,events.queries.single().south)
        app.close()
    }

    /** Обране місто запам'ятовується; те саме місто вдруге (геолокація на старті) не перечитує видачу. */
    @Test fun selectedCityIsRememberedAndTheSameCityCostsNothing()=runTest {
        val cities=Cities(); val events=Events(); val app=app(events,backgroundScope,cities=cities)
        runCurrent(); advanceTimeBy(1000); runCurrent()
        val kharkiv=CityResult("Харків",49.9935,36.2304)
        app.selectCity(kharkiv); advanceTimeBy(1000); runCurrent()
        assertEquals(kharkiv,cities.stored)
        val before=events.queries.size

        app.selectCity(CityResult("Харків",49.99,36.23)); advanceTimeBy(1000); runCurrent()
        assertEquals(before,events.queries.size)
        assertEquals(kharkiv,cities.stored)
        app.close()
    }

    @Test fun availabilityIsPartOfServerQuery()=runTest {
        val events=Events();val app=app(events,backgroundScope)
        runCurrent();app.setOnlyAvailable(true);runCurrent()
        assertTrue(events.queries.last().available)
        assertTrue(app.state.value.map.onlyAvailable);app.close()
    }

    @Test fun answeringTheOpeningQuestionsEndsThemAndReordersWhatWasFound()=runTest {
        val events=Events(); events.results=listOf(event("social-later","social","2090-01-06T19:00:00Z"),event("music-sooner","music","2090-01-05T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        assertTrue(app.state.value.needsOnboarding)
        assertEquals("music-sooner",app.state.value.map.index.first().id)
        // Лише інтереси: вплив слотів на порядок — предмет TasteRankingTest.
        app.saveTaste(listOf("social"),emptyList(),Crowd.ANY); runCurrent()
        assertFalse(app.state.value.needsOnboarding)
        // Збережено на наступний запуск, обрана категорія веде список.
        assertEquals(listOf("social"),taste.stored.interests)
        assertTrue(taste.stored.answered)
        assertEquals("social-later",app.state.value.map.index.first().id)
        assertEquals(listOf("social-later"),app.state.value.map.suggested.map { it.id })
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
        assertTrue(app.state.value.map.suggested.isEmpty())
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
        assertNull(app.state.value.detail.event)
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

    /** Чат: відкриття тягне хвіст, відправлення обрізає текст і дописує нове, закриття зупиняє опитування. */
    @Test fun chatPollsWhileOpenAndStopsWhenClosed()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        events.chatMessages=listOf(ChatMessage("m0","ev","host","Host",null,"Привіт","2026-09-16T09:00:00Z"))
        app.openChat("ev"); runCurrent()
        assertEquals(listOf("m0"),app.state.value.chat?.messages?.map { it.id })
        assertFalse(app.state.value.chat!!.loading)

        app.sendMessage("  Буду о сьомій  "); runCurrent()
        assertEquals(listOf("ev" to "Буду о сьомій"),events.sent)
        assertEquals(listOf("m0","m1"),app.state.value.chat?.messages?.map { it.id })

        app.sendMessage("   "); runCurrent()
        assertEquals(1,events.sent.size,"порожнє не летить на сервер")
        assertIs<AppNotice.Failed>(app.state.value.notice)

        // Хтось інший написав: наступне опитування підхопить лише нове.
        events.chatMessages=events.chatMessages+ChatMessage("m9","ev","other","Інший",null,"Ок","2026-09-16T10:30:00Z")
        advanceTimeBy(ChatRules.POLL_INTERVAL_MS+1); runCurrent()
        assertEquals(listOf("m0","m1","m9"),app.state.value.chat?.messages?.map { it.id })

        app.closeChat(); runCurrent()
        assertNull(app.state.value.chat)
        app.close()
    }

    /** Непрочитане: відкриття чату знімає бейдж і позначає прочитаним; нове чуже дзвонить раз. */
    @Test fun unreadChatsRingOnceAndClearWhenOpened()=runTest {
        val events=Events()
        val seen=object:SeenRequestStore { val keys=mutableSetOf<String>(); override fun seen()=keys.toSet(); override fun markSeen(keys:Set<String>) { this.keys+=keys } }
        val rung=mutableListOf<ChatAlert>()
        val app=PoruchApp(
            events=events, saved=events, authoring=events, participation=events, requests=events, chat=events,
            auth=Auth(), geo=object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },
            eventActions=EventActions(events,events,Auth()), accountActions=AccountActions(Auth()),
            safety=safety, tasteStore=taste, scope=backgroundScope,
            reminderStore=object:ReminderPreferenceStore { override fun enabled()=true; override fun setEnabled(enabled:Boolean) {} },
            seenMessages=seen, chatNotifier=object:ChatNotifier { override fun notifyMessages(alerts:List<ChatAlert>) { rung+=alerts } }
        )
        events.unreadChats=listOf(ChatUnread("ev","Настілки",2,"m9","Інший","Ок","2026-09-16T10:30:00Z"))
        app.loadMyEvents(); advanceTimeBy(200); runCurrent()
        assertEquals(1,app.state.value.unreadChats)
        assertEquals(listOf(ChatAlert("ev","Настілки",2,"Інший","Ок")),rung)

        app.loadMyEvents(); advanceTimeBy(200); runCurrent()
        assertEquals(1,rung.size,"те саме повідомлення не дзвонить удруге")

        app.openChat("ev"); runCurrent()
        assertEquals(0,app.state.value.unreadChats,"відкритий чат більше не непрочитаний")
        assertEquals(listOf("ev"),events.readMarks)
        app.close()
    }

    /** Новий запит дзвонить раз: після перечитування ті самі ключі вже «бачені». */
    @Test fun aNewJoinRequestRingsOnceAndShowsOnTheFeed()=runTest {
        val events=Events()
        val mine=event("mine","games","2090-01-01T10:00:00Z").let { it.copy(gathering=it.gathering!!.copy(organizerId="user")) }
        val seen=object:SeenRequestStore { val keys=mutableSetOf<String>(); override fun seen()=keys.toSet(); override fun markSeen(keys:Set<String>) { this.keys+=keys } }
        val rung=mutableListOf<RequestAlert>()
        val app=PoruchApp(
            events=events, saved=events, authoring=events, participation=events, requests=events, chat=events,
            auth=Auth(), geo=object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },
            eventActions=EventActions(events,events,Auth()), accountActions=AccountActions(Auth()),
            safety=safety, tasteStore=taste, scope=backgroundScope,
            reminderStore=object:ReminderPreferenceStore { override fun enabled()=true; override fun setEnabled(enabled:Boolean) {} },
            seenRequests=seen, requestNotifier=object:RequestNotifier { override fun notify(alerts:List<RequestAlert>) { rung+=alerts } }
        )
        events.pending=listOf(JoinRequest("mine","guest","Гість",null,"2026-09-16T10:00:00Z"))
        events.mine=listOf(mine)
        app.loadMyEvents(); advanceTimeBy(200); runCurrent()
        assertEquals(listOf(RequestAlert("mine","mine",1)),rung)
        assertEquals(1,app.state.value.library.pendingRequests.size)

        app.loadMyEvents(); advanceTimeBy(200); runCurrent()
        assertEquals(1,rung.size,"той самий запит не дзвонить удруге")
        app.close()
    }


    // ---- Аудит 2026-09-23

    /** «Усі» — без меж дати: застиглий `from = now` ховав події, що вже тривають. */
    @Test fun theAnyDateFilterHasNoBounds()=runTest {
        val events=Events(); val app=app(events,backgroundScope); runCurrent()
        app.setDateFilter(DateFilter.TODAY); runCurrent()
        assertNotNull(events.queries.last().from)
        app.setDateFilter(DateFilter.ANY); runCurrent()
        assertNull(events.queries.last().from); assertNull(events.queries.last().to)
        app.close()
    }

    /** Пуш приходить з фонового потоку FCM: стан змінюється лише в scope застосунку. */
    @Test fun aPushIsHandledOnTheAppScope()=runTest {
        val events=Events()
        val seen=object:SeenRequestStore { val keys=mutableSetOf<String>(); override fun seen()=keys.toSet(); override fun markSeen(keys:Set<String>) { this.keys+=keys } }
        val app=PoruchApp(
            events=events, saved=events, authoring=events, participation=events, requests=events, chat=events,
            auth=Auth(), geo=object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },
            eventActions=EventActions(events,events,Auth()), accountActions=AccountActions(Auth()),
            seenMessages=seen, chatNotifier=object:ChatNotifier { override fun notifyMessages(alerts:List<ChatAlert>) {} }, scope=backgroundScope
        )
        app.pushReceived("chat","m1")
        assertTrue(seen.keys.isEmpty(),"не в потоці виклику")
        runCurrent()
        assertEquals(setOf("m1"),seen.keys)
        app.close()
    }

    /** Вихід не лишає «Ви йдете» на картках: вони належать акаунту. */
    @Test fun signingOutLeavesNoMembershipInTheCards()=runTest {
        val events=Events(); events.results=listOf(event("mine","games","2090-01-05T19:00:00Z").let { it.copy(gathering=it.gathering!!.copy(joined=true)) })
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        assertTrue(app.state.value.cards.getValue("mine").gathering!!.joined)
        app.signOut(); runCurrent()
        assertTrue(app.state.value.cards.isEmpty())
        assertTrue(app.state.value.home.events.isEmpty() && app.state.value.map.events.isEmpty())
        app.close()
    }

    /** Прострочений токен при виході: локально вийшли, банера помилки нема. */
    @Test fun signingOutWithAnExpiredTokenShowsNoError()=runTest {
        val auth=Auth().apply { signOutRefused=true }
        val app=app(Events(),backgroundScope,auth); runCurrent()
        app.signOut(); runCurrent()
        assertNull(app.state.value.session.userId)
        assertNull(app.state.value.notice)
        app.close()
    }

    /** Текст, що не пішов, повертається через стан один раз; закриття екрана відправлення не скасовує. */
    @Test fun aFailedMessageComesBackAndClosingDoesNotCancelSending()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        app.openChat("ev"); runCurrent()
        events.failSend=true
        app.sendMessage("Буду о сьомій"); runCurrent()
        assertEquals("Буду о сьомій",app.state.value.chat?.failedDraft)
        assertEquals("Буду о сьомій",app.consumeFailedDraft())
        assertNull(app.consumeFailedDraft())

        events.failSend=false; events.slowSend=true
        app.sendMessage("Ще одне"); runCurrent()
        app.closeChat(); advanceTimeBy(200); runCurrent()
        assertEquals(listOf("ev" to "Ще одне"),events.sent)
        app.close()
    }

    /** Дія з подією перечитує її картку, а не індекс міста. */
    @Test fun joiningReloadsTheCardNotTheWholeCity()=runTest {
        val events=Events(); events.results=listOf(event("e","games","2090-01-05T19:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        val searches=events.queries.size; events.cardRequests.clear()
        events.results=listOf(event("e","games","2090-01-05T19:00:00Z").let { it.copy(gathering=it.gathering!!.copy(joined=true)) })
        app.joinEvent("e"); runCurrent(); advanceTimeBy(1000); runCurrent()
        assertEquals(searches,events.queries.size)
        assertEquals(listOf(listOf("e")),events.cardRequests)
        assertTrue(app.state.value.cards.getValue("e").gathering!!.joined)
        app.close()
    }

    /** Закладка, поставлена поки «мої» в дорозі, не зникає з відповіддю, що її ще не бачила. */
    @Test fun aSaveMadeDuringALoadSurvivesIt()=runTest {
        val events=Events(); val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        app.loadMyEvents(); app.toggleSaved("e"); runCurrent()
        assertTrue(app.state.value.isSaved("e"))
        app.close()
    }

    /** Тимчасовий збій доповнень лишає відоме: без цього 504 знову питав вік. */
    @Test fun aFailedOptionalReadKeepsWhatWasKnown()=runTest {
        val events=Events(); events.pending=listOf(JoinRequest("mine","guest","Гість",null,"2026-09-16T10:00:00Z"))
        val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        assertTrue(app.state.value.library.account.ageDeclared)
        safety.fail=true; events.failPending=true
        app.loadMyEvents(); runCurrent()
        assertTrue(app.state.value.library.account.ageDeclared)
        assertEquals(1,app.state.value.library.pendingRequests.size)
        assertFalse(app.state.value.library.loading)
        app.close()
    }

    /** Інтереси акаунта, що вийшов, не переходять наступному. */
    @Test fun anAccountsInterestsDoNotMoveToTheNextOne()=runTest {
        val app=app(Events(),backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
        app.saveTaste(listOf("music"),emptyList(),Crowd.ANY); runCurrent()
        app.handleAuthCallback("poriad://auth/callback"); runCurrent(); advanceTimeBy(1000); runCurrent()
        assertEquals("recovered",app.state.value.session.userId)
        assertEquals(emptyList(),app.state.value.interests)
        app.close()
    }

    /** `event_view` — відкриті деталі, а не кроки каруселі й не перечитування. Деталі мають свій прапорець завантаження. */
    @Test fun anEventViewIsCountedOncePerOpening()=runTest {
        val tracked=mutableListOf<String>()
        PoruchAnalytics.sink={ name,_ -> tracked+=name }
        try {
            val events=Events(); events.results=listOf(event("a","art","2090-01-05T19:00:00Z"),event("b","art","2090-01-06T19:00:00Z"))
            val app=app(events,backgroundScope); runCurrent(); advanceTimeBy(1000); runCurrent()
            app.selectEvent("a"); app.selectEvent("b"); runCurrent()
            assertEquals(0,tracked.count { it=="event_view" })
            app.openEvent("b")
            assertTrue(app.state.value.detail.loading)
            runCurrent()
            assertFalse(app.state.value.detail.loading)
            app.resume(); runCurrent()
            assertEquals(1,tracked.count { it=="event_view" })
            app.close()
        } finally { PoruchAnalytics.sink=null }
    }

    /** Перемикач аналітики: пристрій, стан, платформний хук; вимкнено — у сінк нічого. */
    @Test fun turningAnalyticsOffStopsEventsAndTellsThePlatform()=runTest {
        val tracked=mutableListOf<String>(); val collection=mutableListOf<Boolean>()
        val stored=object:AnalyticsPreferenceStore { var on=true; override fun enabled()=on; override fun setEnabled(enabled:Boolean) { on=enabled } }
        PoruchAnalytics.sink={ name,_ -> tracked+=name }
        try {
            val events=Events()
            val app=PoruchApp(
                events=events, saved=events, authoring=events, participation=events, requests=events, chat=events,
                auth=Auth(), geo=object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },
                eventActions=EventActions(events,events,Auth()), accountActions=AccountActions(Auth()),
                analyticsStore=stored, scope=backgroundScope
            )
            PoruchAnalytics.collection={ collection+=it }
            assertEquals(listOf(true),collection,"хук отримує поточне значення одразу")
            app.setAnalyticsEnabled(false)
            assertFalse(stored.on); assertFalse(app.state.value.analyticsEnabled)
            assertEquals(listOf(true,false),collection)
            PoruchAnalytics.track("login")
            assertTrue(tracked.isEmpty())
            app.close()
        } finally { PoruchAnalytics.sink=null; PoruchAnalytics.collection=null; PoruchAnalytics.enabled=true }
    }

    /** Запит до події без назви (мої ще не доїхали) не позначається баченим: задзвонить пізніше. */
    @Test fun aRequestWithoutATitleIsNotMarkedSeen()=runTest {
        val events=Events()
        val seen=object:SeenRequestStore { val keys=mutableSetOf<String>(); override fun seen()=keys.toSet(); override fun markSeen(keys:Set<String>) { this.keys+=keys } }
        val app=PoruchApp(
            events=events, saved=events, authoring=events, participation=events, requests=events, chat=events,
            auth=Auth(), geo=object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },
            eventActions=EventActions(events,events,Auth()), accountActions=AccountActions(Auth()),
            safety=safety, tasteStore=taste, scope=backgroundScope,
            reminderStore=object:ReminderPreferenceStore { override fun enabled()=true; override fun setEnabled(enabled:Boolean) {} },
            seenRequests=seen, requestNotifier=object:RequestNotifier { override fun notify(alerts:List<RequestAlert>) {} }
        )
        events.pending=listOf(JoinRequest("unknown","guest","Гість",null,"2026-09-16T10:00:00Z"))
        app.loadMyEvents(); advanceTimeBy(200); runCurrent()
        assertTrue(seen.keys.isEmpty())
        app.close()
    }

    /** Свій профіль приходить разом із «моїми» і зникає з акаунтом. */
    @Test fun ownProfileLoadsWithTheAccountAndLeavesWithIt()=runTest {
        val app=app(Events(),backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        assertEquals("me@example.invalid",app.state.value.library.profile?.email)
        app.signOut(); runCurrent()
        assertNull(app.state.value.library.profile)
        app.close()
    }

    /** Нове фото стає профілем, і лише тоді зникає старий файл; прибрати фото — теж прибрати файл. */
    @Test fun replacingTheAvatarRemovesTheOldFileAfterwards()=runTest {
        val app=app(Events(),backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        app.setAvatar(byteArrayOf(1),"image/jpeg"); runCurrent()
        assertEquals("https://test.invalid/avatar/1.jpg",app.state.value.library.profile?.avatarUrl)
        assertTrue(profiles.deleted.isEmpty())
        app.setAvatar(byteArrayOf(2),"image/jpeg"); runCurrent()
        assertEquals(listOf("https://test.invalid/avatar/1.jpg"),profiles.deleted)
        app.removeAvatar(); runCurrent()
        assertNull(app.state.value.library.profile?.avatarUrl)
        assertEquals("https://test.invalid/avatar/2.jpg",profiles.deleted.last())
        app.close()
    }

    /** Імʼя перевіряється до сервера, «Про себе» зберігається обрізаним. */
    @Test fun savingTheProfileValidatesTheNameAndTrimsTheBio()=runTest {
        val app=app(Events(),backgroundScope); runCurrent(); advanceTimeBy(101); runCurrent()
        app.saveProfile(" ",null); runCurrent()
        assertEquals(AppNotice.Failed(AppError.InvalidName),app.state.value.notice)
        app.saveProfile(" Оля ","  Люблю настолки  "); runCurrent()
        assertEquals("Оля",app.state.value.library.profile?.name)
        assertEquals("Люблю настолки",app.state.value.library.profile?.bio)
        app.close()
    }

    /** Картка іншої людини: запізніла відповідь для попередньої не перезаписує відкриту. */
    @Test fun aLateCardForAnotherPersonIsDropped()=runTest {
        profiles.cards=mapOf("a" to Profile("a","А",null,null,null,1,2),"b" to Profile("b","Б",null,null,null,0,0))
        profiles.slow=setOf("a")
        val app=app(Events(),backgroundScope); runCurrent()
        app.openPerson("a"); runCurrent()
        assertTrue(app.state.value.person?.loading==true)
        app.openPerson("b"); runCurrent(); advanceTimeBy(101); runCurrent()
        assertEquals("Б",app.state.value.person?.profile?.name)
        app.openPerson("hidden"); runCurrent()
        assertEquals(PersonState("hidden",null,loading=false),app.state.value.person)
        app.closePerson(); runCurrent()
        assertNull(app.state.value.person)
        app.close()
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

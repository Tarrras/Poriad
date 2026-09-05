package app.poruch.shared

import app.poruch.domain.*
import app.poruch.events.EventActions
import app.poruch.account.AccountActions
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.datetime.*
import kotlin.time.Clock
import kotlin.uuid.Uuid
import kotlin.uuid.ExperimentalUuidApi

/** Owns presentation jobs; a screen observer never owns the network client. */
class PoruchApp internal constructor(
    private val events: EventRepository, private val auth: AuthRepository,
    private val geo: GeoSearchRepository, private val eventActions: EventActions,
    private val accountActions: AccountActions,
    private val preferences: PreferencesRepository? = null,
    private val creationIdentity: CreationIdentityStore? = null,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
) {
    private val mutable = MutableStateFlow(AppState(userId=auth.session.value?.userId))
    val state: StateFlow<AppState> = mutable.asStateFlow()
    private var query = EventQuery(50.30,30.25,50.60,30.80)
    private var discoveryJob: Job? = null
    private var cityJob: Job? = null
    private var detailJob: Job? = null
    private var myEventsJob: Job? = null
    private var mutationJob: Job? = null
    private var pendingCreation: Pair<EventDraft,String>? = null
    private var selectedId: String? = null
    init {
        scope.launch {
            auth.session.map { it?.userId }.distinctUntilChanged().collect { uid ->
                synchronizeIdentity(uid)
            }
        }
        refresh()
        if (state.value.userId != null) loadMyEvents()
    }
    private fun synchronizeIdentity(uid: String?) {
        val changed = mutable.value.userId != uid
        mutable.update { it.copy(userId=uid, savedIds=if(changed) emptyList() else it.savedIds, myEvents=if(changed) emptyList() else it.myEvents,interests=if(changed) emptyList() else it.interests) }
        if (changed) {
            myEventsJob?.cancel(); detailJob?.cancel(); selectedId=null; pendingCreation=null
            mutable.update { it.copy(events=emptyList(),selectedEvent=null,passwordRecovery=false,completedEventId=null) }
            events.clearPrivateCache(); refresh(); if (uid != null) loadMyEvents()
        }
    }
    fun observe(onChange: (AppState) -> Unit): Subscription {
        val job = scope.launch { state.collect { onChange(it) } }
        return Subscription { job.cancel() }
    }
    fun refresh() {
        discoveryJob?.cancel()
        val snapshot = query
        discoveryJob = scope.launch {
            mutable.update { it.copy(loading=true) }
            try {
                val result = events.discover(snapshot)
                mutable.update { it.copy(events=result,loading=false,offline=false,message=if(result.size>=300) "Збільшіть масштаб мапи, щоб побачити всі події в цій області" else it.message) }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) {
                val cached = events.cached(snapshot)
                mutable.update { it.copy(events=cached,loading=false,offline=true,message=message(e)) }
            }
        }
    }
    fun searchArea(south: Double, west: Double, north: Double, east: Double) {
        if (listOf(south,west,north,east).any { !it.isFinite() } || south > north) return
        query=query.copy(south=south.coerceIn(-90.0,90.0),west=west.coerceIn(-180.0,180.0),north=north.coerceIn(-90.0,90.0),east=east.coerceIn(-180.0,180.0)); refresh()
    }
    fun setCategory(category: String) {
        mutable.update { it.copy(category=category) }; query=query.copy(category=category.takeUnless { it=="all" }); refresh()
    }
    fun setDateFilter(filter: String) {
        val zone = TimeZone.currentSystemDefault()
        val now = Clock.System.now(); val today=now.toLocalDateTime(zone).date
        val start = when(filter) {
            "today" -> today.atStartOfDayIn(zone)
            "weekend" -> today.plus(((6-today.dayOfWeek.isoDayNumber).coerceAtLeast(0)),DateTimeUnit.DAY).atStartOfDayIn(zone)
            else -> now
        }
        val end = when(filter) {
            "today" -> today.plus(1,DateTimeUnit.DAY).atStartOfDayIn(zone)
            "weekend" -> today.plus((8-today.dayOfWeek.isoDayNumber),DateTimeUnit.DAY).atStartOfDayIn(zone)
            else -> null
        }
        mutable.update { it.copy(dateFilter=filter) }; query=query.copy(from=start.toString(),to=end?.toString()); refresh()
    }
    fun selectEvent(id: String) {
        selectedId=id; detailJob?.cancel()
        mutable.update { it.copy(selectedEvent=(it.events+it.myEvents).firstOrNull { event -> event.id==id }) }
        detailJob=scope.launch {
            try { val event=events.details(id); if(selectedId==id) mutable.update { it.copy(selectedEvent=event,message=if(event==null) "Подія недоступна" else it.message) } }
            catch(e: CancellationException) { throw e }
            catch(e: Exception) { mutable.update { it.copy(message=message(e)) } }
        }
    }
    fun dismissEvent() { selectedId=null; detailJob?.cancel(); mutable.update { it.copy(selectedEvent=null) } }
    fun loadMyEvents() {
        if(auth.session.value==null) return
        myEventsJob?.cancel()
        myEventsJob=scope.launch {
            try {
                val mine=events.myEvents(); val saved=events.savedIds(); val interests=preferences?.interests().orEmpty()
                mutable.update { it.copy(myEvents=mine,savedIds=saved,interests=interests) }
            } catch(e: CancellationException) { throw e }
            catch(e: Exception) { mutable.update { it.copy(message=message(e)) } }
        }
    }
    private fun mutate(block: suspend () -> Unit) {
        if(mutationJob?.isActive==true) return
        mutationJob=scope.launch {
            mutable.update { it.copy(mutating=true,message=null) }
            try { block() }
            catch(e: CancellationException) { throw e }
            catch(e: Exception) { mutable.update { it.copy(message=message(e)) } }
            finally { mutable.update { it.copy(mutating=false) } }
        }
    }
    private fun changed(id: String) { refresh(); loadMyEvents(); if(selectedId==id) selectEvent(id) }
    fun joinEvent(id: String) = mutate { eventActions.join(id); changed(id); mutable.update { it.copy(message="Ви приєдналися до події") } }
    fun leaveEvent(id: String) = mutate { eventActions.leave(id); changed(id) }
    fun cancelEvent(id: String) = mutate { eventActions.cancel(id); changed(id) }
    fun toggleSaved(id: String) = mutate {
        if(auth.session.value==null) throw AppException(Failure.AUTH,"Увійдіть, щоб зберігати події")
        if(id in state.value.savedIds) events.unsave(id) else events.save(id)
        val saved=events.savedIds(); mutable.update { it.copy(savedIds=saved) }; loadMyEvents()
    }
    fun signIn(email: String, password: String) = mutate { accountActions.signIn(email,password); mutable.update { it.copy(message="Ви увійшли") }; refresh(); loadMyEvents() }
    fun signUp(email: String, password: String, name: String) = mutate {
        val signedIn=accountActions.signUp(email,password,name)
        mutable.update { it.copy(message=if(signedIn) "Обліковий запис створено" else "Підтвердьте email за посиланням у листі, потім увійдіть") }
    }
    fun signOut() = mutate {
        myEventsJob?.cancel(); detailJob?.cancel()
        try { auth.signOut() } finally {
            events.clearPrivateCache(); selectedId=null
            mutable.update { it.copy(myEvents=emptyList(),savedIds=emptyList(),selectedEvent=null,userId=null) }; refresh()
        }
    }
    @OptIn(ExperimentalUuidApi::class)
    fun createEvent(draft: EventDraft) = mutate {
        val id = creationIdentity?.idFor(draft) ?: pendingCreation?.takeIf { it.first==draft }?.second ?: Uuid.random().toString().also { pendingCreation=draft to it }
        val created=eventActions.create(id,draft); pendingCreation=null; creationIdentity?.clear(); changed(created); selectEvent(created)
        mutable.update { it.copy(message="Подію опубліковано",completedEventId=created) }
    }
    fun updateEvent(id: String, draft: EventDraft) = mutate { eventActions.update(id,draft); changed(id); mutable.update { it.copy(message="Зміни збережено",completedEventId=id) } }
    fun toggleInterest(category: String) = mutate {
        if (category !in setOf("music","sport","art","food","games","outdoors","social")) return@mutate
        val selected=state.value.interests
        val next=if(category in selected) selected-category else selected+category
        preferences?.setInterests(next) ?: throw AppException(Failure.AUTH,"Увійдіть, щоб зберегти інтереси")
        mutable.update { it.copy(interests=next) }
    }
    fun clearCompletedEvent() { mutable.update { it.copy(completedEventId=null) } }
    fun uploadEventImage(eventId: String, bytes: ByteArray, contentType: String) = mutate {
        val event=events.details(eventId) ?: throw AppException(Failure.VALIDATION,"Подія недоступна")
        if(event.organizerId!=auth.session.value?.userId) throw AppException(Failure.FORBIDDEN,"Фото додає організатор")
        val url=events.uploadImage(eventId,bytes,contentType)
        events.update(eventId,EventDraft(event.title,event.description,event.category,event.city,event.address,event.latitude,event.longitude,event.startsAt,event.endsAt,event.timeZone,event.capacity,url))
        changed(eventId); mutable.update { it.copy(message="Фото додано") }
    }
    fun requestPasswordReset(email: String) = mutate {
        if (!email.contains("@")) throw AppException(Failure.VALIDATION,"Вкажіть коректний email")
        auth.requestPasswordReset(email)
        mutable.update { it.copy(message="Якщо обліковий запис існує, лист для відновлення вже надіслано") }
    }
    fun updatePassword(password: String) = mutate {
        if (password.length < 8) throw AppException(Failure.VALIDATION,"Пароль має містити щонайменше 8 символів")
        auth.updatePassword(password)
        mutable.update { it.copy(passwordRecovery=false,message="Пароль змінено") }
    }
    fun handleAuthCallback(url: String) = mutate {
        val recovery=auth.handleCallback(url)
        synchronizeIdentity(auth.session.value?.userId)
        mutable.update { it.copy(passwordRecovery=recovery,message=if(recovery) "Вкажіть новий пароль у профілі" else "Email підтверджено") }
        refresh(); loadMyEvents()
    }
    fun clearMessage() { mutable.update { it.copy(message=null) } }
    fun searchCity(query: String) {
        cityJob?.cancel()
        if(query.trim().length<2) { mutable.update { it.copy(cities=emptyList()) }; return }
        cityJob=scope.launch {
            delay(400)
            try { val result=geo.search(query); mutable.update { it.copy(cities=result) } }
            catch(e: CancellationException) { throw e }
            catch(e: Exception) { mutable.update { it.copy(message=message(e)) } }
        }
    }
    fun selectCity(city: CityResult) {
        mutable.update { it.copy(cityName=city.name,cityLatitude=city.latitude,cityLongitude=city.longitude,cities=emptyList()) }
        searchArea(city.latitude-0.15,city.longitude-0.25,city.latitude+0.15,city.longitude+0.25)
    }
    private fun message(error: Exception) = if(error is AppException) error.message ?: "Не вдалося виконати дію" else "Не вдалося виконати дію. Спробуйте ще раз"
    fun close() { scope.cancel() }
}

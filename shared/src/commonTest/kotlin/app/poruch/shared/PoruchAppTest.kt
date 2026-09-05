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
        override suspend fun signUp(email:String,password:String,name:String)=true
        override suspend fun signOut() { session.value=null }
        override suspend fun accessToken()=session.value?.accessToken
        override suspend fun requestPasswordReset(email:String) {}
        override suspend fun updatePassword(password:String) {}
        override suspend fun handleCallback(url:String):Boolean { session.value=UserSession("recovered","new","refresh",9999999999); return true }
    }
    private class Events: EventRepository {
        val queries=mutableListOf<EventQuery>()
        val createIds=mutableListOf<String>()
        var failCreate=false
        override suspend fun discover(query:EventQuery):List<Event> { queries+=query; delay(100); return emptyList() }
        override fun cached(query:EventQuery)=emptyList<Event>()
        override suspend fun details(id:String):Event?=null
        override suspend fun myEvents()=emptyList<Event>()
        override suspend fun savedIds()=emptyList<String>()
        override suspend fun save(id:String) {}
        override suspend fun unsave(id:String) {}
        override suspend fun create(id:String,draft:EventDraft):String { createIds+=id; if(failCreate) throw AppException(Failure.NETWORK,"offline"); return id }
        override suspend fun update(id:String,draft:EventDraft)=id
        override suspend fun join(id:String) {}
        override suspend fun leave(id:String) {}
        override suspend fun cancel(id:String) {}
        override suspend fun uploadImage(eventId:String,bytes:ByteArray,contentType:String)="https://test.invalid/image.jpg"
        override fun clearPrivateCache() {}
    }
    private fun app(events:Events,scope:CoroutineScope):PoruchApp {
        val auth=Auth()
        return PoruchApp(events,auth,object:GeoSearchRepository { override suspend fun search(query:String)=emptyList<CityResult>() },EventActions(events,auth),AccountActions(auth),scope=scope)
    }
    @Test fun replacementQueryCancelsPreviousDiscovery()=runTest {
        val events=Events(); val app=app(events,backgroundScope)
        runCurrent(); app.searchArea(1.0,2.0,3.0,4.0); runCurrent()
        assertEquals(2,events.queries.size)
        assertEquals(1.0,events.queries.last().south)
        advanceTimeBy(101);runCurrent()
        assertFalse(app.state.value.loading);app.close()
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
        assertTrue(events.createIds.isEmpty());assertNotNull(app.state.value.message);app.close()
    }
    @Test fun recoveryFlagSurvivesIdentityChange()=runTest {
        val app=app(Events(),backgroundScope)
        runCurrent();app.handleAuthCallback("poruch://auth/callback");runCurrent()
        assertTrue(app.state.value.passwordRecovery)
        app.close()
    }

}

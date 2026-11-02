package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import kotlin.test.*

/** Редактор без входу (docs/organizers-1.5.md, хвиля 2): вхід — на «Опублікувати», публікація — сама після нього. */
@OptIn(ExperimentalCoroutinesApi::class)
class GuestPublishTest {
    private val walk=EventDraft("Прогулянка","Зустріч у центрі міста",EventCategory.OUTDOORS,"Київ","Поділ",50.45,30.5,"2090-01-01T10:00:00Z","2090-01-01T12:00:00Z","Europe/Kyiv",10)

    @Test fun aGuestPublishesAfterSigningIn()=runTest {
        val tracked=mutableListOf<Pair<String,Map<String,String>>>()
        PoruchAnalytics.sink={ name,params -> tracked+=name to params }
        try {
            val events=Events(); val auth=Auth(); auth.session.value=null
            val app=testApp(events,backgroundScope,auth)
            runCurrent()
            app.createStep("about",draft=false,mediaCount=0)
            app.createEvent(walk); runCurrent()
            assertTrue(events.createIds.isEmpty(),"nothing reaches the server before the sign-in")
            assertTrue(app.state.value.publishAfterSignIn)
            assertNull(app.state.value.notice,"the wall is the sign-in screen, not a banner")

            auth.session.value=UserSession("user","token","refresh",9999999999); advanceTimeBy(1000); runCurrent()
            assertEquals(1,events.createIds.size,"published by itself")
            assertEquals(events.createIds.single(),app.state.value.completedEventId)
            assertFalse(app.state.value.publishAfterSignIn)
            assertEquals(
                listOf("create_step" to "true","auth_wall" to "create"),
                tracked.filter { it.first=="create_step" || it.first=="auth_wall" }.map { it.first to (it.second["guest"] ?: it.second["action"]) }
            )
            assertEquals(1,tracked.count { it.first=="event_create" })

            // Ще один вхід (оновлення токена, повернення) нічого не публікує вдруге.
            app.resume(); advanceTimeBy(1000); runCurrent()
            assertEquals(1,events.createIds.size)
            app.close()
        } finally { PoruchAnalytics.sink=null }
    }

    /** Хибна чернетка гостя — та сама підсвітка полів, що й з входом, і без стіни входу. */
    @Test fun aGuestSeesFieldErrorsFirst()=runTest {
        val auth=Auth(); auth.session.value=null
        val app=testApp(Events(),backgroundScope,auth)
        runCurrent(); app.createEvent(walk.copy(title="")); runCurrent()
        assertFalse(app.state.value.publishAfterSignIn)
        assertEquals(AppError.InvalidDraft(listOf(DraftField.TITLE)),(app.state.value.notice as AppNotice.Failed).error)
        app.close()
    }

    /** Новий акаунт з коду без віку: вік з рядка згоди ставиться мовчки, і публікація йде одразу, без кроку галочки. */
    @Test fun aNewAccountPublishesRightAfterSignIn()=runTest {
        val events=Events(); val auth=Auth(); auth.session.value=null
        val safety=Safety(AccountFacts())
        val app=testApp(events,backgroundScope,auth,safety=safety)
        runCurrent(); app.createEvent(walk); runCurrent()
        app.sendSignInCode("web@poriad.app"); runCurrent()
        app.verifySignInCode("web@poriad.app","123456"); advanceTimeBy(1000); runCurrent()
        assertFalse(app.state.value.session.askBirthDate)
        assertEquals(1,safety.adultConfirmations)
        assertEquals(1,events.createIds.size)
        assertEquals(events.createIds.single(),app.state.value.completedEventId)
        app.close()
    }

    /**
     * Сервер не знайшов віку, хоч факти акаунта не прочитались і галочку ми не питали: тепер питаємо її, а не висимо мовчки.
     * Це не `create_failed`: попереду крок, а не відмова.
     */
    @Test fun anUnknownAgeAsksForTheCheckbox()=runTest {
        val tracked=mutableListOf<String>()
        PoruchAnalytics.sink={ name,_ -> tracked+=name }
        try {
            val events=Events(); val auth=Auth(); auth.session.value=null
            val app=testApp(events,backgroundScope,auth)
            events.createError=AppError.AgeRequired
            runCurrent(); app.createEvent(walk); runCurrent()
            auth.session.value=UserSession("user","token","refresh",9999999999); advanceTimeBy(1000); runCurrent()
            assertEquals(1,events.createIds.size)
            assertTrue(app.state.value.session.askBirthDate,"the sign-in screen shows the checkbox")
            assertTrue(app.state.value.publishAfterSignIn,"still waiting")
            assertNull((app.state.value.notice as? AppNotice.Failed)?.error)
            assertFalse("create_failed" in tracked)

            events.createError=null
            app.confirmAdult(); advanceTimeBy(1000); runCurrent()
            assertEquals(2,events.createIds.size)
            assertEquals(events.createIds.first(),events.createIds.last(),"the same id")
            assertEquals(events.createIds.last(),app.state.value.completedEventId)
            app.close()
        } finally { PoruchAnalytics.sink=null }
    }

    /**
     * Вік з рядка згоди не дійшов (мережа) — запасний крок галочки. Закрили його — публікація не чекає: інакше галочка з
     * профілю згодом опублікувала б несподівано.
     */
    @Test fun closingTheCheckboxStepCancels()=runTest {
        val events=Events(); val auth=Auth(); auth.session.value=null
        val safety=Safety(AccountFacts()).apply { adultFails=true }
        val app=testApp(events,backgroundScope,auth,safety=safety)
        runCurrent(); app.createEvent(walk); runCurrent()
        app.verifySignInCode("web@poriad.app","123456"); advanceTimeBy(1000); runCurrent()
        assertTrue(app.state.value.session.askBirthDate,"the fallback step")
        app.dismissConfirmationStep()
        safety.adultFails=false
        assertFalse(app.state.value.publishAfterSignIn)
        app.confirmAdult(); advanceTimeBy(1000); runCurrent()
        assertTrue(events.createIds.isEmpty())
        app.close()
    }

    /** Екран входу зникає сам після входу (iOS кличе dismissConfirmationStep на onDisappear) — публікація йде далі. */
    @Test fun theSheetClosingAfterSignInKeepsThePublish()=runTest {
        val events=Events(); val auth=Auth(); auth.session.value=null
        val app=testApp(events,backgroundScope,auth)
        runCurrent(); app.createEvent(walk); runCurrent()
        auth.session.value=UserSession("user","token","refresh",9999999999); runCurrent()
        app.dismissConfirmationStep(); app.cancelPendingPublish()
        advanceTimeBy(1000); runCurrent()
        assertEquals(1,events.createIds.size)
        app.close()
    }

    /** Вихід з акаунта: чужа вже чернетка не публікується з наступним входом. */
    @Test fun signingOutDropsThePendingPublish()=runTest {
        val events=Events(); val auth=Auth(); auth.session.value=null
        val app=testApp(events,backgroundScope,auth)
        events.createError=AppError.AgeRequired
        runCurrent(); app.createEvent(walk); runCurrent()
        auth.session.value=UserSession("user","token","refresh",9999999999); advanceTimeBy(1000); runCurrent()
        assertTrue(app.state.value.publishAfterSignIn,"waits for the age")
        app.signOut(); advanceTimeBy(1000); runCurrent()
        assertFalse(app.state.value.publishAfterSignIn)
        events.createError=null
        auth.session.value=UserSession("other","token","refresh",9999999999); advanceTimeBy(1000); runCurrent()
        app.confirmAdult(); advanceTimeBy(1000); runCurrent()
        assertEquals(1,events.createIds.size,"only the attempt before the sign-out")
        app.close()
    }

    /** Закрили вхід — лишились у редакторі; пізніший вхід з профілю нічого сам не публікує. */
    @Test fun closingTheSignInCancelsThePublish()=runTest {
        val events=Events(); val auth=Auth(); auth.session.value=null
        val app=testApp(events,backgroundScope,auth)
        runCurrent(); app.createEvent(walk); runCurrent()
        app.cancelPendingPublish()
        assertFalse(app.state.value.publishAfterSignIn)
        auth.session.value=UserSession("user","token","refresh",9999999999); advanceTimeBy(1000); runCurrent()
        assertTrue(events.createIds.isEmpty())
        app.close()
    }

    /** Збій після входу — банер у редакторі, а повторний тап бере той самий id: другої події не буде. */
    @Test fun aRetryAfterTheSignInIsIdempotent()=runTest {
        val events=Events(); val auth=Auth(); auth.session.value=null
        val app=testApp(events,backgroundScope,auth)
        events.failCreate=true
        runCurrent(); app.createEvent(walk); runCurrent()
        auth.session.value=UserSession("user","token","refresh",9999999999); advanceTimeBy(1000); runCurrent()
        assertEquals(AppNotice.Failed(AppError.Network),app.state.value.notice)
        assertFalse(app.state.value.publishAfterSignIn)

        events.failCreate=false
        app.createEvent(walk); runCurrent()
        assertEquals(2,events.createIds.size)
        assertEquals(events.createIds.first(),events.createIds.last())
        assertEquals(events.createIds.last(),app.state.value.completedEventId)
        app.close()
    }
}

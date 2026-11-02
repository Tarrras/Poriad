package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import kotlin.test.*

/** Вхід кодом з пошти й галочка «Мені вже є 18» (docs/organizers-1.5.md, хвиля 2). */
@OptIn(ExperimentalCoroutinesApi::class)
class SessionCodeTest {
    /** Код → крок коду; хибний код лишає крок; правильний — вхід, а новий акаунт без віку питає галочку. */
    @Test fun signingInWithACode()=runTest {
        val tracked=mutableListOf<Pair<String,Map<String,String>>>()
        PoruchAnalytics.sink={ name,params -> tracked+=name to params }
        try {
            val auth=Auth(); auth.session.value=null
            val safety=Safety(AccountFacts())
            val app=testApp(Events(),backgroundScope,auth,safety=safety)
            runCurrent()
            app.sendSignInCode(" web@poriad.app "); runCurrent()
            assertEquals(listOf(" web@poriad.app "),auth.codesSent)
            assertEquals("web@poriad.app",app.state.value.session.awaitingCode)

            app.verifySignInCode("web@poriad.app","654321"); runCurrent()
            assertEquals(AppNotice.Failed(AppError.InvalidCode),app.state.value.notice)
            assertFalse(app.state.value.signedIn)
            assertEquals("web@poriad.app",app.state.value.session.awaitingCode,"the code step stays")

            app.verifySignInCode("web@poriad.app","123456"); runCurrent()
            assertEquals("code-user",app.state.value.session.userId)
            assertNull(app.state.value.session.awaitingCode)
            assertTrue(app.state.value.session.askBirthDate,"a new account confirms its age")
            assertEquals("code",tracked.single { it.first=="login" }.second["method"])

            app.confirmAdult(); runCurrent()
            assertEquals(1,safety.adultConfirmations)
            assertFalse(app.state.value.session.askBirthDate)
            assertTrue(app.state.value.library.account.ageDeclared)
            assertFalse(app.state.value.needsAgeDeclaration)
            assertEquals(AppNotice.Told(AppMessage.AGE_CONFIRMED),app.state.value.notice)
            app.close()
        } finally { PoruchAnalytics.sink=null }
    }

    /**
     * Галочку «Мені вже є 18» відмітили на першому екрані входу: новий акаунт її отримує сам — без кроку галочки й без
     * «Вік підтверджено». Збій — крок, як раніше.
     */
    @Test fun theCheckboxOnTheFirstScreenConfirmsAgeQuietly()=runTest {
        val auth=Auth(); auth.session.value=null
        val safety=Safety(AccountFacts())
        val app=testApp(Events(),backgroundScope,auth,safety=safety)
        runCurrent()
        app.verifySignInCode("web@poriad.app","123456",adult=true); runCurrent()
        assertEquals("code-user",app.state.value.session.userId)
        assertEquals(1,safety.adultConfirmations)
        assertFalse(app.state.value.session.askBirthDate,"no separate step")
        assertTrue(app.state.value.library.account.ageDeclared)
        assertEquals(AppNotice.Told(AppMessage.SIGNED_IN),app.state.value.notice,"no «age confirmed» toast")
        app.close()
    }

    @Test fun aCheckboxThatDidNotSaveFallsBackToTheStep()=runTest {
        val auth=Auth(); auth.session.value=null
        val safety=object: SafetyRepository by Safety(AccountFacts()) { override suspend fun confirmAdult() = fail(AppError.Network) }
        val app=testApp(Events(),backgroundScope,auth,safety=safety)
        runCurrent()
        app.verifySignInCode("web@poriad.app","123456",adult=true); runCurrent()
        assertTrue(app.state.value.signedIn)
        assertTrue(app.state.value.session.askBirthDate)
        app.close()
    }

    /**
     * Акаунт з коду (запис з вебу) пароля може не мати: пароль не питаємо. Видалення — через новий код на пошту з профілю,
     * без пароля; хибний код нічого не видаляє.
     */
    @Test fun aCodeAccountDeletesWithACode()=runTest {
        val auth=Auth(); auth.session.value=null
        val app=testApp(Events(),backgroundScope,auth,safety=Safety(AccountFacts(adultConfirmedAt="2026-11-01T10:00:00Z")),
            profiles=Profiles().apply { mine=mine.copy(userId="code-user",email="web@poriad.app") })
        runCurrent(); app.verifySignInCode("web@poriad.app","123456"); advanceTimeBy(1000); runCurrent()
        assertTrue(app.state.value.session.viaCode)
        assertTrue(app.state.value.session.passwordless,"no password field")

        app.sendDeletionCode(); runCurrent()
        assertEquals("web@poriad.app",auth.codesSent.single())
        app.deleteAccountWithCode("000000"); runCurrent()
        assertFalse(auth.deleted)
        assertTrue(app.state.value.signedIn)
        assertEquals(AppNotice.Failed(AppError.InvalidCode),app.state.value.notice)

        app.deleteAccountWithCode("123456"); runCurrent()
        assertNull(auth.deletedWithPassword)
        assertTrue(auth.deleted)
        assertFalse(app.state.value.signedIn)
        assertEquals(AppNotice.Told(AppMessage.ACCOUNT_DELETED),app.state.value.notice)
        app.close()
    }

    /** Пароль і пошта — як і було: пароль питаємо. */
    @Test fun aPasswordSessionStillAsksForThePassword() {
        assertFalse(SessionState(userId="u",providers=setOf("email"),methods=setOf("password")).passwordless)
        assertTrue(SessionState(userId="u",providers=setOf("google"),methods=setOf("oauth")).passwordless)
    }

    /** Закрили екран на кроці коду — наступного разу форма, а не код. */
    @Test fun closingTheScreenForgetsTheCode()=runTest {
        val auth=Auth(); auth.session.value=null
        val app=testApp(Events(),backgroundScope,auth)
        runCurrent(); app.sendSignInCode("a@b.co"); runCurrent()
        app.dismissConfirmationStep()
        assertNull(app.state.value.session.awaitingCode)
        app.close()
    }

    /** Реєстрація з галочкою: дата в метадані не йде. Стара форма з датою працює, як і була. */
    @Test fun signingUpWithTheCheckbox()=runTest {
        val auth=Auth(); auth.session.value=null
        val app=testApp(Events(),backgroundScope,auth)
        runCurrent(); app.signUp("new@poriad.app","password1","Імʼя"); runCurrent()
        assertNull(auth.signedUpWith)
        assertTrue(app.state.value.signedIn)
        auth.session.value=null; runCurrent()
        app.signUp("old@poriad.app","password1","Імʼя","1990-01-01"); runCurrent()
        assertEquals("1990-01-01",auth.signedUpWith)
        app.close()
    }
}

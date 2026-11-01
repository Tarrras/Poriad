package app.poruch.account
import app.poruch.domain.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class AccountActionsTest {
    private class Auth: AuthRepository {
        override val session = MutableStateFlow<UserSession?>(null)
        var signedIn = false
        override suspend fun signIn(email:String,password:String) { signedIn=true }
        var signedUpWith:String?="unset"
        override suspend fun signUp(email:String,password:String,name:String,birthDate:String?):Boolean { signedUpWith=birthDate; return true }
        val codes=mutableListOf<String>()
        override suspend fun sendCode(email:String) { codes+=email }
        override suspend fun verifyCode(email:String,code:String) { codes+="$email:$code" }
        override suspend fun signOut() {}
        override suspend fun accessToken():String? = null
        override suspend fun requestPasswordReset(email:String) {}
        override suspend fun updatePassword(password:String,current:String?) {}
        override suspend fun handleCallback(url:String) = false
        override suspend fun verifyPassword(password: String) {}
        override suspend fun deleteAccount(password: String?, appleAuthorizationCode: String?) { session.value = null }
        override fun idTokenNonce() = "hashed"
        override suspend fun signInWithIdToken(provider: IdProvider, idToken: String) {}
    }
    @Test fun ordinaryEmailCanSignIn() = runTest {
        val auth=Auth(); AccountActions(auth).signIn("person@example.com","password123")
        assertTrue(auth.signedIn)
    }
    @Test fun whitespaceEmailIsRejectedBeforeNetwork() = runTest {
        val auth=Auth()
        assertFailsWith<AppFailure> { AccountActions(auth).signIn("per son@example.com","password123") }
        assertFalse(auth.signedIn)
    }
    @Test fun shortPasswordIsRejected() = runTest {
        assertFailsWith<AppFailure> { AccountActions(Auth()).signIn("a@b.com","123") }
    }
    /** Мінімальний вік перевіряється до запиту і ще раз у базі. */
    @Test fun anUnderageSignUpNeverReachesTheNetwork() = runTest {
        val auth=Auth()
        val error=assertFailsWith<AppFailure> {
            AccountActions(auth).signUp("teen@example.com","password123","Тінейджер","2012-05-01",today)
        }
        assertEquals(AppError.Underage,error.error)
    }
    @Test fun anAdultSignUpPasses() = runTest {
        assertTrue(AccountActions(Auth()).signUp("person@example.com","password123","Олена","1998-05-01",today))
    }
    @Test fun anUnreadableDateIsRejected() = runTest {
        assertFailsWith<AppFailure> { AccountActions(Auth()).signUp("a@b.com","password123","Олена","yesterday",today) }
    }
    /** Галочка замість дати: дата в репозиторій не йде, і сервер ставить `adult_confirmed_at`. */
    @Test fun aCheckboxSignUpSendsNoDate() = runTest {
        val auth=Auth()
        assertTrue(AccountActions(auth).signUp("person@example.com","password123","Олена"))
        assertNull(auth.signedUpWith)
    }
    /** Пошту й код перевіряємо до мережі: хибний код не палить спробу на сервері. */
    @Test fun aCodeIsDigitsOnly() = runTest {
        val auth=Auth(); val actions=AccountActions(auth)
        assertEquals(AppError.InvalidEmail,assertFailsWith<AppFailure> { actions.sendCode("not-an-email") }.error)
        assertEquals(AppError.InvalidCode,assertFailsWith<AppFailure> { actions.verifyCode("a@b.com","12a456") }.error)
        assertEquals(AppError.InvalidCode,assertFailsWith<AppFailure> { actions.verifyCode("a@b.com","123") }.error)
        assertTrue(auth.codes.isEmpty())
        actions.sendCode(" a@b.com "); actions.verifyCode("a@b.com"," 123456 ")
        assertEquals(listOf(" a@b.com ","a@b.com: 123456 "),auth.codes)
    }
    private val today = kotlinx.datetime.LocalDate.parse("2026-09-06")
}

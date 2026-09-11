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
        override suspend fun signUp(email:String,password:String,name:String,birthDate:String) = true
        override suspend fun signOut() {}
        override suspend fun accessToken():String? = null
        override suspend fun requestPasswordReset(email:String) {}
        override suspend fun updatePassword(password:String) {}
        override suspend fun handleCallback(url:String) = false
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
    /** The age floor is checked before the account is attempted, and again by the database. */
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
    private val today = kotlinx.datetime.LocalDate.parse("2026-09-06")
}

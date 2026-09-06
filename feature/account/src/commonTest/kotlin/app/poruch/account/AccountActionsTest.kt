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
        override suspend fun signUp(email:String,password:String,name:String) = true
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
}

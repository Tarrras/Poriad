package app.poruch.data

import app.poruch.domain.AuthRepository
import app.poruch.domain.IdProvider
import app.poruch.domain.UserSession
import kotlinx.coroutines.flow.MutableStateFlow

/** Сесія `u1` з токеном `token`, що не спливає: для запитів, яким потрібен лише вхід. */
internal class SignedInAuth : AuthRepository {
    override val session = MutableStateFlow<UserSession?>(UserSession("u1", "token", "refresh", 9999999999))
    override suspend fun accessToken() = session.value?.accessToken
    override suspend fun signIn(email: String, password: String) {}
    override suspend fun signUp(email: String, password: String, name: String, birthDate: String?) = true
    override suspend fun sendCode(email: String) {}
    override suspend fun verifyCode(email: String, code: String) {}
    override fun idTokenNonce() = ""
    override suspend fun signInWithIdToken(provider: IdProvider, idToken: String) {}
    override suspend fun signOut() {}
    override suspend fun requestPasswordReset(email: String) {}
    override suspend fun updatePassword(password: String, current: String?) {}
    override suspend fun handleCallback(url: String) = false
    override suspend fun verifyPassword(password: String) {}
    override suspend fun deleteAccount(password: String?, appleAuthorizationCode: String?) {}
}

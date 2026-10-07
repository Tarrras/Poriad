package app.poruch.android.platform

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import app.poruch.android.BuildConfig
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential

/** Кнопка Google є, лише коли для збірки вказано Web client ID (gradle.properties). */
val googleSignInAvailable get() = BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()

/**
 * ID-токен Google через Credential Manager: системний аркуш з акаунтами пристрою. [nonce] — SHA-256
 * з [app.poruch.shared.PoruchApp.idTokenNonce]. Null — людина закрила аркуш; інші збої — винятки
 * [androidx.credentials.exceptions.GetCredentialException]. [context] — Activity: аркуш показується поверх неї.
 */
suspend fun googleIdToken(context: Context, nonce: String): String? {
    val option = GetSignInWithGoogleOption.Builder(BuildConfig.GOOGLE_WEB_CLIENT_ID).setNonce(nonce).build()
    val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
    return try {
        GoogleIdTokenCredential.createFrom(CredentialManager.create(context).getCredential(context, request).credential.data).idToken
    } catch (e: GetCredentialCancellationException) {
        null
    }
}

package app.poruch.android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.edit
import app.poruch.shared.SecureSessionStore
import android.security.keystore.KeyPermanentlyInvalidatedException
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** На диску лише шифротекст; AES-ключ живе в Android Keystore і не експортується. */
class SessionStore(context: Context) : SecureSessionStore {
    private val preferences = context.getSharedPreferences("secure_session", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (store.getKey("poruch_session", null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("poruch_session", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    override fun read(): String? = try {
        preferences.getString("data", null)?.let { encoded ->
            val bytes = Base64.decode(encoded, Base64.NO_WRAP)
            Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
        }
    } catch (e: GeneralSecurityException) {
        // Стираємо лише коли шифротекст справді не прочитати ніколи: ключ втрачено або підмінено.
        // Тимчасовий збій Keystore лишає сесію на наступний старт.
        if (e is AEADBadTagException || e is UnrecoverableKeyException || e is KeyPermanentlyInvalidatedException) clear()
        null
    } catch (_: Exception) { null }
    override fun write(value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        // apply: запис іде з головного потоку, диск — у фоні; пам'ять SharedPreferences оновлюється одразу.
        preferences.edit { putString("data", Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray()), Base64.NO_WRAP)) }
    }
    override fun clear() { preferences.edit { clear() } }
}

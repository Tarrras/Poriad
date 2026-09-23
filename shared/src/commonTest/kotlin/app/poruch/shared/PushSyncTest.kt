package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.*

@OptIn(ExperimentalCoroutinesApi::class)
class PushSyncTest {
    private class Tokens : PushTokens {
        val registered = mutableListOf<Pair<String, String>>()
        val unregistered = mutableListOf<String>()
        /** Яким ключем знімали: null — поточною сесією. */
        val keys = mutableListOf<String?>()
        var fail = false
        var failUnregister: AppError? = null
        override suspend fun register(token: String, platform: String) { delay(50); if (fail) fail(AppError.Network); registered += token to platform }
        override suspend fun unregister(token: String, accessToken: String?) { failUnregister?.let { fail(it) }; unregistered += token; keys += accessToken }
    }
    private class Pending : PendingUnregisterStore {
        var value: PendingUnregister? = null
        override fun read() = value
        override fun write(value: PendingUnregister?) { this.value = value }
    }
    private val sessionA = UserSession("a", "access-a", "refresh-a", 9999999999)

    /** Токен приходить до входу: чекає акаунта, потім реєструється один раз. */
    @Test fun aTokenWaitsForAnAccountAndRegistersOnce() = runTest {
        val tokens = Tokens(); val store = AppStore(AppState(), backgroundScope)
        val sync = PushSync(tokens, null, null, store)
        sync.tokenChanged("t1", PushPlatform.ANDROID); runCurrent(); advanceTimeBy(100)
        assertTrue(tokens.registered.isEmpty(), "без акаунта нема кого реєструвати")

        store.update { it.copy(session = SessionState(userId = "user")) }
        // Токен і вхід приходять одночасно: обидва шляхи ведуть до однієї реєстрації.
        sync.register(); sync.tokenChanged("t1", PushPlatform.ANDROID); runCurrent(); advanceTimeBy(100); runCurrent()
        assertEquals(listOf("t1" to PushPlatform.ANDROID), tokens.registered)
        assertTrue(store.value.session.pushRegistered)

        sync.tokenChanged("t1", PushPlatform.ANDROID); advanceTimeBy(100); runCurrent()
        assertEquals(1, tokens.registered.size, "той самий зареєстрований токен не реєструємо вдруге")
    }

    /** Інший акаунт на тому ж телефоні — та сама реєстрація під ним. */
    @Test fun anotherAccountRegistersTheSameTokenAgain() = runTest {
        val tokens = Tokens(); val store = AppStore(AppState(session = SessionState(userId = "a")), backgroundScope)
        val sync = PushSync(tokens, null, null, store)
        sync.tokenChanged("t1", PushPlatform.IOS); advanceTimeBy(100); runCurrent()
        store.update { it.copy(session = SessionState(userId = "b")) }
        sync.register(); advanceTimeBy(100); runCurrent()
        assertEquals(2, tokens.registered.size)
        sync.unregister(UserSession("b", "access-b", "refresh-b", 9999999999))
        assertEquals(listOf("t1"), tokens.unregistered)
    }

    /** Відмова сервера не позначає пристрій зареєстрованим і не блокує наступну спробу. */
    @Test fun aRefusedRegistrationCanBeRetried() = runTest {
        val tokens = Tokens().apply { fail = true }; val store = AppStore(AppState(session = SessionState(userId = "a")), backgroundScope)
        val sync = PushSync(tokens, null, null, store)
        sync.tokenChanged("t1", PushPlatform.IOS); advanceTimeBy(100); runCurrent()
        assertFalse(store.value.session.pushRegistered)
        tokens.fail = false
        sync.register(); advanceTimeBy(100); runCurrent()
        assertTrue(store.value.session.pushRegistered)
    }

    /** Пуш про чат позначає ключ баченим у списку чатів, а не запитів. */
    @Test fun aReceivedPushMarksItsOwnSeenList() = runTest {
        class Seen : SeenRequestStore { val keys = mutableSetOf<String>(); override fun seen() = keys.toSet(); override fun markSeen(keys: Set<String>) { this.keys += keys } }
        val requests = Seen(); val messages = Seen()
        val sync = PushSync(null, requests, messages, AppStore(AppState(), backgroundScope))
        sync.received("chat", "m1"); sync.received("request", "r1"); sync.received("unknown", "x")
        assertEquals(setOf("m1"), messages.keys)
        assertEquals(setOf("r1"), requests.keys)
    }

    /** Вихід офлайн: токен із ключем акаунта чекає і знімається при наступному поверненні. */
    @Test fun anUnregisterThatFailedOfflineIsRetriedWithTheOldKey() = runTest {
        val tokens = Tokens(); val pending = Pending()
        val store = AppStore(AppState(session = SessionState(userId = "a")), backgroundScope)
        val sync = PushSync(tokens, null, null, store, pending)
        sync.tokenChanged("t1", PushPlatform.ANDROID); advanceTimeBy(100); runCurrent()

        tokens.failUnregister = AppError.Network
        sync.unregister(sessionA)
        assertEquals(PendingUnregister("t1", "a", "access-a", 9999999999), pending.value)
        store.update { it.forAccount(null) }

        tokens.failUnregister = null
        sync.retryPending(); runCurrent()
        assertEquals(listOf<String?>("access-a"), tokens.keys, "знімаємо ключем акаунта, що вийшов, а не поточним")
        assertNull(pending.value)
    }

    /** Той самий акаунт повернувся: токен знову його, і повтор його не знімає. */
    @Test fun aPendingUnregisterIsDroppedWhenTheSameAccountIsBack() = runTest {
        val tokens = Tokens(); val pending = Pending().apply { value = PendingUnregister("t1", "a", "access-a", 9999999999) }
        val sync = PushSync(tokens, null, null, AppStore(AppState(session = SessionState(userId = "a")), backgroundScope), pending)
        sync.retryPending(); runCurrent()
        assertTrue(tokens.unregistered.isEmpty())
        assertNull(pending.value)
    }

    /** Сесію відкликав сервер (не вихід): токен знімаємо останнім ключем; 401 — повторювати нічого. */
    @Test fun aDroppedSessionReleasesItsTokenWithTheLastKey() = runTest {
        val tokens = Tokens(); val pending = Pending()
        val store = AppStore(AppState(session = SessionState(userId = "a")), backgroundScope)
        val sync = PushSync(tokens, null, null, store, pending)
        sync.tokenChanged("t1", PushPlatform.IOS); advanceTimeBy(100); runCurrent()
        sync.accountLeft(sessionA); runCurrent()
        assertEquals(listOf<String?>("access-a"), tokens.keys)

        sync.tokenChanged("t2", PushPlatform.IOS); advanceTimeBy(100); runCurrent()
        tokens.failUnregister = AppError.SessionRequired
        sync.accountLeft(sessionA); runCurrent()
        assertNull(pending.value, "мертвий ключ не зберігаємо")
    }
}

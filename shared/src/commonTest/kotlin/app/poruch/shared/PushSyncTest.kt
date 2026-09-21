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
        var fail = false
        override suspend fun register(token: String, platform: String) { delay(50); if (fail) fail(AppError.Network); registered += token to platform }
        override suspend fun unregister(token: String) { unregistered += token }
    }

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
        sync.unregister()
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
}

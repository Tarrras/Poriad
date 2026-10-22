package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.*
import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class PushSyncTest {
    private class Tokens : PushTokens {
        val registered = mutableListOf<Pair<String, PushPlatform>>()
        val unregistered = mutableListOf<String>()
        /** Яким ключем знімали: null — поточною сесією. */
        val keys = mutableListOf<String?>()
        var fail = false
        var failUnregister: AppError? = null
        override suspend fun register(token: String, platform: PushPlatform) { delay(50); if (fail) fail(AppError.Network); registered += token to platform }
        override suspend fun unregister(token: String, accessToken: String?) { failUnregister?.let { fail(it) }; unregistered += token; keys += accessToken }
        /** `release_push_token`: (токен, акаунт) — без сесії. */
        val released = mutableListOf<Pair<String, String>>()
        override suspend fun release(token: String, userId: String) { failUnregister?.let { fail(it) }; released += token to userId }
        /** Канал повернення: (токен, місто, інтереси) кожного `touch_device` і токени `forget_device`. */
        val touched = mutableListOf<Triple<String, String?, List<String>>>()
        val forgotten = mutableListOf<String>()
        override suspend fun touchDevice(token: String, platform: PushPlatform, city: String?, interests: List<String>) { touched += Triple(token, city, interests) }
        override suspend fun forgetDevice(token: String) { forgotten += token }
    }
    private class Devices : DeviceTouchStore {
        var value: DeviceTouch? = null
        override fun last() = value
        override fun save(touch: DeviceTouch?) { value = touch }
    }
    private class Pending : PendingUnregisterStore {
        var value: PendingUnregister? = null
        override fun read() = value
        override fun write(value: PendingUnregister?) { this.value = value }
    }
    private val sessionA = UserSession("a", "access-a", "refresh-a", 9999999999)

    /** Годинник тестів каналу повернення: `runTest` віртуалізує корутини, а не `Clock.System`. */
    private var seconds = 1_800_000_000L
    private fun device(tokens: Tokens, store: AppStore, devices: Devices = Devices()) =
        PushSync(tokens, null, null, store, devices = devices, now = { Instant.fromEpochSeconds(seconds) })

    /** Гість з дозволом і дайджестом: сервер чує пристрій, але не частіше разу на 12 годин. */
    @Test fun aGuestDeviceIsTouchedAtMostEveryTwelveHours() = runTest {
        val tokens = Tokens(); val store = AppStore(AppState(), backgroundScope)
        val sync = device(tokens, store)
        sync.tokenChanged("t1", PushPlatform.IOS); sync.notificationsAllowed(true); runCurrent()
        assertEquals(listOf(Triple<String, String?, List<String>>("t1", "Київ", emptyList())), tokens.touched, "гість без акаунта — теж")

        sync.notificationsAllowed(true); runCurrent()
        seconds += 11.hours.inWholeSeconds; sync.notificationsAllowed(true); runCurrent()
        assertEquals(1, tokens.touched.size, "друге відкриття за 11 годин — без запиту")
        seconds += 1.hours.inWholeSeconds; sync.notificationsAllowed(true); runCurrent()
        assertEquals(2, tokens.touched.size, "минуло 12 годин — знову")
    }

    /** Інше місто чи інтереси — одразу, без 12 годин. Своє місце на мапі й місто поза покриттям — без міста. */
    @Test fun aCityOrInterestChangeIsSentAtOnce() = runTest {
        val tokens = Tokens(); val store = AppStore(AppState(), backgroundScope)
        val sync = device(tokens, store).also { it.start() }
        sync.tokenChanged("t1", PushPlatform.ANDROID); sync.notificationsAllowed(true); runCurrent()

        store.update { it.copy(taste = Taste(interests = listOf(EventCategory.MUSIC, EventCategory.COMEDY, EventCategory.UNKNOWN))) }; runCurrent()
        assertEquals(Triple<String, String?, List<String>>("t1", "Київ", listOf("comedy", "music")), tokens.touched.last(), "інтереси — ключами, без невідомих")
        store.update { it.copy(city = CityState("Львів", 49.8, 24.0)) }; runCurrent()
        assertEquals("Львів", tokens.touched.last().second)
        store.update { it.copy(city = CityState("Біла Церква", 49.8, 30.1)) }; runCurrent()
        assertNull(tokens.touched.last().second, "місто поза п'ятьма сервер не прийме")
        store.update { it.copy(city = CityState()) }; runCurrent()
        store.update { it.copy(city = it.city.copy(custom = true)) }; runCurrent()
        assertNull(tokens.touched.last().second, "«Шукати тут» — свого міста нема")
        assertEquals(6, tokens.touched.size)
        store.update { it.copy(city = it.city.copy(suggestions = listOf(CityResult("Київ", 50.4, 30.5)))) }; runCurrent()
        assertEquals(6, tokens.touched.size, "підказки пошуку міста — не зміна")
    }

    /** Нема дозволу чи вимкнено дайджест — сервер забуває пристрій тим токеном, що знав, навіть без нового. */
    @Test fun noPermissionOrDigestForgetsTheDevice() = runTest {
        val tokens = Tokens(); val store = AppStore(AppState(), backgroundScope); val devices = Devices()
        val sync = device(tokens, store, devices).also { it.start() }
        sync.tokenChanged("t1", PushPlatform.IOS); sync.notificationsAllowed(true); runCurrent()

        store.update { it.copy(digestEnabled = false) }; runCurrent()
        assertEquals(listOf("t1"), tokens.forgotten, "дайджест вимкнено — забути")
        assertNull(devices.value)
        store.update { it.copy(digestEnabled = true) }; runCurrent()
        assertEquals(2, tokens.touched.size, "увімкнено знову — одразу, хоч 12 годин не минуло")

        // Наступний запуск iOS без дозволу: токена від APNs нема, але сервер знає старий.
        val again = device(tokens, AppStore(AppState(), backgroundScope), devices)
        again.notificationsAllowed(false); runCurrent()
        assertEquals(listOf("t1", "t1"), tokens.forgotten)
        assertNull(devices.value)
        again.notificationsAllowed(false); runCurrent()
        assertEquals(2, tokens.forgotten.size, "забувати вже нічого")
    }

    /** Фоновий процес (пуш, новий токен FCM) — не відкриття: без слова платформи про дозвіл сервер нічого не чує. */
    @Test fun aBackgroundProcessDoesNotTouch() = runTest {
        val tokens = Tokens(); val store = AppStore(AppState(), backgroundScope)
        device(tokens, store).also { it.start() }.tokenChanged("t1", PushPlatform.ANDROID); runCurrent()
        store.update { it.copy(city = CityState("Одеса", 46.5, 30.7)) }; runCurrent()
        assertTrue(tokens.touched.isEmpty())
    }

    /** Новий токен на тому ж пристрої: старий сервер забуває, щоб пуш повернення не прийшов двічі. */
    @Test fun aNewTokenReplacesTheOldDevice() = runTest {
        val tokens = Tokens(); val store = AppStore(AppState(), backgroundScope)
        val sync = device(tokens, store)
        sync.tokenChanged("t1", PushPlatform.ANDROID); sync.notificationsAllowed(true); runCurrent()
        sync.tokenChanged("t2", PushPlatform.ANDROID); runCurrent()
        assertEquals(listOf("t1"), tokens.forgotten)
        assertEquals("t2", tokens.touched.last().first)
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

    /** Вихід офлайн: токен і id акаунта, без ключа доступу, чекають і знімаються без сесії при наступному поверненні. */
    @Test fun anUnregisterThatFailedOfflineIsReleasedLaterWithoutAKey() = runTest {
        val tokens = Tokens(); val pending = Pending()
        val store = AppStore(AppState(session = SessionState(userId = "a")), backgroundScope)
        val sync = PushSync(tokens, null, null, store, pending)
        sync.tokenChanged("t1", PushPlatform.ANDROID); advanceTimeBy(100); runCurrent()

        tokens.failUnregister = AppError.Network
        sync.unregister(sessionA)
        assertEquals(PendingUnregister("t1", "a"), pending.value)
        store.update { it.forAccount(null) }

        tokens.failUnregister = null
        sync.retryPending(); runCurrent()
        assertEquals(listOf("t1" to "a"), tokens.released, "знімаємо токен акаунта, що вийшов, а не поточного")
        assertTrue(tokens.keys.isEmpty(), "жодного ключа доступу")
        assertNull(pending.value)

        // Сервер відмовив (401/Rejected): повтор нічого не дасть, запис прибираємо.
        pending.value = PendingUnregister("t1", "a"); tokens.failUnregister = AppError.Rejected
        sync.retryPending(); runCurrent()
        assertNull(pending.value)
    }

    /** Той самий акаунт повернувся: токен знову його, і повтор його не знімає. */
    @Test fun aPendingUnregisterIsDroppedWhenTheSameAccountIsBack() = runTest {
        val tokens = Tokens(); val pending = Pending().apply { value = PendingUnregister("t1", "a") }
        val sync = PushSync(tokens, null, null, AppStore(AppState(session = SessionState(userId = "a")), backgroundScope), pending)
        sync.retryPending(); runCurrent()
        assertTrue(tokens.unregistered.isEmpty() && tokens.released.isEmpty())
        assertNull(pending.value)
    }

    /** Сесію відкликав сервер (не вихід): токен знімаємо останнім ключем; 401 — пізніше без ключа. */
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
        assertEquals(PendingUnregister("t2", "a"), pending.value, "мертвий ключ не причина лишити токен акаунту")

        store.update { it.forAccount(null) }; tokens.failUnregister = null
        sync.retryPending(); runCurrent()
        assertEquals(listOf("t2" to "a"), tokens.released)
        assertNull(pending.value)
    }
}

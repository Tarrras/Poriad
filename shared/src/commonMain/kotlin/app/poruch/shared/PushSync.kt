package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlin.time.Clock
import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant

/**
 * Реєстрація пристрою для пушів. Токен один на телефон, а людей на ньому може бути кілька,
 * тож реєструємо під кожним акаунтом, з яким входять, і знімаємо, коли акаунт іде. Зняти не
 * вдалося (офлайн, сесію відкликано) — токен і id того акаунта чекають у [pending] і
 * повторюються на старті й при поверненні в застосунок, уже без сесії ([PushTokens.release]).
 *
 * Окремо від акаунтів — канал повернення ([touch]): пристрій, а не людина, тож і для гостя.
 */
internal class PushSync(
    private val push: PushTokens?,
    private val seenRequests: SeenRequestStore?,
    private val seenMessages: SeenRequestStore?,
    private val store: AppStore,
    private val pending: PendingUnregisterStore? = null,
    private val devices: DeviceTouchStore? = null,
    private val now: () -> Instant = { Clock.System.now() }
) {
    /** Токен пристрою від платформи і його платформа. */
    private var token: Pair<String, PushPlatform>? = null
    /** Токен і акаунт, для яких реєстрація вже йде: токен і вхід часто приходять одночасно. */
    private var registering: Pair<String, String?>? = null
    /** Акаунт, під яким токен зареєстровано. Null — ні під яким, або вже знято. */
    private var registeredFor: String? = null
    private var retrying: Job? = null
    /**
     * Дозвіл системи, як його бачить платформа на передньому плані. Null — ще не казала: фоновий процес (пуш, новий
     * токен FCM) застосунок не відкривав, і `last_seen` від нього зсуватись не має.
     */
    private var allowed: Boolean? = null
    private var touching: Job? = null

    /** Зміна міста, інтересів чи перемикача дайджесту — одразу до сервера, не чекаючи [TOUCH_EVERY]. */
    fun start() {
        store.scope.launch {
            store.state.map { listOf(it.city.name, it.city.custom, it.taste.interests, it.digestEnabled) }.distinctUntilChanged().collect { touch() }
        }
        // Радар: місто й артисти гостя.
        store.scope.launch { store.state.map { radarCity(it) to radarArtists(it) }.distinctUntilChanged().collect { radar() } }
    }

    /** Що сервер радару почув у цьому процесі. Пам'ять, а не диск: на старті шлемо знову, і так `updated_at` живий. */
    private var radarSent: Triple<String, String?, List<String>>? = null
    private var radaring: Job? = null

    /** Артисти гостя для сервера; в акаунта — порожньо: його артисти в підписках. */
    private fun radarArtists(state: AppState): List<String> =
        if (state.signedIn) emptyList() else state.library.follows.filter { it.kind == FollowKind.ARTIST }.map { it.targetId }.sorted()

    /**
     * Радар артистів (docs/artist-radar.md): з дозволом і токеном — `set_radar` (місто пристрою й артисти гостя), гостю й
     * акаунту, незалежно від дайджесту. Дозвіл забрали — `forget_radar`.
     */
    fun radar() {
        val allowed = allowed ?: return
        val tokens = push ?: return
        val (token, platform) = this.token ?: return
        if (radaring?.isActive == true) return
        if (!allowed) {
            if (radarSent == null) return
            radaring = store.scope.launch {
                if (attempt("radar forget") { tokens.forgetRadar(token) }) radarSent = null
                radaring = null
            }
            return
        }
        val state = store.value
        val next = Triple(token, radarCity(state), radarArtists(state))
        if (next == radarSent) return
        radaring = store.scope.launch {
            val done = attempt("radar") { tokens.setRadar(token, platform, next.second, next.third); radarSent = next }
            radaring = null
            // Поки йшов запит, могли змінити місто чи список.
            if (done) radar()
        }
    }

    /** Платформа на передньому плані: є дозвіл (authorized чи provisional) чи нема. Кожне відкриття. */
    fun notificationsAllowed(allowed: Boolean) {
        this.allowed = allowed
        touch()
        radar()
    }

    /**
     * Канал повернення (docs/guest-channel.md). Є токен, дозвіл і дайджест — `touch_device`, щоб сервер знав, коли
     * пристрій відкривали, не частіше [TOUCH_EVERY]; інше місто чи інтереси — одразу. Нема дозволу чи дайджесту —
     * `forget_device` тим токеном, що сервер знає: на iOS без дозволу нового токена й не буде.
     */
    fun touch() {
        val allowed = allowed ?: return
        val tokens = push ?: return
        val devices = devices ?: return
        if (touching?.isActive == true) return
        val state = store.value
        val last = devices.last()
        if (!allowed || !state.digestEnabled) {
            last ?: return
            touching = store.scope.launch {
                attempt("forget") { tokens.forgetDevice(last.token); devices.save(null) }
            }
            return
        }
        // Дозвіл є, а токен ще їде: iOS реєструється в APNs уже після дозволу, і [tokenChanged] покличе знову.
        val (token, platform) = this.token ?: return
        val city = state.city.name.takeIf { name -> !state.city.custom && HomeLocation.covered.any { it.city == name } }
        val interests = state.taste.interests.filter { it != EventCategory.UNKNOWN }.map { it.key }.distinct().sorted()
        val at = now().epochSeconds
        if (last != null && last.token == token && last.city == city && last.interests == interests &&
            at - last.at < TOUCH_EVERY.inWholeSeconds) return
        touching = store.scope.launch {
            val done = attempt("touch") {
                // Новий токен (перевстановлення, ротація FCM): старий рядок інакше отримав би ще й свій пуш.
                if (last != null && last.token != token) tokens.forgetDevice(last.token)
                tokens.touchDevice(token, platform, city, interests)
                devices.save(DeviceTouch(token, city, interests, at))
            }
            touching = null
            // Поки йшов запит, могли змінити місто чи інтереси.
            if (done) touch()
        }
    }

    private suspend inline fun attempt(what: String, block: () -> Unit): Boolean = try {
        block(); PoruchLog.i("push") { "device $what" }; true
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        PoruchLog.w("push") { "device $what failed: ${e.asAppError()}" }; false
    }

    /** Платформа отримала або оновила токен. Реєструємо одразу, якщо є акаунт. */
    fun tokenChanged(token: String, platform: PushPlatform) {
        if (this.token?.first == token && store.value.session.pushRegistered) return
        this.token = token to platform
        register()
        touch()
        radar()
    }

    /** Реєструє поточний токен під поточним акаунтом. Без токена, сховища чи акаунта — нічого. */
    fun register() {
        val (token, platform) = this.token ?: return
        val tokens = push ?: return
        val uid = store.value.session.userId ?: return
        if (registering == token to uid) return
        registering = token to uid
        store.scope.launch {
            try {
                tokens.register(token, platform)
                PoruchLog.i("push") { "registered ${platform.key} token" }
                registeredFor = uid
                // Сервер переписав власника токена: попередній акаунт його вже не тримає.
                if (pending?.read()?.token == token) pending.write(null)
                store.update { it.copy(session = it.session.copy(pushRegistered = true)) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("push") { "register failed: ${e.asAppError()}" }
            } finally {
                if (registering == token to uid) registering = null
            }
        }
    }

    /**
     * Знімає токен до виходу поточної сесії: після нього RPC уже не знає, чий він. Збій виходу
     * не зупиняє, але токен лишається в [pending] з id цього акаунта.
     */
    suspend fun unregister(session: UserSession?) {
        val (token, _) = this.token ?: return
        val tokens = push ?: return
        session ?: return
        registeredFor = null
        store.update { it.copy(session = it.session.copy(pushRegistered = false)) }
        try {
            tokens.unregister(token)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            remember(token, session, e)
        }
    }

    /**
     * Сесія зникла не через вихід (сервер відкликав refresh): пробуємо останнім ключем. Він живий
     * ще хвилину після того, як ми вирішили оновлювати; не вийшло — [pending] зніме без ключа.
     */
    fun accountLeft(session: UserSession) {
        val (token, _) = this.token ?: return
        val tokens = push ?: return
        if (registeredFor != session.userId) return
        registeredFor = null
        store.scope.launch {
            try {
                tokens.unregister(token, session.accessToken)
                PoruchLog.i("push") { "token released after the session was dropped" }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                remember(token, session, e)
            }
        }
    }

    /** Будь-який збій, і 401 теж: повтор іде без ключа сесії, тож мертвий ключ йому не заважає. */
    private fun remember(token: String, session: UserSession, e: Exception) {
        PoruchLog.w("push") { "unregister failed: ${e.asAppError()}, will retry" }
        pending?.write(PendingUnregister(token, session.userId))
    }

    /** Старт і повернення в застосунок: повторює незняте без ключа сесії, поки сервер не зніме чи не відмовить. */
    fun retryPending() {
        val stored = pending ?: return
        val left = stored.read() ?: return
        val tokens = push ?: return
        if (retrying?.isActive == true) return
        // Той самий акаунт знову тут — токен знову його, знімати не можна.
        if (left.userId == store.value.session.userId) { stored.write(null); return }
        retrying = store.scope.launch {
            try {
                tokens.release(left.token, left.userId)
                PoruchLog.i("push") { "pending token released" }
                stored.write(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("push") { "pending unregister failed: $error" }
                if (error == AppError.SessionRequired || error == AppError.Rejected) stored.write(null)
            }
        }
    }

    /** Пуш прийшов на цей пристрій: ключ бачений, щоб локальне сповіщення не повторило те саме. */
    fun received(kind: String, key: String) {
        PoruchLog.i("push") { "received $kind" }
        when (kind) {
            "chat" -> seenMessages?.markSeen(setOf(key))
            "request" -> seenRequests?.markSeen(setOf(key))
        }
    }

    companion object {
        /** Частіше `last_seen` не треба: вікна сервера — тижні, а відкриттів на день може бути десяток. */
        val TOUCH_EVERY = 12.hours
    }
}

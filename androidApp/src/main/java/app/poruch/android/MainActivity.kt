@file:OptIn(KoinExperimentalAPI::class)

package app.poruch.android

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import com.google.android.play.core.review.ReviewManagerFactory
import com.google.android.play.core.ktx.launchReview
import com.google.android.play.core.ktx.requestReview
import kotlinx.coroutines.CancellationException
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.tween
import androidx.compose.ui.layout.layout
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.lottie.compose.*
import androidx.core.content.edit
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import app.poruch.android.feature.OnboardingRoute
import app.poruch.android.feature.cityAt
import app.poruch.android.feature.lastKnownPosition
import app.poruch.android.navigation.*
import app.poruch.android.platform.NotificationPermission
import app.poruch.android.ui.*
import app.poruch.domain.EventLinks
import app.poruch.domain.PoruchLog
import app.poruch.shared.AppNotice
import app.poruch.shared.AppState
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.dropWhile
import kotlinx.coroutines.flow.first
import org.koin.android.ext.android.inject
import org.koin.androidx.compose.KoinAndroidContext
import org.koin.androidx.compose.navigation3.getEntryProvider
import org.koin.android.scope.AndroidScopeComponent
import org.koin.androidx.scope.activityRetainedScope
import org.koin.compose.koinInject
import org.koin.compose.navigation3.EntryProvider
import org.koin.core.annotation.KoinExperimentalAPI
import org.koin.core.scope.Scope
import java.util.Locale
import java.util.UUID

class MainActivity : ComponentActivity(), AndroidScopeComponent {
    /** Retained-скоуп: [Navigator] і записи стека переживають поворот. */
    override val scope: Scope by activityRetainedScope()
    private val app: PoruchApp by inject()

    /** Застосунок одномовний: без цього системні пікери й `java.time` виходили б мовою телефону. */
    override fun attachBaseContext(base: Context) {
        val locale = Locale.forLanguageTag(APP_LANGUAGE)
        Locale.setDefault(locale)
        val configuration = Configuration(base.resources.configuration).apply { setLocale(locale) }
        super.attachBaseContext(base.createConfigurationContext(configuration))
    }

    /**
     * Повернення в застосунок: запити на участь і членство могли змінитися, поки його не було. Дозвіл на сповіщення —
     * для каналу повернення: сервер чує, що пристрій живий (docs/guest-channel.md).
     */
    override fun onStart() {
        super.onStart()
        app.resume()
        app.notificationsAllowed(getSystemService(NotificationManager::class.java).areNotificationsEnabled())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handle(intent)
        // Записи стека збираємо зі скоупу Activity один раз, до композиції.
        val entryProvider = getEntryProvider<NavKey>()
        val navigator = scope.get<Navigator>()
        setContent {
            KoinAndroidContext {
                PoruchTheme {
                    PoruchRoot(navigator, entryProvider)
                    Splash()
                }
            }
        }
    }

    private fun handle(intent: Intent) {
        // Запуск з «Недавніх» несе старий intent: колбек уже використано, сповіщення вже відкривали.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val data = intent.data
        if (intent.action == Intent.ACTION_VIEW && data?.scheme == BuildConfig.AUTH_SCHEME && data.host == "auth") {
            app.handleAuthCallback(data.toString())
        }
        // Extras читаємо лише з наших сповіщень: Activity експортована, і чужа апка інакше підкинула б
        // причину в метрики чи змусила перехід. Посилання нижче публічні й так.
        val ours = intent.takeIf { it.getStringExtra(EXTRA_KEY) == launchKey(this) }
        // Дайджест вихідних веде на головну: там уся область, ранжована за смаком.
        if (ours?.action == ACTION_DIGEST) {
            scope.get<Navigator>().reset(Home)
            if (intent.hasExtra(EXTRA_STEP)) app.winbackOpened(intent.getIntExtra(EXTRA_STEP, 1))
            else app.digestOpened(intent.getIntExtra(EXTRA_WEEK, 1))
            return
        }
        // Тап по сповіщенню: що воно було — для метрики, яка повертає людей, а яка лише дратує.
        ours?.getStringExtra(EXTRA_REASON)?.let(app::pushOpened)
        // Пуш про кілька нових подій закладу: мапа на його стосі. Одна подія йде звичайним шляхом нижче.
        ours?.getStringExtra(EXTRA_PLACE_ID)?.let { placeId ->
            val navigator = scope.get<Navigator>()
            navigator.reset(Home)
            app.openPlace(placeId)
            navigator.open(Explore())
            return
        }
        // Пуш про кілька нових подій артиста: екран артиста поверх головної. Одна подія йде звичайним шляхом нижче.
        ours?.getStringExtra(EXTRA_ARTIST_ID)?.let { artistId ->
            val navigator = scope.get<Navigator>()
            navigator.reset(Home)
            app.openArtist(artistId)
            navigator.open(ArtistPage(artistId))
            return
        }
        // Посилання на подію (`poriad.app/e/…` чи `poriad://event/…`) і тап по сповіщенню: подія (або її чат)
        // поверх головної, «назад» веде туди, а не з застосунку.
        val linked = data?.takeIf { intent.action == Intent.ACTION_VIEW }?.let { EventLinks.eventId(it.toString()) }
        if (linked != null) app.eventLinkOpened(data.toString())
        val eventId = linked ?: ours?.getStringExtra(EXTRA_EVENT_ID) ?: return
        val navigator = scope.get<Navigator>()
        val target = if (ours?.getStringExtra(EXTRA_TARGET) == TARGET_CHAT) Chat(eventId) else Detail(eventId)
        // Та сама подія вже зверху: запис стека й модель лишаються, тож деталі перепитуємо самі — пуш
        // про зміну саме цієї події інакше показував би старі дату й стан.
        val reopened = navigator.current == target
        navigator.reset(Home)
        navigator.open(target)
        if (reopened && target is Detail) app.openEvent(eventId)
    }

    companion object {
        const val EXTRA_EVENT_ID = "eventId"
        private const val EXTRA_PLACE_ID = "placeId"
        private const val EXTRA_ARTIST_ID = "artistId"
        private const val EXTRA_REASON = "reason"
        private const val EXTRA_TARGET = "target"
        private const val EXTRA_WEEK = "week"
        private const val EXTRA_STEP = "step"
        private const val EXTRA_KEY = "key"
        private const val TARGET_CHAT = "chat"
        private const val APP_LANGUAGE = "uk"
        private const val ACTION_DIGEST = "app.poruch.OPEN_DIGEST"
        private const val LAUNCH_PREFS = "launch"

        /**
         * Випадковий ключ цієї установки в extras наших сповіщень (аудит L15). Своя дія не захистила б: її видно з APK,
         * а ключ лежить у приватних налаштуваннях. Сповіщення, показані до появи ключа, просто відкривають застосунок.
         */
        @Synchronized
        private fun launchKey(context: Context): String {
            val prefs = context.getSharedPreferences(LAUNCH_PREFS, Context.MODE_PRIVATE)
            return prefs.getString(EXTRA_KEY, null) ?: UUID.randomUUID().toString().also { prefs.edit { putString(EXTRA_KEY, it) } }
        }

        /** Intent сповіщення: відкрити подію або, з [chat], її чат. Наявний екземпляр отримує його в `onNewIntent`. */
        fun open(context: Context, eventId: String, chat: Boolean = false, reason: String? = null): Intent =
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_KEY, launchKey(context))
                .putExtra(EXTRA_EVENT_ID, eventId)
                .apply {
                    if (chat) putExtra(EXTRA_TARGET, TARGET_CHAT)
                    // Причина сповіщення для `push_open`: без неї (посилання, нагадування зі старого плану) метрики нема.
                    reason?.let { putExtra(EXTRA_REASON, it) }
                }

        /** Intent пуша про кілька нових подій закладу: мапа відкривається на його стосі. */
        fun openPlace(context: Context, placeId: String, reason: String): Intent =
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_KEY, launchKey(context))
                .putExtra(EXTRA_PLACE_ID, placeId)
                .putExtra(EXTRA_REASON, reason)

        /** Intent пуша про кілька нових подій артиста: його екран відкривається поверх головної. */
        fun openArtist(context: Context, artistId: String, reason: String): Intent =
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_KEY, launchKey(context))
                .putExtra(EXTRA_ARTIST_ID, artistId)
                .putExtra(EXTRA_REASON, reason)

        /**
         * Intent [week]-го дайджесту драбини. Своя дія: PendingIntent не сплутається з intent-ом події, extras він не
         * порівнює. Тиждень — для `digest_open`; новіший дайджест заміняє старий у шторці разом з його тижнем.
         */
        fun openDigest(context: Context, week: Int): Intent =
            Intent(context, MainActivity::class.java).setAction(ACTION_DIGEST).putExtra(EXTRA_WEEK, week)
                .putExtra(EXTRA_KEY, launchKey(context))
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

        /** Intent пуша повернення: та сама дія, що в дайджесту, а [step] замість тижня — для `push_open`. */
        fun openWinback(context: Context, step: Int): Intent =
            Intent(context, MainActivity::class.java).setAction(ACTION_DIGEST).putExtra(EXTRA_STEP, step)
                .putExtra(EXTRA_KEY, launchKey(context))
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
}

@Composable
fun PoruchRoot(navigator: Navigator, entryProvider: EntryProvider<NavKey>) {
    val context = LocalContext.current
    val app = koinInject<PoruchApp>()
    val appState = app.state.collectAsStateWithLifecycle()
    // Мапа вкладки живе стільки, скільки корінь. Див. [SharedMapView].
    val sharedMap = remember { SharedMapView(context) }
    DisposableEffect(sharedMap) { onDispose { sharedMap.destroy() } }

    // Перший-другий запуск: лише новим показуємо, де що на головній (docs/coach-marks.md). Читаємо до того,
    // як ефект дайджесту нижче порахує цей запуск, тож на першому тут 0.
    val newcomer = remember { context.getSharedPreferences(PROMPTS, Context.MODE_PRIVATE).getInt(LAUNCHES, 0) < 2 }
    // Нового спершу вітаємо туром по головній, а про геолокацію питаємо вже після нього.
    var tourDone by rememberSaveable { mutableStateOf(!newcomer) }
    LocationPrompt(app, appState, tourDone)
    var digestAsk by remember { mutableStateOf(false) }
    DigestPrompt(app, appState, navigator, digestAsk) { digestAsk = it }
    NotificationPromptAfter(appState, FOLLOW_ASKED) { it.library.followsMade }
    // Закладка, і гостя теж: нагадування напередодні без дозволу не прийде (docs/guest-saves.md).
    NotificationPromptAfter(appState, SAVE_ASKED) { if (it.remindersEnabled) it.library.savesMade else 0 }
    ReviewPrompt(app, appState)
    PasswordRecoveryEffect(navigator, appState)

    // Без провайдера вкладка «Мапа» будувала нову MapView на кожен вхід.
    CompositionLocalProvider(LocalSharedMapView provides sharedMap) {
        RootLayout(navigator, entryProvider, app, appState, tourAllowed = newcomer && !digestAsk) { tourDone = true }
    }
}

/**
 * Стартове місто — те, де людина зараз, а не Київ за замовчуванням. Приблизне положення, без
 * підписки: відмову мовчки приймаємо, «Поруч» на мапі лишається ручним шляхом.
 */
@Composable
private fun LocationPrompt(app: PoruchApp, appState: State<AppState>, tourDone: Boolean) {
    val context = LocalContext.current
    val state by appState
    val nearby = stringResource(R.string.nearby)
    val locate = {
        context.lastKnownPosition({ lat, lon, _ ->
            context.cityAt(
                lat,
                lon,
                nearby,
                app::locatedCity
            )
        }, {})
    }
    val locationPermission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { if (it) locate() }
    // Один раз на запуск, а не на кожен поворот. Обране руками місто спільний код не перебиває.
    var located by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.needsOnboarding, tourDone) {
        if (state.needsOnboarding || located) return@LaunchedEffect
        if (context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            located = true
            return@LaunchedEffect locate()
        }
        if (!tourDone) return@LaunchedEffect
        // Питаємо раз, після онбордингу й туру; далі — лише кнопкою «Поруч» на мапі. Пауза — щоб системне вікно
        // не наклалось на згасання підказки.
        delay(400)
        located = true
        val prompts = context.getSharedPreferences(PROMPTS, Context.MODE_PRIVATE)
        if (prompts.getBoolean(LOCATION_ASKED, false)) return@LaunchedEffect
        prompts.edit { putBoolean(LOCATION_ASKED, true) }
        locationPermission.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
    }
}

/**
 * Дайджест вихідних: без дозволу питаємо раз, спершу своїми словами. Уже в першій сесії — щойно людина
 * закрила першу картку події: побачила, що тут є, і «скажемо в пʼятницю» має сенс. Хто карток не відкривав,
 * того — на другому запуску. Без дозволу Android 13+ мовчить, а до 13 дозволу нема й питати нема про що.
 */
@SuppressLint("InlinedApi") // POST_NOTIFICATIONS питаємо лише коли NotificationPermission.required (API 33+).
@Composable
private fun DigestPrompt(app: PoruchApp, appState: State<AppState>, navigator: Navigator, digestAsk: Boolean, onDigestAsk: (Boolean) -> Unit) {
    val context = LocalContext.current
    val state by appState
    val digestPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission(), app::digestPromptAnswered)
    val prompts = remember { context.getSharedPreferences(PROMPTS, Context.MODE_PRIVATE) }
    fun ask() {
        if (prompts.getBoolean(DIGEST_ASKED, false) || !appState.value.digestEnabled || NotificationPermission(context).granted()) return
        prompts.edit { putBoolean(DIGEST_ASKED, true) }
        onDigestAsk(true)
    }
    var counted by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.needsOnboarding) {
        if (state.needsOnboarding || counted) return@LaunchedEffect
        counted = true
        val launches = prompts.getInt(LAUNCHES, 0) + 1
        prompts.edit { putInt(LAUNCHES, launches) }
        if (launches >= 2) ask()
    }
    // Картку закрито: у стеку була подія, а тепер нема. Чат з картки чи перехід на іншу подію — ще не закрито.
    LaunchedEffect(Unit) {
        snapshotFlow { navigator.stack.any { it is Detail } }.dropWhile { !it }.first { !it }
        // Пауза — щоб лист не наклався на анімацію «назад».
        delay(400)
        ask()
    }
    if (digestAsk) PoruchSheet({ onDigestAsk(false) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(stringResource(R.string.digest_prompt_title), style = PoruchType.brandTitle2, color = Poruch.colors.ink)
            Text(
                stringResource(R.string.digest_prompt_body), style = MaterialTheme.typography.bodyLarge,
                color = Poruch.colors.inkSecondary, modifier = Modifier.padding(bottom = Spacing.sm)
            )
            PrimaryButton(
                stringResource(R.string.digest_prompt_yes),
                { sheet.close { digestPermission.launch(Manifest.permission.POST_NOTIFICATIONS) } }, Modifier.fillMaxWidth()
            )
            SecondaryButton(
                stringResource(R.string.digest_prompt_no),
                { sheet.close { app.digestPromptAnswered(false) } }, Modifier.fillMaxWidth()
            )
        }
    }
}

/**
 * «Стежити» і закладка без дозволу на сповіщення марні: не дійдуть ні пуші про нове, ні нагадування напередодні.
 * Питаємо раз на причину ([flag]), одразу після першої дії ([made] > 0): людина щойно сама попросила, і причина
 * зрозуміла. До Android 13 дозволу нема й питати нема про що.
 */
@SuppressLint("InlinedApi") // POST_NOTIFICATIONS питаємо лише коли NotificationPermission.required (API 33+).
@Composable
private fun NotificationPromptAfter(appState: State<AppState>, flag: String, made: (AppState) -> Int) {
    val context = LocalContext.current
    val count = made(appState.value)
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    LaunchedEffect(count) {
        if (count == 0) return@LaunchedEffect
        val prompts = context.getSharedPreferences(PROMPTS, Context.MODE_PRIVATE)
        if (prompts.getBoolean(flag, false) || NotificationPermission(context).granted()) return@LaunchedEffect
        prompts.edit { putBoolean(flag, true) }
        permission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}

/**
 * Відгук у Play: після оцінки події 4–5, раз на версію. Чи показати вікно, вирішує сам Play (має свої ліміти),
 * і чи людина відповіла, він не каже — тож жодних «дякуємо» після.
 */
@Composable
private fun ReviewPrompt(app: PoruchApp, appState: State<AppState>) {
    val context = LocalContext.current
    val state by appState
    val activity = LocalActivity.current
    LaunchedEffect(state.reviewMoment) {
        if (!state.reviewMoment) return@LaunchedEffect
        val prompts = context.getSharedPreferences(PROMPTS, Context.MODE_PRIVATE)
        if (activity == null || prompts.getString(REVIEW_ASKED_VERSION, null) == BuildConfig.VERSION_NAME) {
            return@LaunchedEffect app.reviewMomentHandled(prompted = false)
        }
        prompts.edit { putString(REVIEW_ASKED_VERSION, BuildConfig.VERSION_NAME) }
        val reviews = ReviewManagerFactory.create(activity)
        val prompted = try {
            reviews.launchReview(activity, reviews.requestReview()); true
        } catch (e: CancellationException) { throw e } catch (e: Exception) {
            PoruchLog.w("review") { "in-app review unavailable: ${e.message}" }; false
        }
        app.reviewMomentHandled(prompted)
    }
}

/** Лист відновлення: окремий екран поверх того, де людина була. Профіль лишається запасним шляхом. */
@Composable
private fun PasswordRecoveryEffect(navigator: Navigator, appState: State<AppState>) {
    val state by appState
    LaunchedEffect(state.session.passwordRecovery) {
        if (state.session.passwordRecovery && navigator.current != NewPassword) navigator.open(
            NewPassword
        )
    }
}

/**
 * Клас ширини вікна, а не модель пристрою: від 600 dp (планшет, телефон у ландшафті, широке вікно поруч з іншим
 * застосунком) вкладки стають рейкою зліва, а вміст — колонкою по центру. Виріз екрана збоку — поле.
 */
@Composable
private fun RootLayout(
    navigator: Navigator,
    entryProvider: EntryProvider<NavKey>,
    app: PoruchApp,
    appState: State<AppState>,
    /** Тур першого знайомства можна показати: новачок, і лист дайджесту не відкритий. */
    tourAllowed: Boolean,
    onTourDone: () -> Unit
) {
    val state by appState
    val current = navigator.current
    BoxWithConstraints(Modifier
        .fillMaxSize()
        .background(Poruch.colors.canvas)
        .windowInsetsPadding(WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal))) {
        val wide = maxWidth >= 600.dp
        // Онбординг замінює застосунок, а не накриває: за ним на першому запуску ще нічого нема.
        if (state.needsOnboarding) OnboardingRoute() else {
            // Кожен запис стека має власне сховище моделей: пушнуті екрани переживають поворот і
            // чистяться при знятті. Вкладки беруть моделі зі сховища Activity, див. `activityStoreOwner`.
            // Список декораторів — один на композицію: новий екземпляр на кожну емісію стану
            // перескладав би `NavDisplay` з усім екраном під ним.
            val saveable = rememberSaveableStateHolderNavEntryDecorator<NavKey>()
            val stores = rememberViewModelStoreNavEntryDecorator<NavKey>()
            val decorators = remember(saveable, stores) { listOf(saveable, stores) }
            BackHandler(navigator.handlesRootBack, navigator::back)
            CompositionLocalProvider(LocalWideLayout provides wide) {
                NavDisplay(
                    backStack = navigator.stack,
                    // Рейка не накриває вміст вкладки: поле зліва лише поки вона видна.
                    modifier = Modifier.padding(start = if (wide && current is Tab) NavRailClearance else 0.dp),
                    onBack = navigator::back,
                    entryDecorators = decorators,
                    entryProvider = entryProvider
                )
            }
            TabBar(
                current,
                navigator,
                Modifier.align(if (wide) Alignment.CenterStart else Alignment.BottomCenter),
                wide = wide,
                waiting = state.waitingEvents,
                newFollows = state.library.newFollowEvents > 0,
                onCreate = {
                    app.createStarted("fab")
                    navigator.createEvent()
                }
            )
            // Лише на головній й не разом з іншим питанням: пуш чи посилання, що відкрили подію, ставлять тур на
            // паузу, а лист дайджесту (другий запуск) відкладає його, поки людина не відповість.
            CoachMarks(listOf(CoachTip.CITY, CoachTip.MAP, CoachTip.CREATE), enabled = tourAllowed && current == Home, onFinish = onTourDone)
        }
        NoticeHost(state.notice, app::clearNotice, Modifier.align(Alignment.TopCenter))
        if (state.mutating) LinearProgressIndicator(
            Modifier
                .fillMaxWidth()
                .align(Alignment.TopCenter),
            color = Poruch.colors.brand, trackColor = Poruch.colors.brandContainer
        )
    }
}

@Composable
private fun TabBar(
    current: NavKey,
    navigator: Navigator,
    modifier: Modifier,
    /** Широке вікно: рейка зліва замість нижньої панелі. */
    wide: Boolean = false,
    waiting: Int = 0,
    /** Нове в підписках — крапкою на «Профілі»: звідти відкривається «Ви стежите». */
    newFollows: Boolean = false,
    onCreate: () -> Unit
) {
    val reducedMotion = Poruch.reducedMotion
    val tabs = listOf(
        TabItem(Home.tabKey(), stringResource(R.string.home), PoruchIcons.home),
        TabItem(Explore().tabKey(), stringResource(R.string.map), PoruchIcons.map, tip = CoachTip.MAP),
        // Чати з непрочитаним і запити на участь живуть у «Моїх подіях»: туди й бейдж, по одному на подію.
        TabItem(
            Mine.tabKey(),
            stringResource(R.string.my_events),
            PoruchIcons.calendar,
            badge = waiting
        ),
        TabItem(Profile.tabKey(), stringResource(R.string.profile), PoruchIcons.person, dot = newFollows)
    )
    AnimatedVisibility(
        visible = current is Tab,
        enter = when {
            reducedMotion -> fadeIn()
            wide -> fadeIn() + slideInHorizontally { -it }
            else -> fadeIn() + slideInVertically { it }
        },
        exit = when {
            reducedMotion -> fadeOut()
            wide -> fadeOut() + slideOutHorizontally { -it }
            else -> fadeOut() + slideOutVertically { it }
        },
        modifier = modifier
    ) {
        val select = { key: String -> navigator.open(tabFor(key)) }
        if (wide) PoruchNavRail(tabs, current.tabKey(), Modifier.navigationBarsPadding(), onSelect = select) {
            CreateButton(onCreate, Modifier.coachTarget(CoachTip.CREATE))
        } else PoruchTabBar(
            tabs, current.tabKey(), Modifier
                .navigationBarsPadding()
                .padding(bottom = Spacing.md),
            onSelect = select
        ) {
            CreateButton(onCreate, Modifier.coachTarget(CoachTip.CREATE))
        }
    }
}

/** Таббар розрізняє вкладки за класом: `Explore` з будь-яким `focusId` — та сама вкладка. */
private fun NavKey.tabKey(): String = this::class.simpleName.orEmpty()
private fun tabFor(key: String): Tab = when (key) {
    Explore().tabKey() -> Explore()
    Mine.tabKey() -> Mine
    Profile.tabKey() -> Profile
    else -> Home
}

/** Банер під статус-баром. Останній текст тримаємо до кінця анімації; помилки висять довше. */
@Composable
private fun NoticeHost(notice: AppNotice?, dismiss: () -> Unit, modifier: Modifier) {
    val reducedMotion = Poruch.reducedMotion
    var shown by remember { mutableStateOf<AppNotice?>(null) }
    LaunchedEffect(notice) {
        val current = notice ?: return@LaunchedEffect
        shown = current
        delay(if (current.isError) ERROR_NOTICE_MS else INFO_NOTICE_MS)
        dismiss()
    }
    AnimatedVisibility(
        visible = notice != null,
        enter = if (reducedMotion) fadeIn() else fadeIn() + slideInVertically { -it },
        exit = if (reducedMotion) fadeOut() else fadeOut() + slideOutVertically { -it },
        modifier = modifier
    ) {
        shown?.let {
            NoticeBanner(
                it.text(), it.isError, dismiss,
                Modifier
                    .statusBarsPadding()
                    .padding(horizontal = Spacing.page, vertical = Spacing.sm)
            )
        }
    }
}

/**
 * Сплеш поверх застосунку, що вже вантажиться під ним: на диску мапи спливають події, у центр падає
 * шпилька з іконки, під нею зʼявляються назва й обіцянка. Системний сплеш — те саме полотно без іконки
 * (styles.xml), тож шва нема. Анімація — tools/generate_lottie.py.
 */
@Composable
private fun Splash() {
    val colors = Poruch.colors
    val reducedMotion = Poruch.reducedMotion
    var done by rememberSaveable { mutableStateOf(reducedMotion) }
    var titled by remember { mutableStateOf(false) }
    val composition by rememberLottieComposition(LottieCompositionSpec.RawRes(R.raw.splash))
    val progress by animateLottieCompositionAsState(composition)
    LaunchedEffect(progress == 1f) { if (progress == 1f) done = true }
    LaunchedEffect(Unit) {
        delay(950) // шпилька торкається землі
        titled = true
        // Страховка: анімація не завантажилась чи не відіграла — не тримаємо людину на сплеші.
        delay(2_500)
        done = true
    }
    val title by animateFloatAsState(if (titled) 1f else 0f, tween(400), label = "title")
    // Вихід — наліт на мапу: сплеш росте з центру й розчиняється в головній.
    val exit = tween<Float>(450, easing = FastOutLinearInEasing)
    AnimatedVisibility(
        !done,
        enter = EnterTransition.None,
        exit = fadeOut(exit) + scaleOut(exit, targetScale = 2.4f)
    ) {
        Box(Modifier
            .fillMaxSize()
            .background(colors.canvas), contentAlignment = Alignment.Center) {
            LottieAnimation(composition, { progress }, Modifier.size(280.dp))
            // Назва висить під мапою, а не стоїть з нею в стовпці: так мапа точно в центрі екрана,
            // і виліт у місто йде з неї. Приходить, коли шпилька торкається землі.
            Column(
                Modifier
                    .layout { measurable, constraints ->
                        val text = measurable.measure(constraints)
                        layout(text.width, text.height) {
                            text.place(
                                0,
                                text.height / 2 + (140.dp + Spacing.xs).roundToPx()
                            )
                        }
                    }
                    .graphicsLayer { alpha = title; translationY = (1 - title) * 8.dp.toPx() },
                Arrangement.spacedBy(Spacing.xs), Alignment.CenterHorizontally
            ) {
                Text(
                    stringResource(R.string.brand_name),
                    style = PoruchType.brandDisplay,
                    color = colors.ink
                )
                Text(
                    stringResource(R.string.tagline),
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.inkSecondary
                )
            }
        }
    }
}

private const val PROMPTS = "prompts"
private const val LOCATION_ASKED = "location_asked"
private const val LAUNCHES = "launches"
private const val DIGEST_ASKED = "digest_asked"
private const val FOLLOW_ASKED = "follow_asked"
private const val SAVE_ASKED = "save_asked"
private const val REVIEW_ASKED_VERSION = "review_asked_version"
private const val INFO_NOTICE_MS = 3_000L
private const val ERROR_NOTICE_MS = 5_000L

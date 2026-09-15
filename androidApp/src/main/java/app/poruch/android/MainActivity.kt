@file:OptIn(KoinExperimentalAPI::class)

package app.poruch.android

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import app.poruch.android.feature.OnboardingRoute
import app.poruch.android.navigation.*
import app.poruch.android.ui.*
import app.poruch.shared.AppNotice
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.delay
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
                PoruchTheme { PoruchRoot(navigator, entryProvider) }
            }
        }
    }

    private fun handle(intent: Intent) {
        intent.dataString?.let(app::handleAuthCallback)
        intent.getStringExtra(EXTRA_EVENT_ID)?.let(app::selectEvent)
    }

    companion object {
        const val EXTRA_EVENT_ID = "eventId"
        private const val APP_LANGUAGE = "uk"
    }
}

@Composable
fun PoruchRoot(navigator: Navigator, entryProvider: EntryProvider<NavKey>) {
    val context = LocalContext.current
    val app = koinInject<PoruchApp>()
    val state by app.state.collectAsStateWithLifecycle()
    val current = navigator.current
    // Мапа вкладки живе стільки, скільки корінь. Див. [SharedMapView].
    val sharedMap = remember { SharedMapView(context) }
    DisposableEffect(sharedMap) { onDispose { sharedMap.destroy() } }

    LaunchedEffect(state.passwordRecovery) { if (state.passwordRecovery) navigator.reset(Profile) }

    // Без провайдера вкладка «Мапа» будувала нову MapView на кожен вхід.
    CompositionLocalProvider(LocalSharedMapView provides sharedMap) {
    Box(Modifier.fillMaxSize().background(Poruch.colors.canvas)) {
        // Онбординг замінює застосунок, а не накриває: за ним на першому запуску ще нічого нема.
        if (state.needsOnboarding) OnboardingRoute() else {
            // Кожен запис стека має власне сховище моделей: пушнуті екрани переживають поворот і
            // чистяться при знятті. Вкладки беруть моделі зі сховища Activity, див. `activityStoreOwner`.
            NavDisplay(
                backStack = navigator.stack,
                onBack = navigator::back,
                entryDecorators = listOf(
                    rememberSaveableStateHolderNavEntryDecorator(),
                    rememberViewModelStoreNavEntryDecorator()
                ),
                entryProvider = entryProvider
            )
            TabBar(current, navigator, Modifier.align(Alignment.BottomCenter))
        }
        NoticeHost(state.notice, app::clearNotice, Modifier.align(Alignment.TopCenter))
        if (state.mutating) LinearProgressIndicator(
            Modifier.fillMaxWidth().align(Alignment.TopCenter),
            color = Poruch.colors.brand, trackColor = Poruch.colors.brandContainer
        )
    }
    }
}

@Composable
private fun TabBar(current: NavKey, navigator: Navigator, modifier: Modifier) {
    val reducedMotion = Poruch.reducedMotion
    val tabs = listOf(
        TabItem(Home.tabKey(), stringResource(R.string.home), PoruchIcons.home),
        TabItem(Explore().tabKey(), stringResource(R.string.map), PoruchIcons.map),
        TabItem(Mine.tabKey(), stringResource(R.string.my_events), PoruchIcons.calendar),
        TabItem(Profile.tabKey(), stringResource(R.string.profile), PoruchIcons.person)
    )
    AnimatedVisibility(
        visible = current is Tab,
        enter = if (reducedMotion) fadeIn() else fadeIn() + slideInVertically { it },
        exit = if (reducedMotion) fadeOut() else fadeOut() + slideOutVertically { it },
        modifier = modifier
    ) {
        PoruchTabBar(
            tabs, current.tabKey(), Modifier.navigationBarsPadding().padding(bottom = Spacing.md),
            onSelect = { key -> navigator.open(tabFor(key)) }
        ) {
            CreateButton({ navigator.requireAccount { navigator.open(Editor()) } })
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
                Modifier.statusBarsPadding().padding(horizontal = Spacing.page, vertical = Spacing.sm)
            )
        }
    }
}

private const val INFO_NOTICE_MS = 3_000L
private const val ERROR_NOTICE_MS = 5_000L

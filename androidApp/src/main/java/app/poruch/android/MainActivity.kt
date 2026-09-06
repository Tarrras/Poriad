package app.poruch.android

import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import app.poruch.android.feature.*
import app.poruch.android.mvi.LocalPoruchApp
import app.poruch.android.ui.*
import app.poruch.domain.PoruchLog
import app.poruch.shared.AppConfig
import app.poruch.shared.AppGraph
import app.poruch.shared.AppNotice
import app.poruch.shared.PlatformSetup
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable
import java.util.Locale

@Serializable
data class Route(val screen: Screen, val id: String = "") : NavKey

/** Holds the object graph for the process; screens get their own ViewModels from it. */
class PoruchModel(application: Application) : AndroidViewModel(application) {
    init {
        // Tracing is a debug-build tool; release keeps the sinks silent.
        PoruchLog.enabled = BuildConfig.DEBUG
        PlatformSetup.initialize(application)
        PoruchLog.i("app") { "graph created" }
    }

    private val graph = AppGraph(AppConfig(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_KEY), SessionStore(application))
    val app = graph.app
    override fun onCleared() { graph.close() }
}

class MainActivity : ComponentActivity() {
    private val model: PoruchModel by viewModels()

    /**
     * The app ships one language, so it runs in it regardless of the phone's setting. Without this
     * the platform pickers and `java.time` formatting would come out in the system locale while
     * every string around them stayed Ukrainian.
     */
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
        setContent {
            CompositionLocalProvider(LocalPoruchApp provides model.app) {
                PoruchTheme { PoruchRoot() }
            }
        }
    }

    private fun handle(intent: Intent) {
        intent.dataString?.let(model.app::handleAuthCallback)
        intent.getStringExtra(EXTRA_EVENT_ID)?.let(model.app::selectEvent)
    }

    companion object {
        const val EXTRA_EVENT_ID = "eventId"
        private const val APP_LANGUAGE = "uk"
    }
}

/** Tabs keep their own root; everything else is pushed on top of the current one. */
private val TAB_SCREENS = listOf(Screen.HOME, Screen.MAP, Screen.MINE, Screen.PROFILE)

@Composable
fun PoruchRoot() {
    val context = LocalContext.current
    val app = LocalPoruchApp.current
    val state by app.state.collectAsStateWithLifecycle()
    val stack = rememberNavBackStack(Route(Screen.HOME))
    val route = stack.last() as Route

    LaunchedEffect(state.myEvents, state.userId) { Reminders.sync(context, state) }
    LaunchedEffect(state.passwordRecovery) {
        if (state.passwordRecovery) { stack.clear(); stack.add(Route(Screen.PROFILE)) }
    }

    fun navigate(screen: Screen, id: String) {
        if (screen in TAB_SCREENS) { stack.clear(); stack.add(Route(screen)) } else stack.add(Route(screen, id))
    }
    fun back() { if (stack.size > 1) stack.removeLastOrNull() }
    fun requireAccount(action: () -> Unit) { if (state.signedIn) action() else navigate(Screen.AUTH, "") }

    Box(Modifier.fillMaxSize().background(Poruch.colors.canvas)) {
        NavDisplay(backStack = stack, onBack = { back() }, entryProvider = entryProvider {
            entry<Route> { current ->
                when (current.screen) {
                    Screen.HOME -> HomeRoute(::navigate, ::requireAccount)
                    Screen.MAP -> ExploreRoute(::navigate, ::requireAccount)
                    Screen.MINE -> MyEventsRoute(::navigate, ::requireAccount)
                    Screen.PROFILE -> ProfileRoute(::navigate)
                    Screen.AUTH -> AuthRoute(::back)
                    Screen.DETAIL -> DetailRoute(current.id, ::back, ::navigate)
                    Screen.EDITOR -> EditorRoute(current.id.takeIf { it.isNotEmpty() }, ::back)
                }
            }
        })
        TabBar(route.screen, ::navigate, ::requireAccount, Modifier.align(Alignment.BottomCenter))
        NoticeHost(state.notice, app::clearNotice, Modifier.align(Alignment.TopCenter))
        if (state.mutating) LinearProgressIndicator(
            Modifier.fillMaxWidth().align(Alignment.TopCenter),
            color = Poruch.colors.brand, trackColor = Poruch.colors.brandContainer
        )
    }
}

@Composable
private fun TabBar(
    current: Screen, navigate: (Screen, String) -> Unit, requireAccount: (() -> Unit) -> Unit, modifier: Modifier
) {
    val reducedMotion = Poruch.reducedMotion
    val tabs = listOf(
        TabItem(Screen.HOME.name, stringResource(R.string.home), PoruchIcons.home),
        TabItem(Screen.MAP.name, stringResource(R.string.map), PoruchIcons.map),
        TabItem(Screen.MINE.name, stringResource(R.string.my_events), PoruchIcons.calendar),
        TabItem(Screen.PROFILE.name, stringResource(R.string.profile), PoruchIcons.person)
    )
    AnimatedVisibility(
        visible = current in TAB_SCREENS,
        enter = if (reducedMotion) fadeIn() else fadeIn() + slideInVertically { it },
        exit = if (reducedMotion) fadeOut() else fadeOut() + slideOutVertically { it },
        modifier = modifier
    ) {
        PoruchTabBar(
            tabs, current.name, Modifier.navigationBarsPadding().padding(bottom = Spacing.md),
            onSelect = { navigate(Screen.valueOf(it), "") }
        ) {
            CreateButton({ requireAccount { navigate(Screen.EDITOR, "") } })
        }
    }
}

/**
 * Notices land under the status bar. The last one is held past the clear so the text does not
 * vanish mid-exit, and errors linger longer because they usually ask for a decision.
 */
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

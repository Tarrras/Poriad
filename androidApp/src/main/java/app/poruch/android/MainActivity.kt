package app.poruch.android

import android.app.Application
import android.os.Bundle
import android.content.Intent
import androidx.activity.viewModels
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import app.poruch.shared.*
import kotlinx.serialization.Serializable

@Serializable data class Route(val screen: String, val id: String = "") : NavKey
class PoruchModel(application: Application) : AndroidViewModel(application) {
    init { PlatformSetup.initialize(application) }
    private val graph = AppGraph(AppConfig(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_KEY), SessionStore(application))
    val app = graph.app
    override fun onCleared() { graph.close() }
}
class MainActivity : ComponentActivity() {
    private val model: PoruchModel by viewModels()
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); intent.dataString?.let(model.app::handleAuthCallback); intent.getStringExtra("eventId")?.let(model.app::selectEvent) }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) { intent.dataString?.let(model.app::handleAuthCallback); intent.getStringExtra("eventId")?.let(model.app::selectEvent) }
        setContent {
            val colors = if (isSystemInDarkTheme()) darkColorScheme(primary = Color(0xFF9BD7B8)) else lightColorScheme(primary = Color(0xFF246A50), background = Color(0xFFF8F8F2), surface = Color(0xFFF8F8F2), secondaryContainer = Color(0xFFE0EDDF))
            MaterialTheme(colorScheme = colors) { PoruchRoot() }
        }
    }
}
@Composable fun PoruchRoot(model: PoruchModel = viewModel()) {
    val context = LocalContext.current
    val app = model.app
    val state by app.state.collectAsStateWithLifecycle()
    val stack = rememberNavBackStack(Route("map"))
    LaunchedEffect(state.myEvents, state.userId) { Reminders.sync(context, state) }
    LaunchedEffect(state.passwordRecovery) { if (state.passwordRecovery) { stack.clear(); stack.add(Route("profile")) } }
    val snackbar = remember { SnackbarHostState() }
    val route = stack.last() as Route
    fun navigate(screen: String, id: String = "") { stack.add(Route(screen, id)) }
    fun authenticated(action: () -> Unit) { if (state.userId == null) navigate("auth") else action() }
    LaunchedEffect(state.message) { state.message?.let { snackbar.showSnackbar(it); app.clearMessage() } }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }, bottomBar = {
        if (route.screen in listOf("map", "mine", "profile")) NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
            listOf(Triple("map", R.string.map, Icons.Outlined.Map), Triple("mine", R.string.my_events, Icons.Outlined.CalendarMonth), Triple("profile", R.string.profile, Icons.Outlined.Person)).forEach { (key, label, icon) ->
                NavigationBarItem(selected = route.screen == key, onClick = { stack.clear(); stack.add(Route(key)); if (key == "mine") app.loadMyEvents() }, icon = { Icon(icon, null) }, label = { Text(stringResource(label)) })
            }
        }
    }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (state.offline) Text(stringResource(R.string.offline), Modifier.padding(12.dp), color = MaterialTheme.colorScheme.error)
            if (state.loading || state.mutating) LinearProgressIndicator(Modifier.fillMaxWidth())
            NavDisplay(backStack = stack, onBack = { if (stack.size > 1) stack.removeLastOrNull() }, entryProvider = entryProvider {
                entry<Route> { current ->
                    when (current.screen) {
                        "map" -> ExploreScreen(state, app, { navigate("detail", it) }, { authenticated { navigate("create") } })
                        "mine" -> MyEventsScreen(state, { navigate("detail", it); app.selectEvent(it) }, { navigate("auth") }, app::loadMyEvents)
                        "profile" -> ProfileScreen(state, app, { navigate("auth") }, app::signOut)
                        "auth" -> AuthScreen(state, app) { stack.removeLastOrNull() }
                        "detail" -> { LaunchedEffect(current.id) { app.selectEvent(current.id) }; DetailScreen(state, app, { stack.removeLastOrNull() }, { authenticated(it) }, { navigate("edit", it) }) }
                        "create", "edit" -> { LaunchedEffect(current.id) { if (current.screen == "edit") app.selectEvent(current.id) }; if (current.screen == "edit" && state.selectedEvent?.id != current.id) { PageHeader(stringResource(R.string.loading)) { stack.removeLastOrNull() } } else EditorScreen(state, app, current.screen == "edit", { stack.removeLastOrNull() }) }
                    }
                }
            })
        }
    }
}

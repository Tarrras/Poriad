package app.poruch.android.feature

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.location.LocationManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.poruch.android.R
import app.poruch.android.ReminderPreference
import app.poruch.android.feature.account.*
import app.poruch.android.feature.detail.*
import app.poruch.android.feature.editor.*
import app.poruch.android.feature.explore.*
import app.poruch.android.feature.home.*
import app.poruch.android.feature.mine.*
import app.poruch.android.mvi.screenViewModel
import app.poruch.android.platform.*
import kotlinx.coroutines.flow.Flow

/**
 * Routes are the seam between a screen and the platform: they build the screen's ViewModel, turn
 * its effects into navigation or system calls, and keep both concerns out of the composables that
 * draw. Every screen below renders state and emits intents, nothing else.
 */

/** Collects one-shot effects for as long as the route is on screen. */
@Composable
private fun <E> Flow<E>.handle(onEffect: (E) -> Unit) {
    LaunchedEffect(this) { collect(onEffect) }
}

@Composable
fun HomeRoute(navigate: (Screen, String) -> Unit, requireAccount: (() -> Unit) -> Unit) {
    val model = screenViewModel { HomeViewModel(it) }
    model.effects.handle { effect ->
        when (effect) {
            is HomeEffect.Navigate -> when (effect.destination) {
                HomeDestination.DETAIL -> navigate(Screen.DETAIL, effect.id)
                HomeDestination.MAP -> navigate(Screen.MAP, "")
                HomeDestination.PROFILE -> navigate(Screen.PROFILE, "")
                HomeDestination.EDITOR -> requireAccount { navigate(Screen.EDITOR, "") }
            }
        }
    }
    HomeScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@SuppressLint("MissingPermission")
@Composable
fun ExploreRoute(navigate: (Screen, String) -> Unit, requireAccount: (() -> Unit) -> Unit) {
    val context = LocalContext.current
    val nearbyLabel = stringResource(R.string.nearby)
    val model = screenViewModel { ExploreViewModel(it) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        if (results.values.none { it }) {
            model.dispatch(ExploreIntent.LocationDenied)
            return@rememberLauncherForActivityResult
        }
        context.lastKnownPosition(
            onFound = { latitude, longitude -> model.dispatch(ExploreIntent.LocatedAt(nearbyLabel, latitude, longitude)) },
            onUnavailable = { model.dispatch(ExploreIntent.LocationDenied) }
        )
    }
    model.effects.handle { effect ->
        when (effect) {
            is ExploreEffect.OpenDetail -> navigate(Screen.DETAIL, effect.id)
            ExploreEffect.CreateEvent -> requireAccount { navigate(Screen.EDITOR, "") }
            ExploreEffect.AskLocationPermission -> permission.launch(
                arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
            )
        }
    }
    ExploreScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun MyEventsRoute(navigate: (Screen, String) -> Unit, requireAccount: (() -> Unit) -> Unit) {
    val model = screenViewModel { MyEventsViewModel(it) }
    model.effects.handle { effect ->
        when (effect) {
            is MyEventsEffect.OpenDetail -> navigate(Screen.DETAIL, effect.id)
            MyEventsEffect.SignIn -> navigate(Screen.AUTH, "")
            MyEventsEffect.CreateEvent -> requireAccount { navigate(Screen.EDITOR, "") }
        }
    }
    MyEventsScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun DetailRoute(eventId: String, back: () -> Unit, navigate: (Screen, String) -> Unit) {
    val context = LocalContext.current
    val model = screenViewModel(key = eventId) { DetailViewModel(it, eventId) }
    LaunchedEffect(eventId) { model.dispatch(DetailIntent.Load) }
    model.effects.handle { effect ->
        when (effect) {
            DetailEffect.Back -> back()
            is DetailEffect.Edit -> navigate(Screen.EDITOR, effect.id)
            DetailEffect.RequireSignIn -> navigate(Screen.AUTH, "")
            is DetailEffect.ShareEvent -> context.shareEvent(effect.event)
            is DetailEffect.OpenCalendar -> if (!context.addToCalendar(effect.event)) context.toast(R.string.calendar_unavailable)
            is DetailEffect.OpenMaps -> if (!context.openInMaps(effect.event)) context.toast(R.string.maps_unavailable)
        }
    }
    DetailScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun EditorRoute(editingId: String?, back: () -> Unit) {
    val context = LocalContext.current
    val drafts = remember(context) { DraftStore(context.applicationContext) }
    val model = screenViewModel(key = editingId ?: "new") { EditorViewModel(it, drafts, editingId) }
    model.effects.handle { effect -> when (effect) { EditorEffect.Close -> back() } }
    EditorScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch, back)
}

@Composable
fun AuthRoute(back: () -> Unit) {
    val model = screenViewModel { AuthViewModel(it) }
    model.effects.handle { effect -> when (effect) { AuthEffect.Close -> back() } }
    AuthScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun ProfileRoute(navigate: (Screen, String) -> Unit) {
    val model = screenViewModel { ProfileViewModel(it) }
    model.effects.handle { effect -> when (effect) { ProfileEffect.SignIn -> navigate(Screen.AUTH, "") } }
    ProfileScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch) { ReminderPreference() }
}

/**
 * Reads a coarse position without holding a location subscription: a last-known fix is enough to
 * move the map, and asking for a fresh one only when there is none keeps the radio quiet.
 */
@SuppressLint("MissingPermission")
private fun Context.lastKnownPosition(onFound: (Double, Double) -> Unit, onUnavailable: () -> Unit) {
    val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
    val known = manager.getProviders(true)
        .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
        .maxByOrNull { it.time }
    if (known != null) {
        onFound(known.latitude, known.longitude)
        return
    }
    val provider = if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) LocationManager.NETWORK_PROVIDER
    else LocationManager.GPS_PROVIDER
    if (Build.VERSION.SDK_INT >= 30 && manager.isProviderEnabled(provider)) {
        manager.getCurrentLocation(provider, null, mainExecutor) { fresh ->
            if (fresh != null) onFound(fresh.latitude, fresh.longitude) else onUnavailable()
        }
    } else onUnavailable()
}

/** Every destination the app can navigate to. The back stack stores these by name. */
enum class Screen { HOME, MAP, MINE, PROFILE, DETAIL, EDITOR, AUTH }

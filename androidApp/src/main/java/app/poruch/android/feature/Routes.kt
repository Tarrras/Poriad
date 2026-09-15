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
import app.poruch.android.feature.onboarding.*
import app.poruch.android.mvi.activityStoreOwner
import app.poruch.android.navigation.*
import app.poruch.android.platform.*
import kotlinx.coroutines.flow.Flow
import org.koin.androidx.compose.koinViewModel
import org.koin.core.parameter.parametersOf

/*
 * Маршрути — шов між екраном і платформою: беруть ViewModel з Koin, перетворюють ефекти на
 * навігацію чи системні виклики. Composable лише малюють стан і шлють інтенти.
 *
 * Два терміни життя моделей: вкладка ([activityStoreOwner]) переживає перемикання, пушнутий екран
 * бере модель зі сховища свого запису стека і чиститься при знятті.
 */

/** Збирає одноразові ефекти, поки маршрут на екрані. */
@Composable
private fun <E> Flow<E>.handle(onEffect: (E) -> Unit) {
    LaunchedEffect(this) { collect(onEffect) }
}

/** Онбординг. Без власної навігації: стор позначає відповіді даними, і корінь показує застосунок. */
@Composable
fun OnboardingRoute() {
    val model = koinViewModel<OnboardingViewModel>(viewModelStoreOwner = activityStoreOwner())
    OnboardingScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun HomeRoute(navigator: Navigator) {
    val model = koinViewModel<HomeViewModel>(viewModelStoreOwner = activityStoreOwner())
    model.effects.handle { effect ->
        when (effect) {
            is HomeEffect.Navigate -> when (effect.destination) {
                HomeDestination.DETAIL -> navigator.open(Detail(effect.id))
                HomeDestination.MAP -> navigator.open(Explore())
                HomeDestination.PROFILE -> navigator.open(Profile)
                HomeDestination.EDITOR -> navigator.requireAccount { navigator.open(Editor()) }
            }
        }
    }
    HomeScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@SuppressLint("MissingPermission")
@Composable
fun ExploreRoute(focusId: String, navigator: Navigator) {
    val context = LocalContext.current
    val nearbyLabel = stringResource(R.string.nearby)
    val model = koinViewModel<ExploreViewModel>(viewModelStoreOwner = activityStoreOwner())
    // Мапу відкрили з деталей події: наводимось на неї.
    LaunchedEffect(focusId) { if (focusId.isNotEmpty()) model.dispatch(ExploreIntent.FocusEvent(focusId)) }
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
            is ExploreEffect.OpenDetail -> navigator.open(Detail(effect.id))
            ExploreEffect.CreateEvent -> navigator.requireAccount { navigator.open(Editor()) }
            ExploreEffect.AskLocationPermission -> permission.launch(
                arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
            )
        }
    }
    ExploreScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun MyEventsRoute(navigator: Navigator) {
    val model = koinViewModel<MyEventsViewModel>(viewModelStoreOwner = activityStoreOwner())
    model.effects.handle { effect ->
        when (effect) {
            is MyEventsEffect.OpenDetail -> navigator.open(Detail(effect.id))
            MyEventsEffect.SignIn -> navigator.open(Auth)
            MyEventsEffect.CreateEvent -> navigator.requireAccount { navigator.open(Editor()) }
        }
    }
    MyEventsScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun DetailRoute(route: Detail, navigator: Navigator) {
    val context = LocalContext.current
    val model = koinViewModel<DetailViewModel> { parametersOf(route) }
    model.effects.handle { effect ->
        when (effect) {
            DetailEffect.Back -> navigator.back()
            is DetailEffect.Edit -> navigator.open(Editor(effect.id))
            DetailEffect.RequireSignIn -> navigator.open(Auth)
            is DetailEffect.ShareEvent -> context.shareEvent(effect.event)
            is DetailEffect.OpenCalendar -> if (!context.addToCalendar(effect.event)) context.toast(R.string.calendar_unavailable)
            is DetailEffect.OpenMaps -> if (!context.openInMaps(effect.event)) context.toast(R.string.maps_unavailable)
            is DetailEffect.OpenLink -> if (!context.openLink(effect.url)) context.toast(R.string.link_unavailable)
            is DetailEffect.OpenMap -> navigator.open(Explore(effect.id))
        }
    }
    DetailScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun EditorRoute(route: Editor, navigator: Navigator) {
    val model = koinViewModel<EditorViewModel> { parametersOf(route) }
    model.effects.handle { effect -> when (effect) { EditorEffect.Close -> navigator.back() } }
    EditorScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch, navigator::back)
}

@Composable
fun AuthRoute(navigator: Navigator) {
    val model = koinViewModel<AuthViewModel>()
    model.effects.handle { effect -> when (effect) { AuthEffect.Close -> navigator.back() } }
    AuthScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun ProfileRoute(navigator: Navigator) {
    val model = koinViewModel<ProfileViewModel>(viewModelStoreOwner = activityStoreOwner())
    model.effects.handle { effect -> when (effect) { ProfileEffect.SignIn -> navigator.open(Auth) } }
    ProfileScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch) { ReminderPreference() }
}

/** Грубе положення без підписки: останнього відомого досить, свіже просимо лише коли його нема. */
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

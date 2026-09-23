package app.poruch.android.feature

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.location.Geocoder
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
import app.poruch.android.feature.account.*
import app.poruch.android.feature.chat.*
import app.poruch.android.feature.detail.*
import app.poruch.android.feature.editor.*
import app.poruch.android.feature.explore.*
import app.poruch.android.feature.home.*
import app.poruch.android.feature.mine.*
import app.poruch.android.feature.onboarding.*
import app.poruch.android.mvi.activityStoreOwner
import app.poruch.android.navigation.*
import app.poruch.android.platform.*
import app.poruch.domain.CityResult
import kotlinx.coroutines.flow.Flow
import org.koin.androidx.compose.koinViewModel
import org.koin.core.parameter.parametersOf
import java.util.Locale
import kotlin.concurrent.thread

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
                HomeDestination.CHAT -> navigator.open(Chat(effect.id))
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
            onFound = { latitude, longitude ->
                context.cityAt(latitude, longitude, nearbyLabel) { model.dispatch(ExploreIntent.LocatedAt(it.name, it.latitude, it.longitude)) }
            },
            onUnavailable = { model.dispatch(ExploreIntent.LocationDenied) }
        )
    }
    model.effects.handle { effect ->
        when (effect) {
            is ExploreEffect.OpenDetail -> navigator.open(Detail(effect.id))
            ExploreEffect.CreateEvent -> navigator.requireAccount { navigator.open(Editor()) }
            ExploreEffect.AskLocationPermission -> permission.launch(
                // Лише приблизна: «події поруч» — це кілометр, а не метр, і Play не питає, навіщо точна.
                arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION)
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
    val notifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        model.dispatch(DetailIntent.NotificationPermissionAnswered(granted))
    }
    model.effects.handle { effect ->
        when (effect) {
            DetailEffect.Back -> navigator.back()
            DetailEffect.AskNotificationPermission -> notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
            is DetailEffect.Edit -> navigator.open(Editor(effect.id))
            DetailEffect.RequireSignIn -> navigator.open(Auth)
            is DetailEffect.ShareEvent -> context.shareEvent(effect.event)
            is DetailEffect.OpenCalendar -> if (!context.addToCalendar(effect.event)) context.toast(R.string.calendar_unavailable)
            is DetailEffect.OpenMaps -> if (!context.openInMaps(effect.event)) context.toast(R.string.maps_unavailable)
            is DetailEffect.OpenLink -> if (!context.openLink(effect.url)) context.toast(R.string.link_unavailable)
            is DetailEffect.OpenMap -> navigator.open(Explore(effect.id))
            is DetailEffect.OpenChat -> navigator.open(Chat(effect.id))
            is DetailEffect.OpenEvent -> navigator.open(Detail(effect.id))
        }
    }
    // Після повернення з іншого екрана деталей слот відкритої події треба забрати назад.
    LaunchedEffect(Unit) { model.dispatch(DetailIntent.Reopen) }
    DetailScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun ChatRoute(route: Chat, navigator: Navigator) {
    val model = koinViewModel<ChatViewModel> { parametersOf(route) }
    val context = LocalContext.current
    model.effects.handle { effect ->
        when (effect) {
            ChatEffect.Back -> navigator.back()
            is ChatEffect.Copy -> { context.copyText(effect.text); context.toast(R.string.chat_copied) }
        }
    }
    ChatScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun EditorRoute(route: Editor, navigator: Navigator) {
    val model = koinViewModel<EditorViewModel> { parametersOf(route) }
    val notifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        model.dispatch(EditorIntent.NotificationPermissionAnswered(granted))
    }
    model.effects.handle { effect ->
        when (effect) {
            EditorEffect.Close -> navigator.back()
            EditorEffect.AskNotificationPermission -> notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    EditorScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch, navigator::back)
}

@Composable
fun AuthRoute(navigator: Navigator) {
    val model = koinViewModel<AuthViewModel>()
    val context = LocalContext.current
    model.effects.handle { effect ->
        when (effect) {
            AuthEffect.Close -> navigator.back()
            AuthEffect.OpenMail -> context.openMailApp()
            is AuthEffect.OpenLink -> if (!context.openLink(effect.url)) context.toast(R.string.link_unavailable)
        }
    }
    AuthScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

@Composable
fun ProfileRoute(navigator: Navigator) {
    val model = koinViewModel<ProfileViewModel>(viewModelStoreOwner = activityStoreOwner())
    val context = LocalContext.current
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        model.dispatch(ProfileIntent.NotificationPermissionAnswered(granted))
    }
    model.effects.handle { effect ->
        when (effect) {
            ProfileEffect.SignIn -> navigator.open(Auth)
            ProfileEffect.AskNotificationPermission -> permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            is ProfileEffect.OpenLink -> if (!context.openLink(effect.url)) context.toast(R.string.link_unavailable)
            is ProfileEffect.WriteEmail -> if (!context.writeEmail(effect.address)) context.toast(R.string.mail_unavailable)
        }
    }
    ProfileScreen(model.state.collectAsStateWithLifecycle().value, model::dispatch)
}

/** Той самий стан профілю: поле нового пароля й прапорець відновлення живуть у ньому. */
@Composable
fun NewPasswordRoute(navigator: Navigator) {
    val model = koinViewModel<ProfileViewModel>(viewModelStoreOwner = activityStoreOwner())
    val state = model.state.collectAsStateWithLifecycle().value
    // Пароль збережено — екран більше не потрібен.
    LaunchedEffect(state.passwordRecovery) { if (!state.passwordRecovery) navigator.back() }
    NewPasswordScreen(state, model::dispatch)
}

/** Поштовий застосунок за категорією, без переліку клієнтів. Якщо його нема, лишаємось тут. */
private fun Context.openMailApp() {
    val intent = Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_EMAIL)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { startActivity(intent) }
}

/**
 * Місто за положенням: людина живе не в «Поруч зі мною», а в Полтаві. Геокодер системний, без
 * мережі своєї; коли він мовчить, лишається [fallback].
 */
internal fun Context.cityAt(latitude: Double, longitude: Double, fallback: String, onCity: (CityResult) -> Unit) {
    val done = { places: List<android.location.Address> ->
        onCity(CityResult(places.firstOrNull()?.locality?.takeIf { it.isNotBlank() } ?: fallback, latitude, longitude))
    }
    if (!Geocoder.isPresent()) return done(emptyList())
    val geocoder = Geocoder(this, Locale.getDefault())
    if (Build.VERSION.SDK_INT >= 33) {
        geocoder.getFromLocation(latitude, longitude, 1, object : Geocoder.GeocodeListener {
            override fun onGeocode(addresses: MutableList<android.location.Address>) = mainExecutor.execute { done(addresses) }
            override fun onError(errorMessage: String?) = mainExecutor.execute { done(emptyList()) }
        })
    } else thread(name = "geocoder") {
        // До API 33 виклик синхронний і ходить у мережу: не на головному.
        @Suppress("DEPRECATION")
        val found = runCatching { geocoder.getFromLocation(latitude, longitude, 1) }.getOrNull().orEmpty()
        mainExecutor.execute { done(found) }
    }
}

/** Грубе положення без підписки: останнього відомого досить, свіже просимо лише коли його нема. */
@SuppressLint("MissingPermission")
internal fun Context.lastKnownPosition(onFound: (Double, Double) -> Unit, onUnavailable: () -> Unit) {
    val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
    val known = manager.getProviders(true)
        .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
        .maxByOrNull { it.time }
    if (known != null) {
        onFound(known.latitude, known.longitude)
        return
    }
    // Лише мережевий провайдер: GPS з одним COARSE на Android 11 кидає SecurityException.
    val provider = LocationManager.NETWORK_PROVIDER
    val asked = Build.VERSION.SDK_INT >= 30 && manager.isProviderEnabled(provider) && runCatching {
        manager.getCurrentLocation(provider, null, mainExecutor) { fresh ->
            if (fresh != null) onFound(fresh.latitude, fresh.longitude) else onUnavailable()
        }
    }.isSuccess
    if (!asked) onUnavailable()
}

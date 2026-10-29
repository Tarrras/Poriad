@file:OptIn(KoinExperimentalAPI::class)

package app.poruch.android.navigation

import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.togetherWith
import androidx.navigation3.scene.Scene
import androidx.navigation3.ui.NavDisplay
import app.poruch.android.feature.*
import app.poruch.android.ui.ContentColumn
import app.poruch.android.ui.Unfold
import org.koin.androidx.scope.dsl.activityRetainedScope
import org.koin.core.annotation.KoinExperimentalAPI
import org.koin.dsl.module
import org.koin.dsl.navigation3.navigation

/**
 * Деталі, що виросли з квитка (Morph.kt): поки квиток накриває екран, екран під ним і деталі міняються миттєво. Інші
 * шляхи до деталей (пуш, рядок-посилання) — звичайний перехід `NavDisplay` (null). Стоїть над модулем: верхні `val`
 * файлу ініціалізуються по порядку, а `module { }` читає це одразу.
 */
private val DetailMorphTransitions: Map<String, Any> = run {
    fun Scene<*>.covered() = (entries.lastOrNull()?.contentKey?.toString()?.substringAfter("eventId=")?.substringBefore(')'))?.let(Unfold::covers) == true
    NavDisplay.transitionSpec { if (targetState.covered()) EnterTransition.None togetherWith ExitTransition.None else null } +
        NavDisplay.popTransitionSpec { if (initialState.covered()) EnterTransition.None togetherWith ExitTransition.None else null }
}

/** Записи стека в retained-скоупі Activity: `get()` дає той самий [Navigator], що й у `NavDisplay`. */
val navigationModule = module {
    activityRetainedScope {
        scoped { Navigator(get()) }
        // На широкому вікні кожен екран — колонка по центру ([ContentColumn]); мапа — на весь екран.
        navigation<Home> { ContentColumn { HomeRoute(get()) } }
        navigation<Explore> { route -> ExploreRoute(route.focusId, get()) }
        navigation<Mine> { ContentColumn { MyEventsRoute(get()) } }
        navigation<Profile> { ContentColumn { ProfileRoute(get()) } }
        navigation<Detail>(metadata = DetailMorphTransitions) { route -> ContentColumn { DetailRoute(route, get()) } }
        navigation<Editor> { route -> ContentColumn { EditorRoute(route, get()) } }
        navigation<Chat> { route -> ContentColumn { ChatRoute(route, get()) } }
        navigation<ArtistPage> { route -> ContentColumn { ArtistRoute(route, get()) } }
        navigation<Follows> { ContentColumn { FollowsRoute(get()) } }
        navigation<MyPlaces> { ContentColumn { MyPlacesRoute(get()) } }
        navigation<Auth> { route -> ContentColumn { AuthRoute(route, get()) } }
        navigation<NewPassword> { ContentColumn { NewPasswordRoute(get()) } }
    }
}

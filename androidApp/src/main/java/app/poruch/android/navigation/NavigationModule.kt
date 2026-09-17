@file:OptIn(KoinExperimentalAPI::class)

package app.poruch.android.navigation

import app.poruch.android.feature.*
import org.koin.androidx.scope.dsl.activityRetainedScope
import org.koin.core.annotation.KoinExperimentalAPI
import org.koin.dsl.module
import org.koin.dsl.navigation3.navigation

/** Записи стека в retained-скоупі Activity: `get()` дає той самий [Navigator], що й у `NavDisplay`. */
val navigationModule = module {
    activityRetainedScope {
        scoped { Navigator(get()) }
        navigation<Home> { HomeRoute(get()) }
        navigation<Explore> { route -> ExploreRoute(route.focusId, get()) }
        navigation<Mine> { MyEventsRoute(get()) }
        navigation<Profile> { ProfileRoute(get()) }
        navigation<Detail> { route -> DetailRoute(route, get()) }
        navigation<Editor> { route -> EditorRoute(route, get()) }
        navigation<Chat> { route -> ChatRoute(route, get()) }
        navigation<Auth> { AuthRoute(get()) }
        navigation<NewPassword> { NewPasswordRoute(get()) }
    }
}

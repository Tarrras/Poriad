@file:OptIn(KoinExperimentalAPI::class)

package app.poruch.android.navigation

import app.poruch.android.feature.*
import app.poruch.android.ui.ContentColumn
import org.koin.androidx.scope.dsl.activityRetainedScope
import org.koin.core.annotation.KoinExperimentalAPI
import org.koin.dsl.module
import org.koin.dsl.navigation3.navigation

/** Записи стека в retained-скоупі Activity: `get()` дає той самий [Navigator], що й у `NavDisplay`. */
val navigationModule = module {
    activityRetainedScope {
        scoped { Navigator(get()) }
        // На широкому вікні кожен екран — колонка по центру ([ContentColumn]); мапа — на весь екран.
        navigation<Home> { ContentColumn { HomeRoute(get()) } }
        navigation<Explore> { route -> ExploreRoute(route.focusId, get()) }
        navigation<Mine> { ContentColumn { MyEventsRoute(get()) } }
        navigation<Profile> { ContentColumn { ProfileRoute(get()) } }
        navigation<Detail> { route -> ContentColumn { DetailRoute(route, get()) } }
        navigation<Editor> { route -> ContentColumn { EditorRoute(route, get()) } }
        navigation<Chat> { route -> ContentColumn { ChatRoute(route, get()) } }
        navigation<ArtistPage> { route -> ContentColumn { ArtistRoute(route, get()) } }
        navigation<Follows> { ContentColumn { FollowsRoute(get()) } }
        navigation<Auth> { route -> ContentColumn { AuthRoute(route, get()) } }
        navigation<NewPassword> { ContentColumn { NewPasswordRoute(get()) } }
    }
}

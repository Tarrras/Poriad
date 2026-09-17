package app.poruch.android.di

import app.poruch.android.BuildConfig
import app.poruch.android.SessionStore
import app.poruch.android.feature.account.AuthViewModel
import app.poruch.android.feature.account.ProfileViewModel
import app.poruch.android.feature.detail.DetailViewModel
import app.poruch.android.feature.editor.DraftStore
import app.poruch.android.feature.editor.EditorViewModel
import app.poruch.android.feature.explore.ExploreViewModel
import app.poruch.android.feature.home.HomeViewModel
import app.poruch.android.feature.mine.MyEventsViewModel
import app.poruch.android.feature.onboarding.OnboardingViewModel
import app.poruch.android.feature.chat.ChatViewModel
import app.poruch.android.navigation.Chat
import app.poruch.android.navigation.Detail
import app.poruch.android.navigation.Editor
import app.poruch.android.platform.AlarmReminderScheduler
import app.poruch.android.platform.ChatNotificationCenter
import app.poruch.android.platform.NotificationPermission
import app.poruch.android.platform.RequestNotificationCenter
import app.poruch.domain.PoruchLog
import app.poruch.shared.AppConfig
import app.poruch.shared.AppGraph
import app.poruch.shared.PoruchApp
import org.koin.android.ext.koin.androidContext
import org.koin.core.module.dsl.viewModel
import org.koin.core.module.dsl.viewModelOf
import org.koin.dsl.module
import org.koin.dsl.onClose

/**
 * Android-контейнер бачить із [AppGraph] лише [PoruchApp]. Моделі з параметрами беруть сам
 * маршрут, а не його поля, щоб nullable id не проходив через `parametersOf(null)`.
 */
val appModule = module {
    single {
        PoruchLog.i("app") { "graph created" }
        AppGraph(
            AppConfig(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_KEY), SessionStore(androidContext()),
            AlarmReminderScheduler(androidContext()), RequestNotificationCenter(androidContext()),
            ChatNotificationCenter(androidContext())
        )
    } onClose { it?.close() }
    single { get<AppGraph>().app }
    single { DraftStore(androidContext()) }
    single { NotificationPermission(androidContext()) }

    viewModelOf(::HomeViewModel)
    viewModelOf(::ExploreViewModel)
    viewModelOf(::MyEventsViewModel)
    viewModelOf(::ProfileViewModel)
    viewModelOf(::OnboardingViewModel)
    viewModelOf(::AuthViewModel)
    viewModel { (route: Detail) -> DetailViewModel(get(), get(), route.eventId) }
    viewModel { (route: Editor) -> EditorViewModel(get(), get(), route.editingId) }
    viewModel { (route: Chat) -> ChatViewModel(get(), route.eventId) }
}

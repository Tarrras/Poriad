package app.poruch.android

import android.app.Application
import android.os.Bundle
import app.poruch.android.di.appModule
import app.poruch.android.navigation.navigationModule
import app.poruch.android.platform.Push
import app.poruch.android.feature.editor.DraftStore
import app.poruch.shared.PoruchApp
import app.poruch.domain.PoruchAnalytics
import app.poruch.domain.PoruchLog
import com.google.firebase.analytics.FirebaseAnalytics
import app.poruch.shared.PlatformSetup
import org.koin.android.ext.android.get
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin
import org.koin.core.logger.Level

/** Запускає Koin на весь процес: граф `shared`, моделі екранів і записи стека навігації. */
class PoruchApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Лог лише в debug-збірці.
        PoruchLog.enabled = BuildConfig.DEBUG
        PlatformSetup.initialize(this)
        // Продуктові події → Firebase. Dev-збірка шле у свій Firebase-проєкт, прод не засмічує.
        val firebase = FirebaseAnalytics.getInstance(this)
        PoruchAnalytics.sink = { name, params ->
            firebase.logEvent(name, Bundle().apply { params.forEach { (key, value) -> putString(key, value) } })
        }
        startKoin {
            androidLogger(if (BuildConfig.DEBUG) Level.INFO else Level.NONE)
            androidContext(this@PoruchApplication)
            modules(appModule, navigationModule)
        }
        // Пуші: токен їде в стор і реєструється, щойно є акаунт.
        Push.start(this, get())
        // Чернетка події належить людині, а не телефону: після виходу наступний акаунт її не бачить.
        // Нагадування чистить ReminderSync сам, бо план для гостя порожній.
        val app: PoruchApp = get(); val drafts: DraftStore = get()
        var lastUser: String? = app.state.value.userId
        app.observe { state ->
            if (lastUser != null && state.userId == null) drafts.clear()
            lastUser = state.userId
        }
    }
}

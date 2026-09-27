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
import app.poruch.domain.summary
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.crashlytics.FirebaseCrashlytics
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
        // Збої бізнес-логіки → Crashlytics non-fatal, з кроками перед ними. Перемикач «Аналітика» вимикає і це.
        val crashlytics = FirebaseCrashlytics.getInstance()
        PoruchLog.breadcrumbs = crashlytics::log
        PoruchLog.reporter = { issue, error -> crashlytics.recordException(NonFatal(issue, error)) }
        startKoin {
            androidLogger(if (BuildConfig.DEBUG) Level.INFO else Level.NONE)
            androidContext(this@PoruchApplication)
            modules(appModule, navigationModule)
        }
        val app: PoruchApp = get(); val drafts: DraftStore = get()
        // Перемикач збору — після створення стора: хук одразу отримує збережений вибір людини, без
        // проміжного «увімкнено». Firebase сам пам'ятає його між запусками.
        PoruchAnalytics.collection = { enabled ->
            firebase.setAnalyticsCollectionEnabled(enabled)
            crashlytics.setCrashlyticsCollectionEnabled(enabled)
        }
        // Пуші: токен їде в стор і реєструється, щойно є акаунт.
        Push.start(this, app)
        // Чернетка події належить людині, а не телефону: після виходу наступний акаунт її не бачить.
        // Нагадування чистить ReminderSync сам, бо план для гостя порожній.
        var lastUser: String? = app.state.value.session.userId
        app.observe { state ->
            if (lastUser != null && state.session.userId == null) drafts.clear()
            lastUser = state.session.userId
        }
    }
}

/**
 * Non-fatal без `message` чужого винятку (там бувають URL з id і шматки JSON): назва проблеми й
 * безпечний підсумок. Стек — від самого винятку, щоб Crashlytics групував за місцем. Без винятку —
 * один кадр із назвою проблеми: інакше всі відмови сервера злиплися б в одну задачу на ApiClient.
 */
private class NonFatal(issue: String, error: Throwable?) : Exception(error?.let { "$issue · ${it.summary()}" } ?: issue) {
    init { stackTrace = error?.stackTrace ?: arrayOf(StackTraceElement("app.poruch.issue", issue, null, -1)) }
}

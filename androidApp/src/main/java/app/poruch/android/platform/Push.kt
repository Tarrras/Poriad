package app.poruch.android.platform

import android.app.ActivityManager
import android.content.Context
import app.poruch.domain.ChatAlert
import app.poruch.domain.PoruchLog
import app.poruch.domain.PushPlatform
import app.poruch.domain.RequestAlert
import app.poruch.shared.PoruchApp
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.koin.android.ext.android.inject

/**
 * Пуші через FCM. Firebase ініціалізує плагін google-services із `androidApp/google-services.json`
 * ще до `Application.onCreate`; тут лише беремо токен.
 */
object Push {
    /** Віддає поточний токен у стор. Кличеться зі старту процесу. */
    fun start(context: Context, app: PoruchApp) {
        if (FirebaseApp.getApps(context).isEmpty()) { PoruchLog.i("push") { "firebase not configured; local alerts only" }; return }
        FirebaseMessaging.getInstance().token
            .addOnSuccessListener { token -> app.pushTokenChanged(token, PushPlatform.ANDROID) }
            .addOnFailureListener { PoruchLog.w("push") { "token failed: ${it.message}" } }
    }
}

/**
 * Приймає токен і повідомлення. Сервер шле лише дані, тож сповіщення малюємо самі тим самим
 * каналом, що й локальні: одна поведінка й один вигляд незалежно від того, звідки дзвінок.
 */
class PushService : FirebaseMessagingService() {
    private val app: PoruchApp by inject()

    override fun onNewToken(token: String) {
        app.pushTokenChanged(token, PushPlatform.ANDROID)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val kind = data["kind"] ?: return
        val eventId = data["eventId"] ?: return
        val title = data["title"].orEmpty()
        val body = data["body"].orEmpty()
        when (kind) {
            // Цей чат зараз на екрані: повідомлення й так видно, дзвонити нема про що.
            "chat" -> if (!(foreground() && app.state.value.chat?.eventId == eventId)) {
                val (author, text) = body.split(": ", limit = 2).let { if (it.size == 2) it[0] to it[1] else "" to body }
                ChatNotificationCenter(this).notifyMessages(listOf(ChatAlert(eventId, title, 1, author, text)))
            }
            "request" -> RequestNotificationCenter(this).notify(listOf(RequestAlert(eventId, title, 1)))
            "joined" -> RequestNotificationCenter(this).notifyJoined(eventId, title, body)
        }
        app.pushReceived(kind, data["key"].orEmpty())
    }

    private fun foreground() = ActivityManager.RunningAppProcessInfo().also(ActivityManager::getMyMemoryState)
        .importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
}

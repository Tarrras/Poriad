package app.poruch.android.platform

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import app.poruch.android.MainActivity
import app.poruch.android.R
import app.poruch.domain.EventReminder
import app.poruch.domain.ReminderScheduler
import app.poruch.domain.ChatAlert
import app.poruch.domain.ChatNotifier
import app.poruch.domain.RequestAlert
import app.poruch.domain.RequestNotifier
import app.poruch.domain.WeekendDigest
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * Сповіщення малюють сервіс і приймач, чий контекст живе локаллю системи: відмінки ("2 нових")
 * мають іти за правилами мови застосунку, як в Activity.
 */
internal fun Context.inAppLanguage(): Context =
    createConfigurationContext(Configuration(resources.configuration).apply { setLocale(Locale.forLanguageTag("uk")) })

/**
 * Дозвіл на сповіщення. До Android 13 його не існує, і питання зникає разом із ним.
 * Сам запит лишається в маршруті: він потребує Activity, а модель екрана — ні.
 */
class NotificationPermission(private val context: Context) {
    val required get() = Build.VERSION.SDK_INT >= 33
    fun granted(): Boolean =
        !required || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
}

/**
 * Нагадування через неточні будильники: навмисно без дозволу на точні. План приходить готовий
 * зі спільного шару, тут лише поставити, зняти й пережити перезавантаження: список лежить у
 * SharedPreferences, а приймач ставить його знову після `BOOT_COMPLETED`.
 */
class AlarmReminderScheduler(private val context: Context) : ReminderScheduler {
    override fun replace(reminders: List<EventReminder>) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        stored(context).forEach { alarms.cancel(pending(context, it)) }
        reminders.forEach {
            alarms.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                it.fireAtEpochMillis,
                pending(context, it)
            )
        }
        store(context, reminders)
    }

    override fun replaceDigest(digest: WeekendDigest?) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        alarms.cancel(digestPending(context))
        storeDigest(context, digest)
        if (digest != null) alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, digest.fireAtEpochMillis, digestPending(context))
    }

    internal companion object {
        private const val PREFS = "reminders"
        private const val KEY = "scheduled"
        private const val CHANNEL = "event_reminders"

        fun restore(context: Context) {
            val alarms = context.getSystemService(AlarmManager::class.java)
            stored(context).filter { it.fireAtEpochMillis > System.currentTimeMillis() }
                .forEach {
                    alarms.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        it.fireAtEpochMillis,
                        pending(context, it)
                    )
                }
            storedDigest(context)?.takeIf { it.fireAtEpochMillis > System.currentTimeMillis() }?.let {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it.fireAtEpochMillis, digestPending(context))
            }
        }

        /** Будильник дайджесту спрацював: текст — з останнього збереженого плану. Тап веде на головну. */
        fun showDigest(system: Context) {
            val context = system.inAppLanguage()
            val digest = storedDigest(context) ?: return
            if (!NotificationPermission(context).granted()) return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(DIGEST_CHANNEL, context.getString(R.string.digest), NotificationManager.IMPORTANCE_DEFAULT)
            )
            val open = PendingIntent.getActivity(
                context, DIGEST_ID, MainActivity.openDigest(context),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val count = context.resources.getQuantityString(R.plurals.digest_count, digest.count, digest.count)
            val titles = digest.titles.joinToString(", ")
            val more = digest.count - digest.titles.size
            val notification = Notification.Builder(context, DIGEST_CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(R.string.digest_title, digest.city ?: context.getString(R.string.digest_nearby), count))
                .setContentText(if (more > 0) context.getString(R.string.digest_more, titles, more) else titles)
                .setContentIntent(open).setAutoCancel(true).build()
            manager.notify(DIGEST_TAG, DIGEST_ID, notification)
        }

        private fun digestPending(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context, DIGEST_ID,
                Intent(context, ReminderReceiver::class.java).setAction(DIGEST_ACTION),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

        private fun storedDigest(context: Context): WeekendDigest? {
            val json = prefs(context).getString(DIGEST_KEY, null) ?: return null
            return runCatching {
                val it = JSONObject(json)
                val titles = it.getJSONArray("titles")
                WeekendDigest(
                    if (it.isNull("city")) null else it.getString("city"), it.getInt("count"),
                    (0 until titles.length()).map(titles::getString), it.getLong("time")
                )
            }.getOrNull()
        }

        private fun storeDigest(context: Context, digest: WeekendDigest?) {
            val json = digest?.let {
                JSONObject().put("city", it.city ?: JSONObject.NULL).put("count", it.count)
                    .put("titles", JSONArray(it.titles)).put("time", it.fireAtEpochMillis).toString()
            }
            prefs(context).edit().putString(DIGEST_KEY, json).apply()
        }

        fun show(system: Context, reminder: EventReminder) {
            val context = system.inAppLanguage()
            if (!NotificationPermission(context).granted()) return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    context.getString(R.string.reminders),
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
            val open = PendingIntent.getActivity(
                context, reminder.eventId.hashCode(),
                MainActivity.open(context, reminder.eventId, reason = "reminder"),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notification = Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(reminder.title)
                .setContentText(context.getString(R.string.reminder_body, reminder.address))
                .setContentIntent(open).setAutoCancel(true).build()
            manager.notify(reminder.eventId.hashCode(), notification)
        }

        /** Той самий intent для постановки і зняття: AlarmManager порівнює їх за дією і додатковими даними не дивиться. */
        private fun pending(context: Context, reminder: EventReminder): PendingIntent =
            PendingIntent.getBroadcast(
                context, reminder.eventId.hashCode(),
                Intent(
                    context,
                    ReminderReceiver::class.java
                ).setAction("app.poruch.REMIND.${reminder.eventId}")
                    .putExtra(EXTRA_ID, reminder.eventId).putExtra(EXTRA_TITLE, reminder.title)
                    .putExtra(EXTRA_ADDRESS, reminder.address),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        private fun stored(context: Context): List<EventReminder> {
            val array = runCatching { JSONArray(prefs(context).getString(KEY, "[]")) }.getOrDefault(
                JSONArray()
            )
            return (0 until array.length()).map { array.getJSONObject(it) }.map {
                EventReminder(
                    it.getString("id"),
                    it.getString("title"),
                    it.optString("address"),
                    it.getLong("time")
                )
            }
        }

        private fun store(context: Context, reminders: List<EventReminder>) {
            val array = JSONArray()
            reminders.forEach {
                array.put(
                    JSONObject().put("id", it.eventId).put("title", it.title)
                        .put("address", it.address).put("time", it.fireAtEpochMillis)
                )
            }
            prefs(context).edit().putString(KEY, array.toString()).apply()
        }

        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_ADDRESS = "address"
        const val DIGEST_ACTION = "app.poruch.DIGEST"
        private const val DIGEST_KEY = "digest"
        private const val DIGEST_CHANNEL = "weekend_digest"
        private const val DIGEST_TAG = "digest"
        private const val DIGEST_ID = 1
    }
}

/**
 * Сповіщення про нові запити на участь. Негайне, без будильника: план тут не потрібен, бо
 * «нове» вже вирішив спільний шар. Одне сповіщення на подію, тап веде на неї.
 */
class RequestNotificationCenter(context: Context) : RequestNotifier {
    private val context = context.inAppLanguage()

    override fun notify(alerts: List<RequestAlert>) = alerts.forEach { alert ->
        post(
            TAG, alert.eventId, alert.eventTitle,
            context.resources.getQuantityString(R.plurals.request_notification_body, alert.count, alert.count),
            reason = "request"
        )
    }

    /** Хтось приєднався до відкритої події: той самий канал і тап на подію, свій простір id. */
    fun notifyJoined(eventId: String, eventTitle: String, text: String) = post(JOINED_TAG, eventId, eventTitle, text, reason = "joined")

    /**
     * Подію скасовано чи перенесено — учасникам. Свій канал з високою важливістю: скасування за годину
     * до початку має спливти, а не лежати в шторці. Одне на подію: новіша зміна замінює попередню.
     * [reason] — `moved` чи `cancelled`, для метрики відкриттів.
     */
    fun notifyEventChange(eventId: String, eventTitle: String, text: String, reason: String) =
        post(CHANGE_TAG, eventId, eventTitle, text, CHANGE_CHANNEL, R.string.event_change_notification_channel, NotificationManager.IMPORTANCE_HIGH, reason)

    /**
     * Нова подія організатора, закладу чи артиста, за якими стежить людина ([reason] — `organizer`, `place` чи
     * `artist`, він же тип пуша). З [eventId] тап веде на подію; без нього (кілька нових подій) — на стос закладу
     * на мапі чи на екран артиста. Одне сповіщення на заклад чи артиста: новіше заміняє попереднє.
     */
    fun notifyFollowed(reason: String, eventId: String?, placeId: String?, title: String, text: String, artistId: String? = null) {
        val key = eventId ?: placeId ?: artistId ?: return
        val open = when {
            eventId != null -> MainActivity.open(context, eventId, reason = reason)
            placeId != null -> MainActivity.openPlace(context, placeId, reason)
            else -> MainActivity.openArtist(context, artistId ?: return, reason)
        }
        post(FOLLOW_TAG, key, title, text, FOLLOW_CHANNEL, R.string.follow_notification_channel, NotificationManager.IMPORTANCE_DEFAULT, reason, open)
    }

    private fun post(
        tag: String, eventId: String, title: String, text: String, channel: String = CHANNEL,
        channelName: Int = R.string.request_notification_channel, importance: Int = NotificationManager.IMPORTANCE_DEFAULT,
        reason: String? = null, target: Intent = MainActivity.open(context, eventId, reason = reason)
    ) {
        if (!NotificationPermission(context).granted()) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(channel, context.getString(channelName), importance))
        // Свій requestCode на кожен вид: extras PendingIntent не порівнює, і тап по старому сповіщенню
        // про ту саму подію інакше ніс би причину нового.
        val open = PendingIntent.getActivity(
            context, (tag + eventId).hashCode(), target,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open).setAutoCancel(true).build()
        // Інший простір id, ніж у нагадувань: запит і нагадування про ту саму подію — два сповіщення.
        manager.notify(tag, eventId.hashCode(), notification)
    }

    private companion object {
        const val CHANNEL = "join_requests"
        const val TAG = "request"
        const val JOINED_TAG = "joined"
        const val CHANGE_CHANNEL = "event_changes"
        const val CHANGE_TAG = "change"
        const val FOLLOW_CHANNEL = "follows"
        const val FOLLOW_TAG = "follow"
    }
}

/** Сповіщення про нові повідомлення в чаті: одне на подію, з іменем і початком останнього. Тап веде в чат. */
class ChatNotificationCenter(context: Context) : ChatNotifier {
    private val context = context.inAppLanguage()

    override fun notifyMessages(alerts: List<ChatAlert>) {
        if (!NotificationPermission(context).granted()) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                context.getString(R.string.chat_notification_channel),
                NotificationManager.IMPORTANCE_DEFAULT
            )
        )
        alerts.forEach { alert ->
            // Свій requestCode: інакше PendingIntent збігся б із запитом і нагадуванням про ту саму
            // подію (extras не розрізняють), і їхні тапи теж вели б у чат.
            val open = PendingIntent.getActivity(
                context, (TAG + alert.eventId).hashCode(),
                MainActivity.open(context, alert.eventId, chat = true, reason = "chat"),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val preview = context.getString(
                R.string.chat_preview,
                alert.authorName.ifBlank { context.getString(R.string.chat_member) },
                alert.preview
            )
            val notification = Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(alert.eventTitle)
                .setContentText(preview)
                .setSubText(
                    context.resources.getQuantityString(
                        R.plurals.chat_unread_count,
                        alert.count,
                        alert.count
                    )
                )
                .setContentIntent(open).setAutoCancel(true).build()
            // Свій простір id: чат, запит і нагадування про ту саму подію — три сповіщення.
            manager.notify(TAG, alert.eventId.hashCode(), notification)
        }
    }

    private companion object {
        const val CHANNEL = "chat_messages"
        const val TAG = "chat"
    }
}

/** Будильник спрацював або телефон перезавантажився. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            AlarmReminderScheduler.restore(context)
            return
        }
        if (intent.action == AlarmReminderScheduler.DIGEST_ACTION) return AlarmReminderScheduler.showDigest(context)
        val id = intent.getStringExtra(AlarmReminderScheduler.EXTRA_ID) ?: return
        AlarmReminderScheduler.show(
            context,
            EventReminder(
                id,
                intent.getStringExtra(AlarmReminderScheduler.EXTRA_TITLE).orEmpty(),
                intent.getStringExtra(AlarmReminderScheduler.EXTRA_ADDRESS).orEmpty(),
                0
            )
        )
    }
}

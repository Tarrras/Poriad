package app.poruch.android

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.ui.Poruch
import app.poruch.shared.AppState
import app.poruch.shared.PoruchApp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.koin.compose.koinInject
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/** Неточні локальні будильники: навмисно без дозволу на точні. */
object Reminders {
    private const val CHANNEL = "event_reminders"
    private fun prefs(context: Context) = context.getSharedPreferences("reminders", Context.MODE_PRIVATE)
    fun enabled(context: Context) = prefs(context).getBoolean("enabled", false)
    fun setEnabled(context: Context, enabled: Boolean) { prefs(context).edit().putBoolean("enabled", enabled).apply(); if (!enabled) clear(context) }
    private fun pending(context: Context, id: String, title: String): PendingIntent = PendingIntent.getBroadcast(context, id.hashCode(), Intent(context, ReminderReceiver::class.java).setAction("app.poruch.REMIND.$id").putExtra("title", title).putExtra("id", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun clear(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val old = runCatching { JSONArray(prefs(context).getString("scheduled", "[]")) }.getOrDefault(JSONArray())
        for (i in 0 until old.length()) alarms.cancel(pending(context, old.getJSONObject(i).getString("id"), ""))
        prefs(context).edit().putString("scheduled", "[]").apply()
    }
    fun sync(context: Context, state: AppState) {
        clear(context)
        if (state.userId == null || !enabled(context)) return
        val alarms = context.getSystemService(AlarmManager::class.java)
        val scheduled = JSONArray()
        state.myEvents.filter { it.gathering?.joined == true && it.isPublished }.forEach { event ->
            val trigger = runCatching { Instant.parse(event.startsAt).toEpochMilli() - 60 * 60 * 1000 }.getOrNull() ?: return@forEach
            if (trigger > System.currentTimeMillis()) {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending(context, event.id, event.title))
                scheduled.put(JSONObject().put("id", event.id).put("title", event.title).put("time", trigger))
            }
        }
        prefs(context).edit().putString("scheduled", scheduled.toString()).apply()
    }
    fun restore(context: Context) {
        if (!enabled(context)) return
        val saved = runCatching { JSONArray(prefs(context).getString("scheduled", "[]")) }.getOrDefault(JSONArray())
        for (i in 0 until saved.length()) {
            val item = saved.getJSONObject(i)
            if (item.getLong("time") > System.currentTimeMillis()) context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.getLong("time"), pending(context, item.getString("id"), item.getString("title")))
        }
    }
    fun notify(context: Context, id: String, title: String) {
        if (!enabled(context) || (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.reminders), NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(context, id.hashCode(), Intent(context, MainActivity::class.java).putExtra("eventId", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(id.hashCode(), Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_notification).setContentTitle(title).setContentText(context.getString(R.string.reminder_body)).setContentIntent(open).setAutoCancel(true).build())
    }
}
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { if (intent.action == Intent.ACTION_BOOT_COMPLETED) Reminders.restore(context) else Reminders.notify(context, intent.getStringExtra("id").orEmpty(), intent.getStringExtra("title").orEmpty()) }
}
/** Перемикач нагадувань. Сам читає плани зі стору, щоб налаштування не тягли стан подій. */
@Composable fun ReminderPreference() {
    val context = LocalContext.current
    val state = koinInject<PoruchApp>().state.collectAsStateWithLifecycle().value
    var enabled by remember { mutableStateOf(Reminders.enabled(context)) }
    var denied by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> enabled = granted; denied = !granted; Reminders.setEnabled(context, granted); Reminders.sync(context, state) }
    val colors = Poruch.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(stringResource(R.string.reminders), Modifier.weight(1f).padding(end = 12.dp), style = MaterialTheme.typography.bodyLarge, color = colors.ink)
        Switch(enabled, { requested ->
            if (requested && Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            else { enabled = requested; Reminders.setEnabled(context, requested); Reminders.sync(context, state) }
        }, colors = SwitchDefaults.colors(checkedTrackColor = colors.brand, checkedThumbColor = colors.onBrand))
    }
    Text(
        stringResource(if (denied) R.string.reminder_permission else R.string.reminder_note),
        style = MaterialTheme.typography.bodySmall, color = if (denied) colors.danger else colors.inkTertiary
    )
}

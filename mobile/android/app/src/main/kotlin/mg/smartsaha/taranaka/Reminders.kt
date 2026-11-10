package mg.smartsaha.taranaka

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Local reminders (vaccines 7 days before, the day before, when late), with
 * no network and no extra library: AlarmManager + a notification.
 *
 * Reminders come by group (one per profile): scheduling a group replaces its
 * previous reminders. They are kept in the app's private preferences so they
 * can be set again after a restart of the phone. Only the text to show is
 * kept (no health data beyond it); the lock screen shows a neutral text.
 */
object Reminders {
    private const val PREFS = "taranaka_reminders"
    private const val CHANNEL = "rappels"
    const val EXTRA_ID = "id"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"

    // Texts in the app language (the phone may be in another one).
    private const val KEY_CHANNEL = "__channel_name"
    private const val KEY_PUBLIC = "__public_text"

    fun schedule(
        context: Context,
        group: String,
        items: List<Map<String, Any?>>,
        channelName: String,
        publicText: String,
    ) {
        cancelGroup(context, group)
        prefs(context).edit().putString(KEY_CHANNEL, channelName).putString(KEY_PUBLIC, publicText).apply()
        val now = System.currentTimeMillis()
        val kept = JSONArray()
        for (item in items) {
            val id = (item["id"] as? Number)?.toInt() ?: continue
            val at = (item["at"] as? Number)?.toLong() ?: continue
            if (at <= now) continue
            val json = JSONObject()
                .put("id", id)
                .put("at", at)
                .put("title", item["title"] as? String ?: "")
                .put("body", item["body"] as? String ?: "")
            kept.put(json)
            setAlarm(context, json)
        }
        prefs(context).edit().putString(group, kept.toString()).apply()
    }

    fun cancelGroup(context: Context, group: String) {
        val saved = prefs(context).getString(group, null) ?: return
        val array = JSONArray(saved)
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (i in 0 until array.length()) {
            alarms.cancel(pendingAlarm(context, array.getJSONObject(i)))
        }
        prefs(context).edit().remove(group).apply()
    }

    /** After a restart of the phone: the alarms are set again. */
    fun restoreAll(context: Context) {
        val now = System.currentTimeMillis()
        for ((key, value) in prefs(context).all) {
            if (key.startsWith("__")) continue
            val array = JSONArray(value as? String ?: continue)
            for (i in 0 until array.length()) {
                val json = array.getJSONObject(i)
                if (json.getLong("at") > now) setAlarm(context, json)
            }
        }
    }

    fun show(context: Context, id: Int, title: String, body: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    prefs(context).getString(KEY_CHANNEL, null) ?: context.getString(R.string.app_name),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val tap = PendingIntent.getActivity(
            context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // On the lock screen: no name nor vaccine, only that a reminder waits.
        val public = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText(prefs(context).getString(KEY_PUBLIC, null) ?: "")
            .build()
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (e: SecurityException) {
            // Notifications not allowed: the reminder also shows in the app.
        }
    }

    private fun setAlarm(context: Context, json: JSONObject) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // Inexact but kept in Doze: no "exact alarm" permission needed.
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, json.getLong("at"), pendingAlarm(context, json))
    }

    private fun pendingAlarm(context: Context, json: JSONObject): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra(EXTRA_ID, json.getInt("id"))
            .putExtra(EXTRA_TITLE, json.optString("title"))
            .putExtra(EXTRA_BODY, json.optString("body"))
        return PendingIntent.getBroadcast(
            context, json.getInt("id"), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/** Shows a reminder when its alarm goes off; sets the alarms again after a restart. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> Reminders.restoreAll(context)
            else -> Reminders.show(
                context,
                intent.getIntExtra(Reminders.EXTRA_ID, 0),
                intent.getStringExtra(Reminders.EXTRA_TITLE) ?: "",
                intent.getStringExtra(Reminders.EXTRA_BODY) ?: "",
            )
        }
    }
}

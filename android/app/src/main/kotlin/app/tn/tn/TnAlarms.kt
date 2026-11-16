package app.tn.tn

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native cancel of a TN alarm scheduled by flutter_local_notifications.
 *
 * The home-screen widget completes tasks without the Dart side running, so
 * the deadline alarm of a just-checked task used to ring anyway. This mirrors
 * the plugin's own cancelNotification(): same PendingIntent (receiver class +
 * request code = notification id), drop the shown notification, and remove
 * the entry from the plugin's reboot cache so it is not re-armed on boot.
 */
object TnAlarms {

    /** Same as models.dart stableHash (31-bit FNV-1a over UTF-16 units). */
    fun stableHash(s: String): Int {
        var h = 0x811C9DC5L
        for (c in s) {
            h = h xor c.code.toLong()
            h = (h * 0x01000193L) and 0x7FFFFFFFL
        }
        return if (h == 0L) 1 else h.toInt()
    }

    fun cancelForEntry(context: Context, entryId: String) {
        val id = stableHash(entryId)
        try {
            val intent = Intent(
                context,
                com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver::class.java
            )
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
            val pi = PendingIntent.getBroadcast(context, id, intent, flags)
            (context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager)?.cancel(pi)
            pi.cancel()
        } catch (_: Exception) {
        }
        try {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager)?.cancel(id)
        } catch (_: Exception) {
        }
        try {
            val prefs = context.getSharedPreferences("scheduled_notifications", Context.MODE_PRIVATE)
            val raw = prefs.getString("scheduled_notifications", null) ?: return
            val arr = JSONArray(raw)
            val kept = JSONArray()
            var removed = false
            for (i in 0 until arr.length()) {
                val n = arr.optJSONObject(i)
                if (n != null && n.optInt("id", Int.MIN_VALUE) == id) {
                    removed = true
                    continue
                }
                kept.put(arr.get(i))
            }
            if (removed) prefs.edit().putString("scheduled_notifications", kept.toString()).apply()
        } catch (_: Exception) {
        }
    }

    /** Drops a pending snooze (reminder carrying the entry id) from state JSON. */
    fun dropSnooze(data: JSONObject, entryId: String) {
        val reminders = data.optJSONArray("reminders") ?: return
        val kept = JSONArray()
        for (i in 0 until reminders.length()) {
            val r = reminders.optJSONObject(i)
            if (r != null && r.optString("id") == entryId) continue
            kept.put(reminders.get(i))
        }
        if (kept.length() != reminders.length()) data.put("reminders", kept)
    }
}

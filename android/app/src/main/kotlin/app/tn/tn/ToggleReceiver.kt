package app.tn.tn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import org.json.JSONObject
import java.util.Calendar

/**
 * Fired from the "Today's tasks" widget checkbox: toggles all items of the
 * entry in the shared state JSON, bumps the state stamp (so the Dart side
 * picks the change up on resume), plays a short ding and refreshes widgets.
 */
class ToggleReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_OPEN_CHAT -> {
                val chatId = intent.getStringExtra(EXTRA_CHAT_ID) ?: return
                val entryId = intent.getStringExtra(EXTRA_ENTRY_ID)
                val launch = Intent(context, MainActivity::class.java).apply {
                    putExtra("open_chat", chatId)
                    if (entryId != null) putExtra("open_entry", entryId)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                try { context.startActivity(launch) } catch (_: Exception) {}
                return
            }
        }
        val entryId = intent.getStringExtra(EXTRA_ENTRY_ID) ?: return
        val itemId = intent.getStringExtra(EXTRA_ITEM_ID)
        val result = goAsync()
        Thread {
            try {
                val changed = if (itemId != null) toggleItem(context, entryId, itemId)
                else toggleEntry(context, entryId)
                // Recurring task completed from the widget: roll it over when
                // its period has passed (mirrors AppModel.rolloverRecurring).
                val rolled = Recurrence.rollover(context)
                if (changed || rolled) {
                    playDing(context)
                    vibrate(context)
                    TnDayWidgetProvider.updateAll(context)
                }
            } catch (_: Exception) {
            } finally {
                result.finish()
            }
        }.start()
    }

    companion object {
        const val EXTRA_ENTRY_ID = "entry"
        const val EXTRA_ITEM_ID = "item"
        const val EXTRA_CHAT_ID = "chatId"
        const val ACTION_TOGGLE = "app.tn.tn.ACTION_TOGGLE_ENTRY"
        const val ACTION_OPEN_CHAT = "app.tn.tn.ACTION_OPEN_CHAT"

        private fun toggleEntry(context: Context, entryId: String): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return false
            val data = JSONObject(raw)
            val entries = data.optJSONArray("entries") ?: return false
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                if (e.optString("id") != entryId) continue
                val items = e.optJSONArray("items") ?: return false
                if (items.length() == 0) return false
                var allDone = true
                for (j in 0 until items.length()) {
                    if (!items.getJSONObject(j).optBoolean("done")) { allDone = false; break }
                }
                for (j in 0 until items.length()) {
                    items.getJSONObject(j).put("done", !allDone)
                }
                if (!allDone) snapCompletedRecurring(e)
                prefs.edit()
                    .putString("flutter.tn-notes-data-v1", data.toString())
                    .putLong("flutter.tn-state-stamp", System.currentTimeMillis())
                    .apply()
                return true
            }
            return false
        }

        /** Toggles a single checklist item; returns true when it became done. */
        private fun toggleItem(context: Context, entryId: String, itemId: String): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return false
            val data = JSONObject(raw)
            val entries = data.optJSONArray("entries") ?: return false
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                if (e.optString("id") != entryId) continue
                val items = e.optJSONArray("items") ?: return false
                for (j in 0 until items.length()) {
                    val item = items.getJSONObject(j)
                    if (item.optString("id") != itemId) continue
                    val currentlyDone = item.optBoolean("done")
                    // Блок: нельзя завершить родителя пока есть незавершённые подзадачи
                    if (!currentlyDone) {
                        for (k in 0 until items.length()) {
                            val child = items.getJSONObject(k)
                            if (child.optString("parentId", "") == itemId && !child.optBoolean("done")) {
                                return false
                            }
                        }
                    }
                    val nowDone = !currentlyDone
                    item.put("done", nowDone)
                    if (nowDone) snapCompletedRecurring(e)
                    prefs.edit()
                        .putString("flutter.tn-notes-data-v1", data.toString())
                        .putLong("flutter.tn-state-stamp", System.currentTimeMillis())
                        .apply()
                    return nowDone
                }
                return false
            }
            return false
        }

        /**
         * Completing an OVERDUE recurring task snaps its deadline forward so
         * the checkmark sticks until the new period ends. DAILY tasks use
         * calendar-day semantics (mirrors models.dart snapCompletedRecurring):
         * completing yesterday's leftover today snaps the deadline to TODAY,
         * same clock time — it stays checked until tonight's midnight
         * rollover, and the fresh instance is today's. Other rules snap to
         * the next occurrence after now.
         */
        private fun snapCompletedRecurring(e: JSONObject) {
            try {
                val rec = e.optString("recurrence", "")
                if (rec.isEmpty() || !e.has("dueAt")) return
                val items = e.optJSONArray("items") ?: return
                if (items.length() == 0) return
                for (j in 0 until items.length()) {
                    if (!items.getJSONObject(j).optBoolean("done")) return
                }
                val now = System.currentTimeMillis()
                if (e.getLong("dueAt") > now) return
                val daysArr: IntArray? = e.optJSONArray("recurrenceDays")?.let { arr ->
                    IntArray(arr.length()) { arr.getInt(it) }
                }
                val mDay = if (e.has("monthDay")) e.getInt("monthDay") else -1
                val next: Long = if (rec == "daily") {
                    val dueCal = Calendar.getInstance().apply { timeInMillis = e.getLong("dueAt") }
                    val hour = dueCal.get(Calendar.HOUR_OF_DAY)
                    val minute = dueCal.get(Calendar.MINUTE)
                    Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, hour)
                        set(Calendar.MINUTE, minute)
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }.timeInMillis
                } else {
                    Recurrence.nextAfter(rec, daysArr, mDay, now)
                }
                e.put("dueAt", next)
            } catch (_: Exception) {
            }
        }

        private fun playDing(context: Context) {
            try {
                val mp = MediaPlayer()
                // Route to the NOTIFICATION stream (USAGE_NOTIFICATION_EVENT +
                // SONIFICATION): the ding used to land on the MEDIA track, so
                // it ignored the notification volume and blared over music.
                mp.setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION_EVENT)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                val afd = context.resources.openRawResourceFd(R.raw.tn_ding)
                mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                mp.setOnCompletionListener { it.release() }
                mp.prepare()
                mp.start()
            } catch (_: Exception) {
            }
        }

        private fun vibrate(context: Context) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager ?: return
                    vm.defaultVibrator.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    val v = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        v.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE))
                    } else {
                        @Suppress("DEPRECATION")
                        v.vibrate(35)
                    }
                }
            } catch (_: Exception) {
            }
        }
    }
}

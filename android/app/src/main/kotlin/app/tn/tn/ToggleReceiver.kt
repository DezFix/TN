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

/**
 * Fired from the "Today's tasks" widget checkbox: toggles all items of the
 * entry in the shared state JSON, bumps the state stamp (so the Dart side
 * picks the change up on resume), plays a short ding and refreshes widgets.
 */
class ToggleReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val entryId = intent.getStringExtra(EXTRA_ENTRY_ID) ?: return
        val result = goAsync()
        Thread {
            try {
                val changed = toggleEntry(context, entryId)
                if (changed) {
                    playDing(context)
                    vibrate(context)
                    TnWidgetProvider.updateAll(context)
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
        const val ACTION_TOGGLE = "app.tn.tn.ACTION_TOGGLE_ENTRY"

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
                prefs.edit()
                    .putString("flutter.tn-notes-data-v1", data.toString())
                    .putLong("flutter.tn-state-stamp", System.currentTimeMillis())
                    .apply()
                return true
            }
            return false
        }

        private fun playDing(context: Context) {
            try {
                val mp = MediaPlayer.create(context, R.raw.tn_ding) ?: return
                mp.setOnCompletionListener { it.release() }
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

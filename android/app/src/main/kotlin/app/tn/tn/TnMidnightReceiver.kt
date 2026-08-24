package app.tn.tn

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * The day-widget shows "today" tasks, so it must roll over exactly at
 * midnight. updatePeriodMillis only fires every 30+ minutes, so we pair it
 * with a daily inexact alarm (no SCHEDULE_EXACT_ALARM grant needed).
 */
class TnMidnightReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // Midnight: recurring tasks whose period ended reset here even if the
        // app is never opened (see Recurrence.rollover).
        Recurrence.rollover(context)
        TnDayWidgetProvider.updateAll(context)
        scheduleNext(context)
    }

    companion object {
        private const val REQUEST_CODE = 4200

        fun scheduleNext(context: Context) {
            try {
                val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
                val pi = PendingIntent.getBroadcast(
                    context, REQUEST_CODE,
                    Intent(context, TnMidnightReceiver::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val cal = Calendar.getInstance().apply {
                    add(Calendar.DAY_OF_YEAR, 1)
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 2)
                    set(Calendar.MILLISECOND, 0)
                }
                am.cancel(pi)
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
            } catch (_: Exception) {
            }
        }
    }
}

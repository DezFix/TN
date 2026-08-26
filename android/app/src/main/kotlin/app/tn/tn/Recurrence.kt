package app.tn.tn

import android.content.Context
import java.util.Calendar
import org.json.JSONObject

/**
 * Native mirror of the Dart recurrence math (models.dart nextOccurrence +
 * AppModel.rolloverRecurring). The home-screen widget can complete tasks
 * without ever opening the app, so recurring resets must work headlessly:
 * once every item of a recurring entry is done and its period has passed,
 * items go back to undone and the deadline jumps forward (catching up over
 * missed periods). One entry per recurring task — no copies.
 */
object Recurrence {

    /** ISO weekday: 1=Mon..7=Sun (Calendar.DAY_OF_WEEK is Sun=1..Sat=7). */
    private fun isoWeekday(c: Calendar): Int {
        val dow = c.get(Calendar.DAY_OF_WEEK)
        return if (dow == Calendar.SUNDAY) 7 else dow - 1
    }

    /**
     * First occurrence of [recurrence] strictly after [fromMs],
     * preserving the clock time. Same semantics as models.dart.
     */
    fun nextAfter(recurrence: String, days: IntArray?, monthDay: Int, fromMs: Long): Long {
        val cur = Calendar.getInstance().apply { timeInMillis = fromMs }
        val hour = cur.get(Calendar.HOUR_OF_DAY)
        val minute = cur.get(Calendar.MINUTE)
        fun normalize(c: Calendar) {
            c.set(Calendar.HOUR_OF_DAY, hour)
            c.set(Calendar.MINUTE, minute)
            c.set(Calendar.SECOND, 0)
            c.set(Calendar.MILLISECOND, 0)
        }
        when (recurrence) {
            "monthly" -> {
                val dom = if (monthDay < 1) cur.get(Calendar.DAY_OF_MONTH) else monthDay
                do {
                    cur.add(Calendar.MONTH, 1)
                    val max = cur.getActualMaximum(Calendar.DAY_OF_MONTH)
                    cur.set(Calendar.DAY_OF_MONTH, if (dom > max) max else dom)
                } while (cur.timeInMillis <= fromMs)
            }
            "weekly" -> {
                val set = if (days == null || days.isEmpty()) intArrayOf(isoWeekday(cur)) else days
                do {
                    cur.add(Calendar.DAY_OF_YEAR, 1)
                } while (!set.contains(isoWeekday(cur)) || cur.timeInMillis <= fromMs)
            }
            else -> { // 'daily' and any unknown rule
                do {
                    cur.add(Calendar.DAY_OF_YEAR, 1)
                } while (cur.timeInMillis <= fromMs)
            }
        }
        normalize(cur)
        return cur.timeInMillis
    }

    /**
     * Resets finished recurring tasks whose period has ended.
     *
     * DAILY tasks use CALENDAR-DAY semantics: once every item is done and
     * the due date's day is strictly in the past, items reset exactly at
     * midnight (this runs from the TnMidnightReceiver alarm) and the
     * deadline jumps to today, same clock time. The old code waited for the
     * next due *instant* (e.g. 18:00), so a task checked off yesterday came
     * back only at execution time instead of at 00:00.
     *
     * Weekly/monthly keep instant semantics: reset when the next occurrence
     * time has passed.
     *
     * Returns true when the state JSON was modified.
     */
    fun rollover(context: Context): Boolean {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return false
        return try {
            val data = JSONObject(raw)
            val entries = data.optJSONArray("entries") ?: return false
            val now = System.currentTimeMillis()
            var changed = false
            for (i in 0 until entries.length()) {
                val e = entries.optJSONObject(i) ?: continue
                val rec = e.optString("recurrence", "")
                if (rec.isEmpty() || !e.has("dueAt")) continue
                val items = e.optJSONArray("items") ?: continue
                if (items.length() == 0) continue
                var allDone = true
                for (j in 0 until items.length()) {
                    if (!items.getJSONObject(j).optBoolean("done")) {
                        allDone = false
                        break
                    }
                }
                if (!allDone) continue

                val daysArr: IntArray? = e.optJSONArray("recurrenceDays")?.let { arr ->
                    IntArray(arr.length()) { arr.getInt(it) }
                }
                val mDay = if (e.has("monthDay")) e.getInt("monthDay") else -1

                val next: Long
                if (rec == "daily") {
                    val cal = Calendar.getInstance().apply { timeInMillis = e.getLong("dueAt") }
                    val dueDayStart = (cal.clone() as Calendar).apply {
                        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                    }.timeInMillis
                    val todayStart = Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                    }.timeInMillis
                    if (dueDayStart >= todayStart) continue // still today's period
                    // Fresh instance: today, same wall-clock time as before
                    // (even if that moment already passed today — the task
                    // then stays checked until tonight's rollover).
                    next = (cal.clone() as Calendar).apply {
                        set(Calendar.YEAR, calendarYearOf(todayStart))
                        set(Calendar.MONTH, calendarMonthOf(todayStart))
                        set(Calendar.DAY_OF_MONTH, calendarDayOf(todayStart))
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }.timeInMillis
                } else {
                    var candidate = nextAfter(rec, daysArr, mDay, e.getLong("dueAt"))
                    if (now < candidate) continue // still inside the current period
                    while (candidate <= now) {
                        candidate = nextAfter(rec, daysArr, mDay, candidate)
                    }
                    next = candidate
                }

                e.put("dueAt", next)
                for (j in 0 until items.length()) {
                    items.getJSONObject(j).put("done", false)
                }
                changed = true
            }
            if (!changed) return false
            prefs.edit()
                .putString("flutter.tn-notes-data-v1", data.toString())
                .putLong("flutter.tn-state-stamp", System.currentTimeMillis())
                .apply()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun calendarYearOf(dayStartMs: Long): Int =
        Calendar.getInstance().apply { timeInMillis = dayStartMs }.get(Calendar.YEAR)

    private fun calendarMonthOf(dayStartMs: Long): Int =
        Calendar.getInstance().apply { timeInMillis = dayStartMs }.get(Calendar.MONTH)

    private fun calendarDayOf(dayStartMs: Long): Int =
        Calendar.getInstance().apply { timeInMillis = dayStartMs }.get(Calendar.DAY_OF_MONTH)
}

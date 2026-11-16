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

    private fun dayStartOf(ms: Long): Long =
        Calendar.getInstance().apply {
            timeInMillis = ms
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    private fun todayStart(): Long = dayStartOf(System.currentTimeMillis())

    private fun daysOf(e: JSONObject): IntArray? =
        e.optJSONArray("recurrenceDays")?.let { arr -> IntArray(arr.length()) { arr.getInt(it) } }

    private fun monthDayOf(e: JSONObject): Int = if (e.has("monthDay")) e.optInt("monthDay", -1) else -1

    private fun allDone(e: JSONObject): Boolean {
        val items = e.optJSONArray("items") ?: return false
        if (items.length() == 0) return false
        for (j in 0 until items.length()) {
            if (!items.getJSONObject(j).optBoolean("done")) return false
        }
        return true
    }

    private fun reopen(e: JSONObject, dueAt: Long) {
        e.put("dueAt", dueAt)
        e.put("updatedAt", System.currentTimeMillis())
        // Kanban: the new occurrence starts in the first column again,
        // not stuck in "Done" (mirrors models.dart _reopen).
        e.remove("boardId")
        val items = e.optJSONArray("items") ?: return
        for (j in 0 until items.length()) items.getJSONObject(j).put("done", false)
    }

    /**
     * Mirror of models.dart currentOccurrence: today's occurrence (daily),
     * or the first one on/after today (weekly/monthly), same clock time.
     */
    fun currentOccurrence(e: JSONObject): Long {
        val rec = e.optString("recurrence", "")
        val due = e.getLong("dueAt")
        val today = todayStart()
        if (dayStartOf(due) >= today) return due
        if (rec == "daily") {
            val dueCal = Calendar.getInstance().apply { timeInMillis = due }
            return Calendar.getInstance().apply {
                timeInMillis = today
                set(Calendar.HOUR_OF_DAY, dueCal.get(Calendar.HOUR_OF_DAY))
                set(Calendar.MINUTE, dueCal.get(Calendar.MINUTE))
            }.timeInMillis
        }
        val days = daysOf(e)
        // Pin the month day for the whole catch-up (no drift to the 28th).
        val mDay = monthDayOf(e).let {
            if (it < 1) Calendar.getInstance().apply { timeInMillis = due }.get(Calendar.DAY_OF_MONTH) else it
        }
        var next = due
        var guard = 0
        while (dayStartOf(next) < today && guard++ < 5000) {
            next = nextAfter(rec, days, mDay, next)
        }
        return next
    }

    /**
     * Mirror of models.dart snapCompletedRecurring: completing an occurrence
     * of a PAST day closes only that occurrence and immediately reopens the
     * task (unchecked) for today / the next task day. Completing yesterday's
     * task must never consume today's. Returns true when reopened.
     */
    fun snapCompleted(e: JSONObject): Boolean {
        return try {
            val rec = e.optString("recurrence", "")
            if (rec.isEmpty() || !e.has("dueAt") || !allDone(e)) return false
            if (dayStartOf(e.getLong("dueAt")) >= todayStart()) return false
            reopen(e, currentOccurrence(e))
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Mirror of models.dart rolloverRecurringTasks. Every period is a
     * calendar day: a checked occurrence holds until 00:00, then the next
     * one opens unchecked (daily: today, even if its clock time passed;
     * weekly: on the next selected weekday; monthly: right after the due day).
     * Returns true when the state JSON was modified.
     */
    fun rollover(context: Context): Boolean {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return false
        return try {
            val data = JSONObject(raw)
            val trashedChats = HashSet<String>()
            data.optJSONArray("chats")?.let { chats ->
                for (i in 0 until chats.length()) {
                    val chat = chats.getJSONObject(i)
                    if (chat.has("deletedAt") && !chat.isNull("deletedAt")) {
                        trashedChats.add(chat.optString("id"))
                    }
                }
            }
            val entries = data.optJSONArray("entries") ?: return false
            val today = todayStart()
            var changed = false
            for (i in 0 until entries.length()) {
                val e = entries.optJSONObject(i) ?: continue
                if (trashedChats.contains(e.optString("chatId"))) continue
                val rec = e.optString("recurrence", "")
                if (rec.isEmpty() || !e.has("dueAt") || !allDone(e)) continue
                val due = e.getLong("dueAt")
                if (dayStartOf(due) >= today) continue // today/future: hold
                if (rec == "weekly") {
                    val first = nextAfter(rec, daysOf(e), -1, due)
                    if (dayStartOf(first) > today) continue // not a task day yet
                }
                reopen(e, currentOccurrence(e))
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
}

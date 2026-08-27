package app.tn.tn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * The single TN home-screen widget: every undone checklist item from ALL
 * chats, checkable right here. Completed items (and fully done entries)
 * are hidden. The period filter comes from prefs written by the in-app
 * widget settings screen:
 *  - all   (default): everything undone, undated items last;
 *  - today: due today or overdue;
 *  - week:  due within the next 7 days (incl. today/overdue).
 *
 * Rows are built as static child RemoteViews (addView): per-row
 * setOnClickPendingIntent is far more reliable across launchers than
 * pending-intent templates with fill-in intents.
 */
class TnDayWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = buildViews(context)
        for (id in ids) manager.updateAppWidget(id, views)
        TnMidnightReceiver.scheduleNext(context)
    }

    companion object {
        /** SharedPreferences stores Dart doubles as strings with this prefix. */
        const val PREF_DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TnDayWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = buildViews(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private data class Row(
            val entryId: String,
            val itemId: String?,
            val chatId: String,
            val title: String,
            val meta: String,
            val overdue: Boolean,
            val ts: Long,
            val priority: Int,
        )

        private fun loadRows(context: Context): List<Row> {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return emptyList()
            // Legacy values ('all', 'week') map to 'upcoming' — the "All tasks"
            // option was removed and Week was replaced by Upcoming.
            val periodRaw = prefs.getString("flutter.tn-daywidget-period", "upcoming") ?: "upcoming"
            val period = if (periodRaw == "today") "today" else "upcoming"
            val now = System.currentTimeMillis()
            val data = JSONObject(raw)
            val names = HashMap<String, String>()
            data.optJSONArray("chats")?.let { chats ->
                for (i in 0 until chats.length()) {
                    val c = chats.getJSONObject(i)
                    names[c.optString("id")] = c.optString("name", "")
                }
            }
            val entries = data.optJSONArray("entries") ?: return emptyList()
            val rows = ArrayList<Row>()
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                if (!e.isNull("scheduledAt")) continue
                if (e.optString("type", "") != "todo") continue
                val chatId = e.optString("chatId", "")
                val time0 = e.optLong("dueAt", e.optLong("ts", 0L))
                val due = e.optLong("dueAt", 0L)
                when (period) {
                    "today" -> if (due == 0L || due > endOfTodayMillis()) continue
                    // Upcoming: overdue + today + tomorrow + day after tomorrow.
                    else -> if (due == 0L || due > endOfUpcomingMillis()) continue
                }
                // Overdue = the moment has already passed (same semantics as
                // the in-app bubble), not merely "before today" — otherwise a
                // task expiring earlier TODAY stays gray in the widget.
                val overdue = due in 1 until System.currentTimeMillis()
                val items = e.optJSONArray("items") ?: continue
                for (j in 0 until items.length()) {
                    val it = items.getJSONObject(j)
                    // Completed items stay out of the widget entirely.
                    if (it.optBoolean("done")) continue
                    val text = it.optString("text", "").trim()
                    if (text.isEmpty()) continue
                    rows.add(
                        Row(
                            e.optString("id"),
                            it.optString("id"),
                            chatId,
                            text.take(90),
                            meta(context, names[chatId] ?: "", time0),
                            overdue,
                            time0,
                            it.optInt("priority", 0),
                        )
                    )
                }
            }
            // Nearest deadline first.
            rows.sortBy { it.ts }
            return rows.take(20)
        }

        private fun startOfTodayMillis(): Long {
            val cal = Calendar.getInstance()
            cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
            return cal.timeInMillis
        }

        private fun endOfTodayMillis(): Long = startOfTodayMillis() + 24 * 60 * 60 * 1000L - 1

        private fun endOfUpcomingMillis(): Long = startOfTodayMillis() + 3 * 24 * 60 * 60 * 1000L - 1

        /** Widget strings follow the IN-APP language, not the system one. */
        private data class Ws(
            val title: String, val empty: String, val overdue: String,
            val secOverdue: String, val secToday: String, val secTomorrow: String, val secLater: String
        )

        private fun widgetStrings(context: Context): Ws {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            var lang = (prefs.all["flutter.tn-widget-lang"] ?: prefs.all["tn-widget-lang"]) as? String
            if (lang.isNullOrEmpty()) lang = Locale.getDefault().language
            return when (lang.take(2).lowercase(Locale.ROOT)) {
                "ru" -> Ws("Задачи", "Пока ничего нет", "просрочено",
                    "Просрочено", "Сегодня", "Завтра", "Позже")
                "uk" -> Ws("Завдання", "Поки нічого немає", "прострочено",
                    "Прострочено", "Сьогодні", "Завтра", "Пізніше")
                "de" -> Ws("Aufgaben", "Noch nichts hier", "überfällig",
                    "Überfällig", "Heute", "Morgen", "Später")
                "es" -> Ws("Tareas", "Aún no hay nada", "vencido",
                    "Vencido", "Hoy", "Mañana", "Más tarde")
                "fr" -> Ws("Tâches", "Rien pour le moment", "en retard",
                    "En retard", "Aujourd'hui", "Demain", "Plus tard")
                else -> Ws("Tasks", "Nothing here yet", "overdue",
                    "Overdue", "Today", "Tomorrow", "Later")
            }
        }
        /** Time + optional chat name for a row's meta line. */
        private fun meta(context: Context, chatName: String, time: Long): String {
            val h = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(time))
            return if (chatName.isEmpty()) h
            else "$h · $chatName"
        }

        /** Section bucket title for a due timestamp, or null when none applies. */
        private fun sectionLabel(context: Context, ws: Ws, due: Long): String? {
            val now = System.currentTimeMillis()
            val startToday = startOfTodayMillis()
            return when {
                due != 0L && due < now -> ws.secOverdue
                due in startToday until (startToday + 24 * 60 * 60 * 1000L) -> ws.secToday
                due in (startToday + 24 * 60 * 60 * 1000L) until (startToday + 2 * 24 * 60 * 60 * 1000L) -> ws.secTomorrow
                due != 0L -> ws.secLater
                else -> null
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            val rv = RemoteViews(context.packageName, R.layout.tn_day_widget)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            // Header opens the app.
            val open = Intent(context, MainActivity::class.java)
            rv.setOnClickPendingIntent(
                R.id.dw_header,
                PendingIntent.getActivity(
                    context, 2, open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            // Gear opens the widget settings screen inside the app.
            val settings = Intent(context, MainActivity::class.java).apply {
                putExtra("open_settings", true)
            }
            rv.setOnClickPendingIntent(
                R.id.dw_settings,
                PendingIntent.getActivity(
                    context, 3, settings,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            val ws = widgetStrings(context)
            rv.setTextViewText(R.id.dw_title, ws.title)
            // Adjustable font size (scale, default 1.0) written by the in-app
            // widget settings screen.
            var fontScale = 1.0f
            try {
                var rawFont: Any? = prefs.all["flutter.tn-widget-font"]
                if (rawFont == null) rawFont = prefs.all["tn-widget-font"]
                when (rawFont) {
                    is Number -> fontScale = rawFont.toFloat()
                    is String -> fontScale = rawFont.removePrefix(PREF_DOUBLE_PREFIX).toFloatOrNull() ?: 1.0f
                }
                if (!fontScale.isFinite() || fontScale < 0.5f || fontScale > 2.0f) fontScale = 1.0f
                fontScale = fontScale.coerceIn(0.8f, 1.6f)
            } catch (_: Exception) {
            }
            rv.setFloat(R.id.dw_title, "setTextSize", 13f * fontScale)
            rv.setFloat(R.id.dw_empty, "setTextSize", 13f * fontScale)

            val rows = try { loadRows(context) } catch (_: Exception) { emptyList<Row>() }
            rv.removeAllViews(R.id.dw_list)
            rv.setViewVisibility(R.id.dw_empty, if (rows.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE)
            rv.setTextViewText(R.id.dw_empty, ws.empty)

            // Re-render the moment the nearest deadline passes so a task
            // turns red exactly on time, not only at midnight / app saves.
            try {
                val now = System.currentTimeMillis()
                rows.map { it.ts }.filter { it > now }.minOrNull()?.let {
                    TnMidnightReceiver.scheduleDueAlarm(context, it)
                }
            } catch (_: Exception) {
            }

            var lastSection: String? = null
            for (r in rows) {
                // Insert a section header when the due-date bucket changes.
                val section = sectionLabel(context, ws, r.ts)
                if (section != null && section != lastSection) {
                    val header = RemoteViews(context.packageName, R.layout.tn_day_section)
                    header.setTextViewText(R.id.ds_label, section)
                    header.setFloat(R.id.ds_label, "setTextSize", 10f * fontScale)
                    rv.addView(R.id.dw_list, header)
                    lastSection = section
                }
                val row = RemoteViews(context.packageName, R.layout.tn_day_row)
                row.setTextViewText(R.id.dr_title, r.title)
                row.setTextViewText(R.id.dr_meta, r.meta)
                row.setFloat(R.id.dr_title, "setTextSize", 13f * fontScale)
                row.setFloat(R.id.dr_meta, "setTextSize", 11f * fontScale)
                // Overdue: red title + red dot; normal: white title, no dot.
                row.setInt(
                    R.id.dr_title, "setTextColor",
                    if (r.overdue) Color.rgb(255, 107, 107) else Color.WHITE
                )
                row.setViewVisibility(
                    R.id.dr_dot,
                    if (r.overdue) android.view.View.VISIBLE else android.view.View.GONE
                )
                // Priority-colored frame (subtle but visible) on the row.
                when (r.priority) {
                    2 -> row.setInt(R.id.dr_root, "setBackgroundResource", R.drawable.dw_row_bg_high)
                    1 -> row.setInt(R.id.dr_root, "setBackgroundResource", R.drawable.dw_row_bg_med)
                    else -> row.setInt(R.id.dr_root, "setBackgroundResource", R.drawable.dw_row_bg)
                }
                row.setViewVisibility(R.id.dr_check, android.view.View.VISIBLE)
                row.setInt(R.id.dr_check, "setImageResource", R.drawable.ic_dw_check_off)
                val toggle = Intent(ToggleReceiver.ACTION_TOGGLE)
                    .setClass(context, ToggleReceiver::class.java)
                    .putExtra(ToggleReceiver.EXTRA_ENTRY_ID, r.entryId)
                    .putExtra(ToggleReceiver.EXTRA_ITEM_ID, r.itemId)
                val togglePi = PendingIntent.getBroadcast(
                    context,
                    (r.entryId.hashCode() * 31 + (r.itemId?.hashCode() ?: 0)),
                    toggle,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                row.setOnClickPendingIntent(R.id.dr_check, togglePi)
                // Tap the text area → open the app on this chat.
                val openChat = Intent(context, MainActivity::class.java)
                    .putExtra("open_chat", r.chatId)
                val openPi = PendingIntent.getActivity(
                    context,
                    (r.entryId.hashCode() * 17 + 7),
                    openChat,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                row.setOnClickPendingIntent(R.id.dr_root, openPi)
                rv.addView(R.id.dw_list, row)
            }

            // Task-count badge in the header.
            rv.setViewVisibility(
                R.id.dw_count,
                if (rows.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE
            )
            if (rows.isNotEmpty()) {
                rv.setTextViewText(R.id.dw_count, rows.size.toString())
            }

            // Transparency preset shared with the in-app settings screen.
            try {
                var alpha = 1.0f
                // Try multiple read paths: Number (Float/Double), String
                // (Base64-prefixed by older Flutter), and plain numeric string.
                val raw = prefs.all["flutter.tn-widget-alpha"]
                when (raw) {
                    is Number -> alpha = raw.toFloat()
                    is String -> {
                        alpha = raw.removePrefix(PREF_DOUBLE_PREFIX).toFloatOrNull() ?: 1.0f
                    }
                    else -> {
                        // Fallback: also try reading the key without "flutter." prefix
                        // (some SharedPreferences plugins don't add it).
                        val alt = prefs.all["tn-widget-alpha"]
                        when (alt) {
                            is Number -> alpha = alt.toFloat()
                            is String -> alpha = alt.removePrefix(PREF_DOUBLE_PREFIX).toFloatOrNull() ?: 1.0f
                            else -> {}
                        }
                    }
                }
                if (!alpha.isFinite() || alpha < 0.05f || alpha > 1.5f) alpha = 1.0f
                val pct = (Math.round(alpha.coerceIn(0.2f, 1.0f) * 10) * 10).coerceIn(20, 100)
                val resId = context.resources.getIdentifier("tn_widget_bg_$pct", "drawable", context.packageName)
                if (resId != 0) {
                    rv.setInt(R.id.dw_root, "setBackgroundResource", resId)
                } else {
                    // Last resort: apply transparency via alpha directly
                    rv.setInt(R.id.dw_root, "setBackgroundColor",
                        android.graphics.Color.argb((alpha.coerceIn(0.2f, 1.0f) * 255).toInt(), 0x17, 0x21, 0x2B))
                }
            } catch (_: Exception) {
            }
            return rv
        }
    }
}

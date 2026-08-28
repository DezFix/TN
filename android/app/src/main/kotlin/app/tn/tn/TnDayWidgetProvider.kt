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
import java.util.Comparator
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
        for (id in ids) {
            val views = buildViews(context, id)
            manager.updateAppWidget(id, views)
        }
        TnMidnightReceiver.scheduleNext(context)
    }

    companion object {
        /** SharedPreferences stores Dart doubles as strings with this prefix. */
        const val PREF_DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TnDayWidgetProvider::class.java))
            if (ids.isEmpty()) return
            for (id in ids) {
                try {
                    manager.notifyAppWidgetViewDataChanged(id, R.id.dw_list)
                } catch (_: Exception) {}
                val views = buildViews(context, id)
                manager.updateAppWidget(id, views)
            }
        }

        fun readSortMode(context: Context): String {
            return try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.getString("flutter.tn-widget-sort", null)
                    ?: prefs.getString("tn-widget-sort", null)
                    ?: "priority"
            } catch (_: Exception) { "priority" }
        }

        data class Row(
            val entryId: String,
            val itemId: String?,
            val chatId: String,
            val title: String,
            val meta: String,
            val overdue: Boolean,
            val ts: Long,
            val priority: Int,
        )

        fun loadRows(context: Context): List<Row> {
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
                // Собираем задачу + подзадачи в одну строку для чистоты виджета
                val undone = ArrayList<JSONObject>()
                for (j in 0 until items.length()) {
                    val it = items.getJSONObject(j)
                    if (it.optBoolean("done")) continue
                    if (it.optString("text", "").trim().isEmpty()) continue
                    undone.add(it)
                }
                if (undone.isEmpty()) continue
                // Корни — задачи без parentId
                val roots = undone.filter { it.optString("parentId", "").isEmpty() }
                val targets = if (roots.isNotEmpty()) roots else listOf(undone[0])
                for (root in targets) {
                    val rootId = root.optString("id")
                    var title = root.optString("text", "").trim().take(90)
                    // Считаем подзадачи этого корня
                    val subCount = undone.count { it.optString("parentId", "") == rootId }
                    if (subCount > 0) {
                        title = "${title.take(80)} (+$subCount)"
                    }
                    val prio = root.optInt("priority", 0)
                    rows.add(
                        Row(
                            e.optString("id"),
                            rootId,
                            chatId,
                            title,
                            meta(context, names[chatId] ?: "", time0),
                            overdue,
                            time0,
                            prio,
                        )
                    )
                }
            }
            // Всегда сначала новые и по времени (ближайший дедлайн первым)
            rows.sortBy { it.ts }
            return rows
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
        data class Ws(
            val title: String, val empty: String, val overdue: String,
            val secOverdue: String, val secToday: String, val secTomorrow: String, val secLater: String
        )

        fun widgetStrings(context: Context): Ws {
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

        fun priorityHeader(context: Context, priority: Int): String {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            var lang = (prefs.all["flutter.tn-widget-lang"] ?: prefs.all["tn-widget-lang"]) as? String
            if (lang.isNullOrEmpty()) lang = Locale.getDefault().language
            return when (lang.take(2).lowercase(Locale.ROOT)) {
                "ru" -> when (priority) { 2 -> "Срочно"; 1 -> "Важно"; else -> "Обычно" }
                "uk" -> when (priority) { 2 -> "Терміново"; 1 -> "Важливо"; else -> "Звичайно" }
                "de" -> when (priority) { 2 -> "Dringend"; 1 -> "Wichtig"; else -> "Normal" }
                "es" -> when (priority) { 2 -> "Urgente"; 1 -> "Importante"; else -> "Normal" }
                "fr" -> when (priority) { 2 -> "Urgent"; 1 -> "Important"; else -> "Normal" }
                else -> when (priority) { 2 -> "Urgent"; 1 -> "Important"; else -> "Normal" }
            }
        }

        /**
         * Adjustable widget font size (scale, default 1.0) written by the
         * in-app widget settings screen. Shared by the provider (header) and
         * the RemoteViewsFactory (task rows) so the whole widget stays in sync.
         */
        fun readFontScale(context: Context): Float {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            var rawFont: Any? = prefs.all["flutter.tn-widget-font"]
            if (rawFont == null) rawFont = prefs.all["tn-widget-font"]
            var fontScale = when (rawFont) {
                is Number -> rawFont.toFloat()
                is String -> rawFont.removePrefix(PREF_DOUBLE_PREFIX).toFloatOrNull() ?: 1.0f
                else -> 1.0f
            }
            if (!fontScale.isFinite() || fontScale < 0.5f || fontScale > 2.0f) fontScale = 1.0f
            return fontScale.coerceIn(0.8f, 1.6f)
        }
        /** Time + optional chat name for a row's meta line. */
        fun meta(context: Context, chatName: String, time: Long): String {
            val h = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(time))
            return if (chatName.isEmpty()) h
            else "$h · $chatName"
        }

        /** Section bucket title for a due timestamp, or null when none applies. */
        fun sectionLabel(context: Context, ws: Ws, due: Long): String? {
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

        private fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
            val rv = RemoteViews(context.packageName, R.layout.tn_day_widget)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            // Header content (icon+title) opens the app — separated from +/gear for reliable tapping
            val open = Intent(context, MainActivity::class.java)
            rv.setOnClickPendingIntent(
                R.id.dw_header_content,
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

            // + hot add: quick task from widget
            val hotAdd = Intent(context, MainActivity::class.java).apply {
                putExtra("hot_add", true)
            }
            rv.setOnClickPendingIntent(
                R.id.dw_hot_add,
                PendingIntent.getActivity(
                    context, 4, hotAdd,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            val ws = widgetStrings(context)
            rv.setTextViewText(R.id.dw_title, ws.title)
            // Adjustable font size, read through the same helper used by the
            // RemoteViewsFactory so list rows match the widget header.
            val fontScale = readFontScale(context)
            rv.setFloat(R.id.dw_title, "setTextSize", 13f * fontScale)
            rv.setFloat(R.id.dw_empty, "setTextSize", 13f * fontScale)

            val rows = try { loadRows(context) } catch (_: Exception) { emptyList<Row>() }
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

            // Scrollable task list: a ListView fed by a RemoteViewsService.
            // When the rows outgrow the widget's height the user can swipe to
            // see the rest (previously the list was clipped at the widget edge).
            val adapterIntent = Intent(context, TnDayWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            }
            rv.setRemoteAdapter(R.id.dw_list, adapterIntent)
            rv.setEmptyView(R.id.dw_list, R.id.dw_empty)
            // Collection click handling must use fillInIntents (per-item PendingIntents
            // are ignored after scrolling). Single broadcast template handles both
            // toggle (checkbox) and open-chat (row) via action in fillInIntent.
            try {
                val tmpl = Intent(context, ToggleReceiver::class.java)
                val tmplPi = PendingIntent.getBroadcast(
                    context, 100,
                    tmpl,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                )
                rv.setPendingIntentTemplate(R.id.dw_list, tmplPi)
            } catch (_: Exception) {}

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

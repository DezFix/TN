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
            val title: String,
            val meta: String,
            val overdue: Boolean,
            val ts: Long,
        )

        private fun loadRows(context: Context): List<Row> {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return emptyList()
            val period = prefs.getString("flutter.tn-daywidget-period", "all") ?: "all"
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
                    "week" -> if (due == 0L || due > endOfWeekMillis()) continue
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
                            text.take(90),
                            meta(context, names[chatId] ?: "", time0),
                            overdue,
                            time0,
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

        private fun endOfWeekMillis(): Long = startOfTodayMillis() + 7 * 24 * 60 * 60 * 1000L - 1

        /** Time + optional chat name for a row's meta line. */
        private fun meta(context: Context, chatName: String, time: Long): String {
            val h = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(time))
            return if (chatName.isEmpty()) h
            else context.getString(R.string.dw_meta_chat, h, chatName)
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

            rv.setTextViewText(R.id.dw_title, context.getString(R.string.dw_title_tasks))

            // Adjustable font size (scale, default 1.0) written by the in-app
            // widget settings screen.
            var fontScale = 1.0f
            try {
                when (val rawFont = prefs.all["flutter.tn-widget-font"]) {
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

            // Re-render the moment the nearest deadline passes so a task
            // turns red exactly on time, not only at midnight / app saves.
            try {
                val now = System.currentTimeMillis()
                rows.map { it.ts }.filter { it > now }.minOrNull()?.let {
                    TnMidnightReceiver.scheduleDueAlarm(context, it)
                }
            } catch (_: Exception) {
            }

            for (r in rows) {
                val row = RemoteViews(context.packageName, R.layout.tn_day_row)
                row.setTextViewText(R.id.dr_title, r.title)
                row.setTextViewText(R.id.dr_meta, r.meta)
                row.setFloat(R.id.dr_title, "setTextSize", 13f * fontScale)
                row.setFloat(R.id.dr_meta, "setTextSize", 11f * fontScale)
                row.setInt(
                    R.id.dr_meta, "setTextColor",
                    if (r.overdue) Color.rgb(255, 107, 107) else Color.rgb(138, 155, 168)
                )
                row.setViewVisibility(R.id.dr_check, android.view.View.VISIBLE)
                row.setInt(R.id.dr_check, "setImageResource", R.drawable.ic_dw_check_off)
                val toggle = Intent(ToggleReceiver.ACTION_TOGGLE)
                    .setClass(context, ToggleReceiver::class.java)
                    .putExtra(ToggleReceiver.EXTRA_ENTRY_ID, r.entryId)
                    .putExtra(ToggleReceiver.EXTRA_ITEM_ID, r.itemId)
                val pi = PendingIntent.getBroadcast(
                    context,
                    (r.entryId.hashCode() * 31 + (r.itemId?.hashCode() ?: 0)),
                    toggle,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                row.setOnClickPendingIntent(R.id.dr_root, pi)
                rv.addView(R.id.dw_list, row)
            }

            // Transparency preset shared with the in-app settings screen.
            try {
                var alpha = 1.0f
                when (val raw = prefs.all["flutter.tn-widget-alpha"]) {
                    is Number -> alpha = raw.toFloat()
                    is String -> alpha = raw.removePrefix(PREF_DOUBLE_PREFIX).toFloatOrNull() ?: 1.0f
                }
                if (!alpha.isFinite() || alpha < 0.05f || alpha > 1.5f) alpha = 1.0f
                val pct = (Math.round(alpha.coerceIn(0.2f, 1.0f) * 10) * 10).coerceIn(20, 100)
                val resId = context.resources.getIdentifier("tn_widget_bg_$pct", "drawable", context.packageName)
                if (resId != 0) rv.setInt(R.id.dw_root, "setBackgroundResource", resId)
            } catch (_: Exception) {
            }
            return rv
        }
    }
}

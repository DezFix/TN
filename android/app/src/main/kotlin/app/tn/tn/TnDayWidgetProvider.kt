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
 * "Today's tasks" home widget. Rows are built as static child RemoteViews
 * (addView) instead of a ListView + RemoteViewsService: per-row
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
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TnDayWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = buildViews(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private data class Row(
            val entryId: String,
            val title: String,
            val meta: String,
            val overdue: Boolean,
        )

        private fun loadRows(context: Context): List<Row> {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return emptyList()
            val data = JSONObject(raw)
            val names = HashMap<String, String>()
            data.optJSONArray("chats")?.let { chats ->
                for (i in 0 until chats.length()) {
                    val c = chats.getJSONObject(i)
                    names[c.optString("id")] = c.optString("name", "")
                }
            }
            val entries = data.optJSONArray("entries") ?: return emptyList()
            val cal = Calendar.getInstance()
            cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
            val endOfToday = cal.timeInMillis + 24 * 60 * 60 * 1000L - 1

            val tmp = ArrayList<Pair<Long, Row>>()
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                if (e.has("scheduledAt")) continue
                val due = e.optLong("dueAt", 0L)
                if (due == 0L || due > endOfToday) continue
                val items = e.optJSONArray("items") ?: continue
                if (items.length() == 0) continue
                var done = 0
                var firstUndone = ""
                for (j in 0 until items.length()) {
                    val it = items.getJSONObject(j)
                    if (it.optBoolean("done")) done++
                    else if (firstUndone.isEmpty()) firstUndone = it.optString("text", "")
                }
                if (done >= items.length()) continue // fully completed — hide from today list
                val chatName = names[e.optString("chatId")] ?: ""
                val time = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(due))
                val overdue = due < cal.timeInMillis
                val title = firstUndone.ifEmpty { e.optString("text", "").replace('\n', ' ').trim() }
                if (title.isEmpty()) continue
                val meta = when {
                    overdue -> context.getString(R.string.dw_overdue, time)
                    chatName.isEmpty() -> time
                    else -> context.getString(R.string.dw_meta_chat, time, chatName)
                }
                tmp.add(Pair(due, Row(e.optString("id"), title.take(90), meta, overdue)))
            }
            tmp.sortBy { it.first }
            return tmp.take(20).map { it.second }
        }

        private fun buildViews(context: Context): RemoteViews {
            val rv = RemoteViews(context.packageName, R.layout.tn_day_widget)

            // Header opens the app.
            val open = Intent(context, MainActivity::class.java)
            rv.setOnClickPendingIntent(
                R.id.dw_header,
                PendingIntent.getActivity(
                    context, 2, open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            val rows = try { loadRows(context) } catch (_: Exception) { emptyList<Row>() }
            rv.removeAllViews(R.id.dw_list)
            rv.setViewVisibility(R.id.dw_empty, if (rows.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE)
            for ((index, r) in rows.withIndex()) {
                val row = RemoteViews(context.packageName, R.layout.tn_day_row)
                row.setTextViewText(R.id.dr_title, r.title)
                row.setTextViewText(R.id.dr_meta, r.meta)
                row.setInt(
                    R.id.dr_meta, "setTextColor",
                    if (r.overdue) Color.rgb(255, 107, 107) else Color.rgb(138, 155, 168)
                )
                row.setInt(R.id.dr_check, "setImageResource", R.drawable.ic_dw_check_off)

                // Tap anywhere in the row (checkbox included) toggles all items:
                // plays ding, refreshes widgets.
                val toggle = Intent(ToggleReceiver.ACTION_TOGGLE)
                    .setClass(context, ToggleReceiver::class.java)
                    .putExtra(ToggleReceiver.EXTRA_ENTRY_ID, r.entryId)
                val pi = PendingIntent.getBroadcast(
                    context, r.entryId.hashCode(), toggle,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                row.setOnClickPendingIntent(R.id.dr_root, pi)
                rv.addView(R.id.dw_list, row)
            }

            // Transparency preset shared with the main widget.
            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                var alpha = 1.0f
                when (val raw = prefs.all["flutter.tn-widget-alpha"]) {
                    is Number -> alpha = raw.toFloat()
                    is String -> alpha = raw.removePrefix(TnWidgetProvider.PREF_DOUBLE_PREFIX).toFloatOrNull() ?: 1.0f
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

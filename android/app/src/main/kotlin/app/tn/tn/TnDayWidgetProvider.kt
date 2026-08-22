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
 * Configurable "TN" companion widget (second widget type). Two modes driven
 * by prefs written from the in-app widget settings screen:
 *  - tasks: every undone checklist item of the scope, checkable right here;
 *    completed items (and fully done entries) are hidden.
 *  - notes: latest entries of the scope as read-only lines.
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

        /** Mirrors the Dart-side auto-collect rule so scoped widgets see
         *  aggregated ("flexible") chat content, not just own entries. */
        private fun entryIncluded(e: JSONObject, scopeChat: String, chatsArr: JSONArray?): Boolean {
            if (scopeChat.isEmpty()) return true
            val cid = e.optString("chatId", "")
            if (cid == scopeChat) return true
            var rule: JSONObject? = null
            if (chatsArr != null) {
                for (i in 0 until chatsArr.length()) {
                    val c = chatsArr.getJSONObject(i)
                    if (c.optString("id") == scopeChat) {
                        rule = c.optJSONObject("autoCollect")
                        break
                    }
                }
            }
            if (rule == null || !rule.optBoolean("enabled")) return false
            // Aggregator chats never act as sources for other aggregators.
            var sourceIsAggregator = false
            var inScope = true
            if (chatsArr != null) {
                for (i in 0 until chatsArr.length()) {
                    val c = chatsArr.getJSONObject(i)
                    if (c.optString("id") != cid) continue
                    sourceIsAggregator = c.optJSONObject("autoCollect")?.optBoolean("enabled") ?: false
                    if (!rule.optBoolean("fromAllChats", true)) {
                        inScope = c.optString("folderId", "") == rule.optString("sourceFolderId", "")
                    }
                    break
                }
            }
            if (sourceIsAggregator || !inScope) return false
            val type = e.optString("type", "")
            when (rule.optString("typeFilter", "all")) {
                "todo" -> if (type != "todo") return false
                "note" -> if (type == "todo") return false
            }
            if (rule.optString("dueFilter", "any") == "today" && type == "todo") {
                val due = e.optLong("dueAt", 0L)
                if (due > endOfTodayMillis()) return false
            }
            return true
        }

        private fun loadRows(context: Context): List<Row> {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return emptyList()
            val mode = prefs.getString("flutter.tn-daywidget-mode", "tasks") ?: "tasks"
            val scopeChat = prefs.getString("flutter.tn-daywidget-chatId", "") ?: ""
            val data = JSONObject(raw)
            var chatsArr: JSONArray? = null
            val names = HashMap<String, String>()
            data.optJSONArray("chats")?.let { chats ->
                chatsArr = chats
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
                val chatId = e.optString("chatId", "")
                if (!entryIncluded(e, scopeChat, chatsArr)) continue
                if (mode == "tasks") {
                    if (e.optString("type", "") != "todo") continue
                    val items = e.optJSONArray("items") ?: continue
                    val time0 = e.optLong("dueAt", e.optLong("ts", 0L))
                    val due = e.optLong("dueAt", 0L)
                    val overdue = due in 1 until startOfTodayMillis()
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
                } else {
                    val preview = previewOf(e)
                    if (preview.isEmpty()) continue
                    val ts = e.optLong("dueAt", e.optLong("ts", 0L))
                    rows.add(Row(e.optString("id"), null, preview, meta(context, names[chatId] ?: "", ts), false, ts))
                }
            }
            // Tasks: nearest deadline first. Notes: newest first.
            if (mode == "tasks") rows.sortBy { it.ts } else rows.sortByDescending { it.ts }
            return rows.take(20)
        }

        private fun startOfTodayMillis(): Long {
            val cal = Calendar.getInstance()
            cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
            return cal.timeInMillis
        }

        private fun endOfTodayMillis(): Long = startOfTodayMillis() + 24 * 60 * 60 * 1000L - 1

        /** Time + optional chat name for a row's meta line. */
        private fun meta(context: Context, chatName: String, time: Long): String {
            val h = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(time))
            return if (chatName.isEmpty()) h
            else context.getString(R.string.dw_meta_chat, h, chatName)
        }

        private fun previewOf(e: JSONObject): String {
            val base = when (e.optString("type", "text")) {
                "todo" -> {
                    var first = ""
                    var allDone = true
                    val items = e.optJSONArray("items")
                    if (items != null) {
                        for (i in 0 until items.length()) {
                            val it = items.getJSONObject(i)
                            if (!it.optBoolean("done")) allDone = false
                            if (first.isEmpty()) first = it.optString("text", "")
                        }
                    }
                    if (allDone) "" else "\u2610 ${first}".trim()
                }
                "audio" -> "\uD83C\uDF99 \u2022"
                "photo" -> "\uD83D\uDCF7"
                "video" -> "\uD83C\uDFAC"
                else -> e.optString("text", "").replace('\n', ' ').trim()
            }
            return base.take(90)
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

            val mode = prefs.getString("flutter.tn-daywidget-mode", "tasks") ?: "tasks"
            val scopeChat = prefs.getString("flutter.tn-daywidget-chatId", "") ?: ""
            val title = when {
                scopeChat.isNotEmpty() -> chatTitle(prefs, scopeChat) ?: context.getString(
                    if (mode == "tasks") R.string.dw_title_tasks else R.string.dw_title_notes
                )
                else -> context.getString(if (mode == "tasks") R.string.dw_title_tasks else R.string.dw_title_notes)
            }
            rv.setTextViewText(R.id.dw_title, title)

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
                if (mode == "tasks") {
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
                } else {
                    row.setViewVisibility(R.id.dr_check, android.view.View.GONE)
                    val pi = PendingIntent.getActivity(
                        context, 5000 + index, open,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    row.setOnClickPendingIntent(R.id.dr_root, pi)
                }
                rv.addView(R.id.dw_list, row)
            }

            // Transparency preset shared with the main widget.
            try {
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

        private fun chatTitle(prefs: android.content.SharedPreferences, chatId: String): String? {
            return try {
                val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return null
                val chats = JSONObject(raw).optJSONArray("chats") ?: return null
                for (i in 0 until chats.length()) {
                    val c = chats.getJSONObject(i)
                    if (c.optString("id") == chatId) return c.optString("name", "").ifEmpty { null }
                }
                null
            } catch (_: Exception) {
                null
            }
        }
    }
}

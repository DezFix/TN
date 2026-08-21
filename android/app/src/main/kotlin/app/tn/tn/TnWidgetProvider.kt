package app.tn.tn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject

class TnWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, buildViews(context))
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TnWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = buildViews(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun buildViews(context: Context): RemoteViews {
            val rv = RemoteViews(context.packageName, R.layout.tn_widget)

            val intent = Intent(context, MainActivity::class.java)
            val pi = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            rv.setOnClickPendingIntent(R.id.w_root, pi)

            val lines = latestLines(context)
            val ids = intArrayOf(R.id.w_item0, R.id.w_item1, R.id.w_item2, R.id.w_item3, R.id.w_item4)
            for ((i, viewId) in ids.withIndex()) {
                if (i < lines.size) {
                    rv.setViewVisibility(viewId, android.view.View.VISIBLE)
                    rv.setTextViewText(viewId, lines[i])
                } else {
                    rv.setViewVisibility(viewId, android.view.View.GONE)
                }
            }
            return rv
        }

        private fun latestLines(context: Context): List<String> {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return emptyList()
            return try {
                val data = JSONObject(raw)
                val names = HashMap<String, String>()
                val chats = data.optJSONArray("chats")
                if (chats != null) {
                    for (i in 0 until chats.length()) {
                        val c = chats.getJSONObject(i)
                        names[c.optString("id")] = c.optString("name", "")
                    }
                }
                val entries = data.optJSONArray("entries") ?: return emptyList()
                val rows = ArrayList<Triple<Long, String, String>>()
                for (i in 0 until entries.length()) {
                    val e = entries.getJSONObject(i)
                    if (e.has("scheduledAt")) continue // delayed messages are not shown yet
                    val chatId = e.optString("chatId", "")
                    val chatName = names[chatId] ?: ""
                    rows.add(Triple(e.optLong("ts", 0), chatName, previewOf(e)))
                }
                rows.sortByDescending { it.first }
                rows.take(5).map { (ts, name, preview) ->
                    val time = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date(ts))
                    if (name.isEmpty()) "$time  $preview" else "$time  $name: $preview"
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun previewOf(e: JSONObject): String {
            return when (e.optString("type", "text")) {
                "todo" -> {
                    val items = e.optJSONArray("items")
                    if (items == null || items.length() == 0) "\u2611"
                    else {
                        var done = 0
                        var first = ""
                        for (i in 0 until items.length()) {
                            val it = items.getJSONObject(i)
                            if (it.optBoolean("done", false)) done++
                            else if (first.isEmpty()) first = it.optString("text", "")
                        }
                        val mark = if (done == items.length()) "\u2611" else "\u2610"
                        "$mark $done/${items.length()} $first".trim()
                    }
                }
                "audio" -> "\uD83C\uDF99 \u2022"
                "photo" -> "\uD83D\uDCF7"
                "video" -> "\uD83C\uDFAC"
                else -> e.optString("text", "").replace('\n', ' ').trim()
            }.take(80)
        }
    }
}

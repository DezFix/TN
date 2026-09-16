package app.tn.tn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Comparator
import java.util.Date
import java.util.Locale

/**
 * The second TN home-screen widget: undone todos from KANBAN chats only,
 * grouped by board column (Idea / In progress / Done, or custom columns).
 * Rows are checkable right here (same ToggleReceiver as the day widget);
 * tapping a row opens the chat scrolled to that card.
 *
 * Layouts, row drawables and check/open actions are shared with the day
 * widget — only the data source (this file) and the list service
 * ([TnKanbanWidgetService]) differ.
 */
class TnKanbanWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = buildViews(context, id)
            manager.updateAppWidget(id, views)
        }
        TnMidnightReceiver.scheduleNext(context)
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TnKanbanWidgetProvider::class.java))
            if (ids.isEmpty()) return
            for (id in ids) {
                try {
                    manager.notifyAppWidgetViewDataChanged(id, R.id.dw_list)
                } catch (_: Exception) {}
                val views = buildViews(context, id)
                manager.updateAppWidget(id, views)
            }
        }

        data class KbRow(
            val entryId: String,
            val itemId: String?,
            val chatId: String,
            val title: String,
            val meta: String,
            val overdue: Boolean,
            val ts: Long,
            val priority: Int,
            val subPreview: String?,
            val colIndex: Int,
            val colName: String,
        )

        private data class KbChat(
            val name: String,
            val columns: List<Pair<String, String>>, // (id, name) in order
        )

        /** In-app language (same source as the day widget), fallback to system. */
        private fun appLang(context: Context): String {
            return try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                var lang = (prefs.all["flutter.tn-widget-lang"] ?: prefs.all["tn-widget-lang"]) as? String
                if (lang.isNullOrEmpty()) lang = Locale.getDefault().language
                lang.take(2).lowercase(Locale.ROOT)
            } catch (_: Exception) { "en" }
        }

        /** Default column names, mirroring i18n.dart board_idea/work/done. */
        private fun defaultColumns(lang: String): List<Pair<String, String>> = when (lang) {
            "ru" -> listOf("idea" to "Идея", "work" to "В работе", "done" to "Готово")
            "uk" -> listOf("idea" to "Ідея", "work" to "В роботі", "done" to "Готово")
            "de" -> listOf("idea" to "Idee", "work" to "In Arbeit", "done" to "Fertig")
            "es" -> listOf("idea" to "Idea", "work" to "En trabajo", "done" to "Hecho")
            "fr" -> listOf("idea" to "Idée", "work" to "En cours", "done" to "Terminé")
            else -> listOf("idea" to "Idea", "work" to "In progress", "done" to "Done")
        }

        fun kanbanTitle(context: Context): String = when (appLang(context)) {
            "ru", "uk" -> "Канбан"
            else -> "Kanban"
        }

        fun loadRows(context: Context): List<KbRow> {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.tn-notes-data-v1", null) ?: return emptyList()
            val lang = appLang(context)
            val data = JSONObject(raw)
            val chats = HashMap<String, KbChat>()
            data.optJSONArray("chats")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val c = arr.getJSONObject(i)
                    if (c.optString("kind", "") != "kanban") continue
                    val cols = ArrayList<Pair<String, String>>()
                    val bj = c.optJSONArray("board")
                    if (bj != null && bj.length() > 0) {
                        for (j in 0 until bj.length()) {
                            val b = bj.getJSONObject(j)
                            val id = b.optString("id", "")
                            val name = b.optString("name", "")
                            if (id.isNotEmpty() && name.isNotEmpty()) cols.add(id to name)
                        }
                    }
                    if (cols.isEmpty()) cols.addAll(defaultColumns(lang))
                    chats[c.optString("id")] = KbChat(c.optString("name", ""), cols)
                }
            }
            if (chats.isEmpty()) return emptyList()
            val rows = ArrayList<KbRow>()
            val entries = data.optJSONArray("entries") ?: return emptyList()
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                if (!e.isNull("scheduledAt")) continue
                if (e.optString("type", "") != "todo") continue
                val chat = chats[e.optString("chatId", "")] ?: continue
                val cols = chat.columns
                var colIdx = cols.indexOfFirst { it.first == e.optString("boardId", "") }
                if (colIdx < 0) colIdx = 0 // legacy null boardId lives in first column
                val colName = cols[colIdx].second
                val due = e.optLong("dueAt", 0L)
                val time0 = if (due != 0L) due else e.optLong("ts", 0L)
                val overdue = due in 1 until System.currentTimeMillis()
                val items = e.optJSONArray("items") ?: continue
                val undone = ArrayList<JSONObject>()
                for (j in 0 until items.length()) {
                    val it = items.getJSONObject(j)
                    if (it.optBoolean("done")) continue
                    if (it.optString("text", "").trim().isEmpty()) continue
                    undone.add(it)
                }
                if (undone.isEmpty()) continue
                val roots = undone.filter { it.optString("parentId", "").isEmpty() }
                val targets = if (roots.isNotEmpty()) roots else listOf(undone[0])
                for (root in targets) {
                    val rootId = root.optString("id")
                    val title = root.optString("text", "").trim().take(90)
                    val childTexts = undone
                        .filter { it.optString("parentId", "") == rootId }
                        .map { it.optString("text", "").trim() }
                        .filter { it.isNotEmpty() }
                    val subPreview: String? = if (childTexts.isEmpty()) null else {
                        val base = childTexts.take(3).joinToString(" • ")
                        val more = childTexts.size - 3
                        if (more > 0) "$base  +$more" else base
                    }
                    rows.add(
                        KbRow(
                            e.optString("id"),
                            rootId,
                            e.optString("chatId", ""),
                            title,
                            kbMeta(context, chat.name, colName, time0),
                            overdue,
                            time0,
                            root.optInt("priority", 0),
                            subPreview,
                            colIdx,
                            colName,
                        )
                    )
                }
            }
            // Column order first, then priority, overdue, time — Done cards sink naturally.
            rows.sortWith(Comparator { a, b ->
                val c = a.colIndex.compareTo(b.colIndex)
                if (c != 0) return@Comparator c
                val pr = b.priority.compareTo(a.priority)
                if (pr != 0) return@Comparator pr
                val overA = if (a.overdue) 0 else 1
                val overB = if (b.overdue) 0 else 1
                val overCmp = overA.compareTo(overB)
                if (overCmp != 0) return@Comparator overCmp
                a.ts.compareTo(b.ts)
            })
            return rows
        }

        /** "Column · Chat · HH:mm" meta line for a kanban row. */
        private fun kbMeta(context: Context, chatName: String, colName: String, time: Long): String {
            val h = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(time))
            val where = if (chatName.isEmpty()) colName else "$colName · $chatName"
            return "$where · $h"
        }

        private fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
            val rv = RemoteViews(context.packageName, R.layout.tn_day_widget)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            val open = Intent(context, MainActivity::class.java)
            rv.setOnClickPendingIntent(
                R.id.dw_header_content,
                PendingIntent.getActivity(
                    context, 12, open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            // Gear opens the app (no dedicated kanban settings screen).
            rv.setOnClickPendingIntent(
                R.id.dw_settings,
                PendingIntent.getActivity(
                    context, 13, Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            val ws = TnDayWidgetProvider.widgetStrings(context)
            rv.setTextViewText(R.id.dw_title, kanbanTitle(context))
            val fontScale = TnDayWidgetProvider.readFontScale(context)
            rv.setFloat(R.id.dw_title, "setTextSize", 13f * fontScale)
            rv.setFloat(R.id.dw_empty, "setTextSize", 13f * fontScale)

            val rows = try { loadRows(context) } catch (_: Exception) { emptyList<KbRow>() }
            rv.setViewVisibility(R.id.dw_empty, if (rows.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE)
            rv.setTextViewText(R.id.dw_empty, ws.empty)

            try {
                val now = System.currentTimeMillis()
                rows.map { it.ts }.filter { it > now }.minOrNull()?.let {
                    TnMidnightReceiver.scheduleDueAlarm(context, it)
                }
            } catch (_: Exception) {
            }

            val adapterIntent = Intent(context, TnKanbanWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            }
            rv.setRemoteAdapter(R.id.dw_list, adapterIntent)
            rv.setEmptyView(R.id.dw_list, R.id.dw_empty)
            try {
                val tmpl = Intent(context, ToggleReceiver::class.java)
                val tmplPi = PendingIntent.getBroadcast(
                    context, 110,
                    tmpl,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                )
                rv.setPendingIntentTemplate(R.id.dw_list, tmplPi)
            } catch (_: Exception) {}

            rv.setViewVisibility(
                R.id.dw_count,
                if (rows.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE
            )
            if (rows.isNotEmpty()) {
                rv.setTextViewText(R.id.dw_count, rows.size.toString())
            }

            // Same transparency preset as the day widget.
            try {
                var alpha = 1.0f
                val raw = prefs.all["flutter.tn-widget-alpha"]
                when (raw) {
                    is Number -> alpha = raw.toFloat()
                    is String -> {
                        alpha = raw.removePrefix(TnDayWidgetProvider.PREF_DOUBLE_PREFIX).toFloatOrNull() ?: 1.0f
                    }
                    else -> {
                        val alt = prefs.all["tn-widget-alpha"]
                        when (alt) {
                            is Number -> alpha = alt.toFloat()
                            is String -> alpha = alt.removePrefix(TnDayWidgetProvider.PREF_DOUBLE_PREFIX).toFloatOrNull() ?: 1.0f
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
                    rv.setInt(R.id.dw_root, "setBackgroundColor",
                        android.graphics.Color.argb((alpha.coerceIn(0.2f, 1.0f) * 255).toInt(), 0x17, 0x21, 0x2B))
                }
            } catch (_: Exception) {
            }
            return rv
        }
    }
}

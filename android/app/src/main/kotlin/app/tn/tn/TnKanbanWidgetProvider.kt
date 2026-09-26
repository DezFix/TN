package app.tn.tn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.DateFormat
import java.util.Comparator
import java.util.Date
import java.util.LinkedHashMap
import java.util.Locale

class TnKanbanWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            try {
                manager.updateAppWidget(id, buildViews(context, manager, id))
            } catch (_: Exception) {
            }
        }
        TnMidnightReceiver.scheduleNext(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_NEXT_PAGE) {
            val id = try {
                intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, INVALID_WIDGET_ID)
            } catch (_: Exception) {
                INVALID_WIDGET_ID
            }
            if (id != INVALID_WIDGET_ID) {
                val manager = AppWidgetManager.getInstance(context) ?: return
                val snapshot = safeSnapshot(context)
                if (snapshot.columns.isNotEmpty()) {
                    val next = (readPage(context, id) + 1) % snapshot.columns.size
                    writePage(context, id, next)
                    try {
                        manager.updateAppWidget(id, buildViews(context, manager, id))
                    } catch (_: Exception) {
                    }
                }
            }
            return
        }
        super.onReceive(context, intent)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        try {
            manager.updateAppWidget(
                appWidgetId,
                buildViews(context, manager, appWidgetId, newOptions),
            )
        } catch (_: Exception) {
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        try {
            val prefs = context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
            val editor = prefs.edit()
            for (id in appWidgetIds) editor.remove(pageKey(id))
            editor.apply()
        } catch (_: Exception) {
        }
    }

    companion object {
        const val ACTION_NEXT_PAGE = "app.tn.tn.ACTION_KANBAN_NEXT_PAGE"

        private const val KANBAN_CHAT_PREF = "tn-kanbanwidget-chatId"
        private const val STATE_PREFS = "tn_kanban_widget_state"
        private const val PAGE_PREFIX = "page_"
        private const val INVALID_WIDGET_ID = -1
        private const val WIDE_MIN_WIDTH_DP = 280
        private const val MAX_WIDE_COLUMNS = 3
        private const val MAX_WIDE_CARDS = 3
        private const val MAX_COMPACT_CARDS = 6

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
            val type: String = "unknown",
            val dueAt: Long? = null,
            val done: Boolean = false,
        )

        private data class KbColumnDef(
            val id: String,
            val name: String,
        )

        private data class KbChat(
            val id: String,
            val name: String,
            val columns: List<KbColumnDef>,
        )

        private data class KbSnapshot(
            val columns: List<KbColumnDef>,
            val rows: List<KbRow>,
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TnKanbanWidgetProvider::class.java))
            if (ids.isEmpty()) return
            for (id in ids) {
                try {
                    manager.updateAppWidget(id, buildViews(context, manager, id))
                } catch (_: Exception) {
                }
            }
        }

        fun kanbanTitle(context: Context): String =
            localized(context, R.string.kb_title, appLang(context))

        fun loadRows(context: Context): List<KbRow> = safeSnapshot(context).rows

        private fun buildViews(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            options: Bundle? = null,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.kb_widget)
            val lang = appLang(context)
            val snapshot = safeSnapshot(context)
            val fontScale = try {
                TnDayWidgetProvider.readFontScale(context)
            } catch (_: Exception) {
                1.0f
            }

            views.setTextViewText(R.id.kb_title, localized(context, R.string.kb_title, lang))
            views.setTextViewText(R.id.kb_count, snapshot.rows.size.toString())
            views.setFloat(R.id.kb_title, "setTextSize", 14f * fontScale)
            views.setFloat(R.id.kb_count, "setTextSize", 11f * fontScale)
            views.setFloat(R.id.kb_empty, "setTextSize", 12f * fontScale)

            val open = try {
                PendingIntent.getActivity(
                    context,
                    requestCode(appWidgetId, 1, 0),
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            } catch (_: Exception) {
                null
            }
            if (open != null) views.setOnClickPendingIntent(R.id.kb_header_content, open)

            val settings = try {
                PendingIntent.getActivity(
                    context,
                    requestCode(appWidgetId, 1, 1),
                    Intent(context, MainActivity::class.java).putExtra("open_settings", true),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            } catch (_: Exception) {
                null
            }
            if (settings != null) views.setOnClickPendingIntent(R.id.kb_settings, settings)

            val wide = isWide(context, manager, appWidgetId, options)
            val page = pageFor(context, appWidgetId, snapshot.columns.size)
            val nextPage = if (!wide && snapshot.columns.size > 1) {
                try {
                    nextPagePendingIntent(context, appWidgetId)
                } catch (_: Exception) {
                    null
                }
            } else {
                null
            }

            val columnIndexes = if (wide) {
                snapshot.columns.indices.take(MAX_WIDE_COLUMNS).toList()
            } else if (snapshot.columns.isEmpty()) {
                emptyList()
            } else {
                listOf(page)
            }
            var cardIndex = 0
            for (index in columnIndexes) {
                val column = snapshot.columns[index]
                val columnRows = snapshot.rows.filter { it.colIndex == index }
                val columnViews = buildColumn(
                    context = context,
                    column = column,
                    rows = columnRows,
                    fontScale = fontScale,
                    lang = lang,
                    compact = !wide,
                    page = page,
                    pageCount = snapshot.columns.size,
                    nextPage = nextPage,
                    appWidgetId = appWidgetId,
                    cardIndex = cardIndex,
                )
                cardIndex += minOf(columnRows.size, cardLimit(wide))
                try {
                    views.addView(R.id.kb_columns, columnViews)
                } catch (_: Exception) {
                }
            }

            val hasColumns = snapshot.columns.isNotEmpty()
            views.setViewVisibility(R.id.kb_columns, if (hasColumns) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.kb_empty, if (hasColumns) View.GONE else View.VISIBLE)
            views.setTextViewText(
                R.id.kb_empty,
                localized(context, R.string.kb_empty, lang),
            )

            if (nextPage != null) {
                try {
                    views.setOnClickPendingIntent(R.id.kb_columns, nextPage)
                } catch (_: Exception) {
                }
            }

            try {
                val futureDue = snapshot.rows.asSequence()
                    .mapNotNull { it.dueAt }
                    .filter { it > System.currentTimeMillis() }
                    .minOrNull()
                if (futureDue != null) TnMidnightReceiver.scheduleDueAlarm(context, futureDue)
            } catch (_: Exception) {
            }
            applyTransparency(context, views)
            return views
        }

        private fun cardLimit(wide: Boolean): Int =
            if (wide) MAX_WIDE_CARDS else MAX_COMPACT_CARDS

        private fun moreCardsText(context: Context, lang: String, count: Int): String {
            val template = localized(context, R.string.kb_more_cards, lang)
            return template.replace("%1\$d", count.toString()).replace("%d", count.toString())
        }

        private fun buildColumn(
            context: Context,
            column: KbColumnDef,
            rows: List<KbRow>,
            fontScale: Float,
            lang: String,
            compact: Boolean,
            page: Int,
            pageCount: Int,
            nextPage: PendingIntent?,
            appWidgetId: Int,
            cardIndex: Int,
        ): RemoteViews {
            val columnViews = RemoteViews(context.packageName, R.layout.kb_column)
            columnViews.setTextViewText(R.id.kb_column_title, column.name)
            columnViews.setTextViewText(R.id.kb_column_count, rows.size.toString())
            columnViews.setFloat(R.id.kb_column_title, "setTextSize", 11f * fontScale)
            columnViews.setFloat(R.id.kb_column_count, "setTextSize", 10f * fontScale)
            columnViews.setViewVisibility(
                R.id.kb_column_empty,
                if (rows.isEmpty()) View.VISIBLE else View.GONE,
            )
            if (rows.isEmpty()) {
                columnViews.setTextViewText(
                    R.id.kb_column_empty,
                    localized(context, R.string.kb_column_empty, lang),
                )
            }
            if (compact && pageCount > 1) {
                columnViews.setViewVisibility(R.id.kb_page, View.VISIBLE)
                columnViews.setTextViewText(R.id.kb_page, "${page + 1}/$pageCount")
                columnViews.setFloat(R.id.kb_page, "setTextSize", 10f * fontScale)
            } else {
                columnViews.setViewVisibility(R.id.kb_page, View.GONE)
            }
            if (compact && nextPage != null) {
                try {
                    columnViews.setOnClickPendingIntent(R.id.kb_column_root, nextPage)
                    columnViews.setOnClickPendingIntent(R.id.kb_page, nextPage)
                } catch (_: Exception) {
                }
            }
            val limit = cardLimit(!compact)
            val visibleRows = rows.take(limit)
            val hiddenCount = rows.size - visibleRows.size
            columnViews.setViewVisibility(
                R.id.kb_column_more,
                if (hiddenCount > 0) View.VISIBLE else View.GONE,
            )
            if (hiddenCount > 0) {
                columnViews.setTextViewText(
                    R.id.kb_column_more,
                    moreCardsText(context, lang, hiddenCount),
                )
                columnViews.setFloat(R.id.kb_column_more, "setTextSize", 10f * fontScale)
            }
            for ((index, row) in visibleRows.withIndex()) {
                val card = buildCard(
                    context = context,
                    row = row,
                    fontScale = fontScale,
                    lang = lang,
                    appWidgetId = appWidgetId,
                    cardIndex = cardIndex + index,
                )
                try {
                    columnViews.addView(R.id.kb_cards, card)
                } catch (_: Exception) {
                }
            }
            return columnViews
        }

        private fun buildCard(
            context: Context,
            row: KbRow,
            fontScale: Float,
            lang: String,
            appWidgetId: Int,
            cardIndex: Int,
        ): RemoteViews {
            val card = RemoteViews(context.packageName, R.layout.kb_card)
            card.setTextViewText(R.id.kb_card_title, row.title)
            card.setTextViewText(
                R.id.kb_card_deadline,
                deadlineText(context, lang, row.dueAt),
            )
            card.setFloat(R.id.kb_card_title, "setTextSize", 12f * fontScale)
            card.setFloat(R.id.kb_card_deadline, "setTextSize", 10f * fontScale)
            card.setInt(
                R.id.kb_card_title,
                "setTextColor",
                if (row.done) Color.rgb(184, 197, 208) else Color.WHITE,
            )
            card.setInt(
                R.id.kb_card_deadline,
                "setTextColor",
                when {
                    row.overdue -> Color.rgb(255, 107, 107)
                    row.dueAt == null -> Color.rgb(138, 155, 168)
                    else -> Color.rgb(184, 197, 208)
                },
            )
            card.setInt(
                R.id.kb_card_root,
                "setBackgroundResource",
                if (row.done) R.drawable.kb_card_done_bg else R.drawable.kb_card_bg,
            )
            val open = try {
                PendingIntent.getActivity(
                    context,
                    requestCode(appWidgetId, 3, cardIndex),
                    Intent(context, MainActivity::class.java).apply {
                        putExtra("open_chat", row.chatId)
                        if (row.entryId.isNotEmpty()) putExtra("open_entry", row.entryId)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            } catch (_: Exception) {
                null
            }
            if (open != null) {
                try {
                    card.setOnClickPendingIntent(R.id.kb_card_root, open)
                    card.setOnClickPendingIntent(R.id.kb_card_title, open)
                    card.setOnClickPendingIntent(R.id.kb_card_deadline, open)
                } catch (_: Exception) {
                }
            }
            return card
        }

        private fun safeSnapshot(context: Context): KbSnapshot {
            return try {
                loadSnapshot(context)
            } catch (_: Exception) {
                KbSnapshot(emptyList(), emptyList())
            }
        }

        private fun loadSnapshot(context: Context): KbSnapshot {
            val lang = appLang(context)
            val prefs = try {
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            } catch (_: Exception) {
                return KbSnapshot(emptyList(), emptyList())
            }
            val raw = stringPref(prefs, "flutter.tn-notes-data-v1")
                ?: stringPref(prefs, "tn-notes-data-v1")
                ?: return KbSnapshot(emptyList(), emptyList())
            if (raw.isBlank()) return KbSnapshot(emptyList(), emptyList())
            val data = try {
                JSONObject(raw)
            } catch (_: Exception) {
                return KbSnapshot(emptyList(), emptyList())
            }
            val chats = parseChats(context, data, lang)
            if (chats.isEmpty()) return KbSnapshot(emptyList(), emptyList())
            val selectedId = selectedChatId(prefs)
            val board = chats[selectedId] ?: chats.values.firstOrNull()
            val active = listOfNotNull(board)
            if (active.isEmpty()) return KbSnapshot(emptyList(), emptyList())

            val columnCount = active.first().columns.size
                .coerceIn(1, MAX_WIDE_COLUMNS)
            val defaults = defaultColumns(context, lang)
            val columns = ArrayList<KbColumnDef>(columnCount)
            for (index in 0 until columnCount) {
                val first = active.first().columns.getOrNull(index)
                val fallback = defaults.getOrNull(index)
                columns.add(
                    KbColumnDef(
                        id = first?.id ?: "column_$index",
                        name = first?.name ?: fallback?.name ?: localized(context, R.string.kb_column, lang),
                    ),
                )
            }

            val rows = ArrayList<KbRow>()
            val entries = data.optJSONArray("entries")
            if (entries != null) {
                for (entryIndex in 0 until entries.length()) {
                    val entry = entries.optJSONObject(entryIndex) ?: continue
                    val chatId = stringValue(entry, "chatId").trim()
                    if (chatId.isEmpty()) continue
                    val chat = active.firstOrNull { it.id == chatId } ?: continue
                    val boardId = stringValue(entry, "boardId").trim()
                    val boardIndex = chat.columns.indexOfFirst { it.id == boardId }
                    val lane = if (boardIndex < 0) 0 else minOf(boardIndex, columnCount - 1)
                    val row = makeRow(
                        context = context,
                        lang = lang,
                        entry = entry,
                        chat = chat,
                        columnIndex = lane,
                        columnName = columns[lane].name,
                    )
                    rows.add(row)
                }
            }
            rows.sortWith(Comparator { first, second ->
                var result = first.colIndex.compareTo(second.colIndex)
                if (result != 0) return@Comparator result
                if (first.done != second.done) {
                    return@Comparator if (first.done) 1 else -1
                }
                val firstDue = first.dueAt
                val secondDue = second.dueAt
                result = when {
                    firstDue != null && secondDue != null -> firstDue.compareTo(secondDue)
                    firstDue != null -> -1
                    secondDue != null -> 1
                    else -> 0
                }
                if (result != 0) return@Comparator result
                first.ts.compareTo(second.ts)
            })
            return KbSnapshot(columns, rows)
        }

        private fun makeRow(
            context: Context,
            lang: String,
            entry: JSONObject,
            chat: KbChat,
            columnIndex: Int,
            columnName: String,
        ): KbRow {
            val type = stringValue(entry, "type").trim().ifEmpty { "unknown" }
            val items = entry.optJSONArray("items")
            val validItems = ArrayList<JSONObject>()
            if (items != null) {
                for (index in 0 until items.length()) {
                    items.optJSONObject(index)?.let { validItems.add(it) }
                }
            }
            val itemTexts = validItems.map { compactText(stringValue(it, "text")) }
                .filter { it.isNotEmpty() }
            val title = cardTitle(context, lang, entry, type, itemTexts)
            val dueAt = longValue(entry, "dueAt")?.takeIf { it > 0L }
            val timestamp = dueAt ?: longValue(entry, "ts")?.takeIf { it > 0L } ?: 0L
            val done = type.equals("todo", ignoreCase = true) &&
                items != null && items.length() > 0 &&
                validItems.size == items.length() && validItems.all { boolValue(it, "done") }
            val priority = validItems.firstOrNull()?.let { intValue(it, "priority") } ?: 0
            return KbRow(
                entryId = stringValue(entry, "id").trim(),
                itemId = null,
                chatId = stringValue(entry, "chatId").trim(),
                title = title,
                meta = deadlineText(context, lang, dueAt),
                overdue = !done && dueAt != null && dueAt < System.currentTimeMillis(),
                ts = timestamp,
                priority = priority,
                subPreview = null,
                colIndex = columnIndex,
                colName = columnName,
                type = type,
                dueAt = dueAt,
                done = done,
            )
        }

        private fun parseChats(
            context: Context,
            data: JSONObject,
            lang: String,
        ): LinkedHashMap<String, KbChat> {
            val result = LinkedHashMap<String, KbChat>()
            val chats = data.optJSONArray("chats") ?: return result
            for (index in 0 until chats.length()) {
                val chat = chats.optJSONObject(index) ?: continue
                val id = stringValue(chat, "id").trim()
                val kind = stringValue(chat, "kind").trim()
                if (id.isEmpty() || !kind.equals("kanban", ignoreCase = true) || isDeleted(chat)) continue
                val columns = ArrayList<KbColumnDef>()
                val board = chat.optJSONArray("board")
                if (board != null) {
                    for (columnIndex in 0 until board.length()) {
                        if (columns.size >= MAX_WIDE_COLUMNS) break
                        val column = board.optJSONObject(columnIndex) ?: continue
                        val columnId = stringValue(column, "id").trim()
                        val columnName = stringValue(column, "name").trim()
                        if (columnId.isEmpty() || columnName.isEmpty()) continue
                        if (columns.any {
                                it.id == columnId ||
                                    it.name.equals(columnName, ignoreCase = true)
                            }
                        ) {
                            continue
                        }
                        columns.add(KbColumnDef(columnId, columnName))
                    }
                }
                if (columns.isEmpty()) columns.addAll(defaultColumns(context, lang))
                result[id] = KbChat(id, stringValue(chat, "name").trim(), columns)
            }
            return result
        }

        private fun defaultColumns(context: Context, lang: String): List<KbColumnDef> {
            return listOf(
                KbColumnDef("idea", localized(context, R.string.kb_column_idea, lang)),
                KbColumnDef("work", localized(context, R.string.kb_column_work, lang)),
                KbColumnDef("done", localized(context, R.string.kb_column_done, lang)),
            )
        }

        private fun cardTitle(
            context: Context,
            lang: String,
            entry: JSONObject,
            type: String,
            itemTexts: List<String>,
        ): String {
            val text = compactText(stringValue(entry, "text"))
            if (text.isNotEmpty()) return text
            if (itemTexts.isNotEmpty()) return itemTexts.first()
            val mediaName = compactText(stringValue(entry, "mediaName"))
            if (mediaName.isNotEmpty()) return mediaName
            val media = compactText(stringValue(entry, "media"))
            if (media.isNotEmpty()) return media
            return localized(context, typeLabelRes(type), lang)
        }

        private fun typeLabelRes(type: String): Int {
            return when (type.trim().lowercase(Locale.ROOT)) {
                "text" -> R.string.kb_type_text
                "todo" -> R.string.kb_type_todo
                "image" -> R.string.kb_type_image
                "audio" -> R.string.kb_type_audio
                "video" -> R.string.kb_type_video
                "file", "doc" -> R.string.kb_type_file
                else -> R.string.kb_type_unknown
            }
        }

        private fun deadlineText(context: Context, lang: String, dueAt: Long?): String {
            if (dueAt == null || dueAt <= 0L) return localized(context, R.string.kb_no_deadline, lang)
            return try {
                val locale = Locale.forLanguageTag(lang.ifBlank { Locale.getDefault().toLanguageTag() })
                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, locale)
                    .format(Date(dueAt))
            } catch (_: Exception) {
                localized(context, R.string.kb_no_deadline, lang)
            }
        }

        private fun localized(context: Context, resource: Int, lang: String): String {
            return try {
                val locale = Locale.forLanguageTag(lang.ifBlank { Locale.getDefault().toLanguageTag() })
                val configuration = Configuration(context.resources.configuration)
                configuration.setLocale(locale)
                context.createConfigurationContext(configuration).getString(resource)
            } catch (_: Exception) {
                try {
                    context.getString(resource)
                } catch (_: Exception) {
                    ""
                }
            }
        }

        private fun appLang(context: Context): String {
            return try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val raw = prefs.all["flutter.tn-widget-lang"] ?: prefs.all["tn-widget-lang"]
                val value = when (raw) {
                    is String -> raw
                    else -> ""
                }
                if (value.isBlank()) Locale.getDefault().language
                else value.substringBefore('-').substringBefore('_').take(2).lowercase(Locale.ROOT)
            } catch (_: Exception) {
                "en"
            }
        }

        private fun selectedChatId(prefs: SharedPreferences): String {
            val prefixed = stringPref(prefs, "flutter.$KANBAN_CHAT_PREF")
            if (prefixed != null) return prefixed.trim()
            return stringPref(prefs, KANBAN_CHAT_PREF)?.trim() ?: ""
        }

        private fun stringPref(prefs: SharedPreferences, key: String): String? {
            return try {
                when (val value = prefs.all[key]) {
                    is String -> value
                    else -> null
                }
            } catch (_: Exception) {
                null
            }
        }

        private fun stringValue(value: JSONObject, key: String): String {
            val item = try {
                value.opt(key)
            } catch (_: Exception) {
                null
            }
            return when (item) {
                is String -> item
                is CharSequence -> item.toString()
                is Number -> item.toString()
                else -> ""
            }
        }

        private fun longValue(value: JSONObject, key: String): Long? {
            val item = try {
                value.opt(key)
            } catch (_: Exception) {
                null
            }
            return when (item) {
                is Float -> if (item.isFinite()) item.toLong() else null
                is Double -> if (item.isFinite()) item.toLong() else null
                is Number -> try {
                    item.toLong()
                } catch (_: Exception) {
                    null
                }
                is String -> item.trim().toLongOrNull()
                else -> null
            }
        }

        private fun intValue(value: JSONObject, key: String): Int {
            val number = longValue(value, key) ?: return 0
            return number.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
        }

        private fun boolValue(value: JSONObject, key: String): Boolean {
            val item = try {
                value.opt(key)
            } catch (_: Exception) {
                null
            }
            return when (item) {
                is Boolean -> item
                is Number -> try {
                    val number = item.toDouble()
                    number.isFinite() && number != 0.0
                } catch (_: Exception) {
                    false
                }
                is String -> item.equals("true", ignoreCase = true) || item == "1"
                else -> false
            }
        }

        private fun isDeleted(chat: JSONObject): Boolean {
            val value = try {
                chat.opt("deletedAt")
            } catch (_: Exception) {
                return true
            }
            return when (value) {
                null, JSONObject.NULL -> false
                is Boolean -> value
                is Number -> try {
                    value.toDouble() != 0.0
                } catch (_: Exception) {
                    true
                }
                is String -> value.trim().lowercase(Locale.ROOT) !in setOf("", "0", "false", "null")
                else -> true
            }
        }

        private fun compactText(value: String): String {
            return value.replace(Regex("\\s+"), " ").trim().take(120)
        }

        private fun isWide(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            suppliedOptions: Bundle? = null,
        ): Boolean {
            val width = try {
                val options = suppliedOptions ?: manager.getAppWidgetOptions(appWidgetId)
                val min = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                val max = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
                when {
                    min > 0 -> min
                    max > 0 -> max
                    else -> 0
                }
            } catch (_: Exception) {
                0
            }
            if (width <= 0) return true
            val density = context.resources.displayMetrics.density.coerceAtLeast(1f)
            val widthDp = if (width > 600) (width / density).toInt() else width
            return widthDp >= WIDE_MIN_WIDTH_DP
        }

        private fun pageKey(appWidgetId: Int): String = "$PAGE_PREFIX$appWidgetId"

        private fun readPage(context: Context, appWidgetId: Int): Int {
            return try {
                context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
                    .getInt(pageKey(appWidgetId), 0)
                    .coerceAtLeast(0)
            } catch (_: Exception) {
                0
            }
        }

        private fun writePage(context: Context, appWidgetId: Int, page: Int) {
            try {
                context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putInt(pageKey(appWidgetId), page.coerceAtLeast(0))
                    .apply()
            } catch (_: Exception) {
            }
        }

        private fun pageFor(context: Context, appWidgetId: Int, count: Int): Int {
            if (count <= 0) return 0
            return readPage(context, appWidgetId).coerceIn(0, count - 1)
        }

        private fun nextPagePendingIntent(context: Context, appWidgetId: Int): PendingIntent {
            val intent = Intent(context, TnKanbanWidgetProvider::class.java).apply {
                action = ACTION_NEXT_PAGE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode(appWidgetId, 2, 0),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun requestCode(appWidgetId: Int, kind: Int, index: Int): Int {
            return (appWidgetId * 100000 + kind * 1000 + index) and 0x7fffffff
        }

        private fun applyTransparency(context: Context, views: RemoteViews) {
            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val raw = prefs.all["flutter.tn-widget-alpha"] ?: prefs.all["tn-widget-alpha"]
                var alpha = when (raw) {
                    is Number -> raw.toFloat()
                    is String -> raw.removePrefix(TnDayWidgetProvider.PREF_DOUBLE_PREFIX).toFloatOrNull() ?: 1.0f
                    else -> 1.0f
                }
                if (!alpha.isFinite() || alpha < 0.05f || alpha > 1.5f) alpha = 1.0f
                val percent = (Math.round(alpha.coerceIn(0.2f, 1.0f) * 10) * 10)
                    .toInt()
                    .coerceIn(20, 100)
                val resource = context.resources.getIdentifier(
                    "tn_widget_bg_$percent",
                    "drawable",
                    context.packageName,
                )
                if (resource != 0) {
                    views.setInt(R.id.kb_root, "setBackgroundResource", resource)
                }
            } catch (_: Exception) {
            }
        }
    }
}

package app.tn.tn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Powers the scrollable task list inside the day widget.
 *
 * The widget used to stack every row as a static child RemoteViews in a
 * vertical LinearLayout (`addView`), which clipped once the rows outgrew the
 * widget's height. To get real scrolling the list is now a ListView driven by
 * this [RemoteViewsService]/factory via `setRemoteAdapter`. Each item is still
 * an independent RemoteViews with its own per-row click PendingIntent, so the
 * toggle / open-chat behaviour is unchanged from before.
 */
class TnDayWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        TnDayWidgetViewsFactory(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0))
}

/** A list item is either a section header title or a task row. */
private sealed class ListItem {
    data class Header(val title: String) : ListItem()
    data class RowI(val row: TnDayWidgetProvider.Companion.Row) : ListItem()
}

class TnDayWidgetViewsFactory(
    private val context: Context,
    private val appWidgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {

    private val items = ArrayList<ListItem>()
    private var fontScale = 1.0f

    companion object {
        // Space the section header rows so they visually stand apart.
        private const val SectionTopPadId = -1
        private const val SectionPad = 100000
    }

    override fun onCreate() {
        // No-op: work happens in onDataSetChanged.
    }

    override fun onDestroy() {
        items.clear()
    }

    override fun onDataSetChanged() {
        items.clear()
        val ws = TnDayWidgetProvider.widgetStrings(context)
        fontScale = TnDayWidgetProvider.readFontScale(context)
        val rows = try {
            TnDayWidgetProvider.loadRows(context)
        } catch (_: Exception) {
            emptyList<TnDayWidgetProvider.Companion.Row>()
        }
        var lastSection: String? = null
        val flat = ArrayList<ListItem>()
        for (r in rows) {
            // Приоритетные группы: Срочно / Важно / Обычно (вместо времени)
            val section = TnDayWidgetProvider.priorityHeader(context, r.priority)
            if (section != lastSection) {
                flat.add(ListItem.Header(section))
                lastSection = section
            }
            flat.add(ListItem.RowI(r))
        }
        items.addAll(flat)
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        val item = items[position]
        return when (item) {
            is ListItem.Header -> {
                val v = RemoteViews(context.packageName, R.layout.tn_day_section)
                v.setTextViewText(R.id.ds_label, item.title)
                v.setFloat(R.id.ds_label, "setTextSize", 10f * fontScale)
                v
            }
            is ListItem.RowI -> buildRow(item.row)
        }
    }

    private fun buildRow(r: TnDayWidgetProvider.Companion.Row): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.tn_day_row)
        row.setTextViewText(R.id.dr_title, r.title)
        row.setTextViewText(R.id.dr_meta, r.meta)
        row.setFloat(R.id.dr_title, "setTextSize", 13f * fontScale)
        row.setFloat(R.id.dr_meta, "setTextSize", 11f * fontScale)
        // Подзадачи вместе в одной задаче — превью внутри строки родителя.
        if (r.subPreview != null && r.subPreview.isNotEmpty()) {
            row.setTextViewText(R.id.dr_subs, "↳ ${r.subPreview}")
            row.setFloat(R.id.dr_subs, "setTextSize", 10f * fontScale)
            row.setViewVisibility(R.id.dr_subs, android.view.View.VISIBLE)
        } else {
            row.setViewVisibility(R.id.dr_subs, android.view.View.GONE)
        }
        row.setInt(R.id.dr_title, "setTextColor", Color.WHITE)
        row.setInt(
            R.id.dr_meta, "setTextColor",
            if (r.overdue) Color.rgb(255, 107, 107) else Color.parseColor("#8A9BA8")
        )
        row.setViewVisibility(
            R.id.dr_dot,
            if (r.overdue) android.view.View.VISIBLE else android.view.View.GONE
        )
        when (r.priority) {
            2 -> row.setInt(R.id.dr_root, "setBackgroundResource", R.drawable.dw_row_bg_high)
            1 -> row.setInt(R.id.dr_root, "setBackgroundResource", R.drawable.dw_row_bg_med)
            else -> row.setInt(R.id.dr_root, "setBackgroundResource", R.drawable.dw_row_bg)
        }
        row.setViewVisibility(R.id.dr_check, android.view.View.VISIBLE)
        row.setInt(R.id.dr_check, "setImageResource", R.drawable.ic_dw_check_off)

        // Collection widgets must use fillInIntent + template (per-item PendingIntents are ignored after scroll)
        val toggleFill = Intent().apply {
            action = ToggleReceiver.ACTION_TOGGLE
            putExtra(ToggleReceiver.EXTRA_ENTRY_ID, r.entryId)
            putExtra(ToggleReceiver.EXTRA_ITEM_ID, r.itemId)
        }
        row.setOnClickFillInIntent(R.id.dr_check, toggleFill)

        val openFill = Intent().apply {
            action = ToggleReceiver.ACTION_OPEN_CHAT
            putExtra(ToggleReceiver.EXTRA_CHAT_ID, r.chatId)
        }
        row.setOnClickFillInIntent(R.id.dr_root, openFill)
        return row
    }

    override fun getLoadingView(): RemoteViews? {
        val v = RemoteViews(context.packageName, R.layout.tn_day_row)
        v.setTextViewText(R.id.dr_title, "...")
        v.setInt(R.id.dr_meta, "setViewVisibility", android.view.View.GONE)
        v.setInt(R.id.dr_check, "setViewVisibility", android.view.View.GONE)
        return v
    }

    override fun getViewTypeCount(): Int = 2 // section header + task row

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}

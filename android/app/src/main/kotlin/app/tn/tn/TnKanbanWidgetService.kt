package app.tn.tn

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Powers the scrollable card list inside the kanban widget.
 * Mirrors [TnDayWidgetViewsFactory], but rows come from
 * [TnKanbanWidgetProvider.loadRows] and section headers are board
 * columns (in board order), not priority groups. Check/open actions
 * reuse [ToggleReceiver], so behaviour matches the day widget.
 */
class TnKanbanWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        TnKanbanWidgetViewsFactory(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0))
}

private sealed class KbListItem {
    data class Header(val title: String) : KbListItem()
    data class RowI(val row: TnKanbanWidgetProvider.Companion.KbRow) : KbListItem()
}

class TnKanbanWidgetViewsFactory(
    private val context: Context,
    private val appWidgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {

    private val items = ArrayList<KbListItem>()
    private var fontScale = 1.0f

    override fun onCreate() {
        // No-op: work happens in onDataSetChanged.
    }

    override fun onDestroy() {
        items.clear()
    }

    override fun onDataSetChanged() {
        items.clear()
        fontScale = TnDayWidgetProvider.readFontScale(context)
        val rows = try {
            TnKanbanWidgetProvider.loadRows(context)
        } catch (_: Exception) {
            emptyList<TnKanbanWidgetProvider.Companion.KbRow>()
        }
        var lastSection: String? = null
        for (r in rows) {
            if (r.colName != lastSection) {
                items.add(KbListItem.Header(r.colName))
                lastSection = r.colName
            }
            items.add(KbListItem.RowI(r))
        }
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        val item = items[position]
        return when (item) {
            is KbListItem.Header -> {
                val v = RemoteViews(context.packageName, R.layout.tn_day_section)
                v.setTextViewText(R.id.ds_label, item.title)
                v.setFloat(R.id.ds_label, "setTextSize", 10f * fontScale)
                v
            }
            is KbListItem.RowI -> buildRow(item.row)
        }
    }

    private fun buildRow(r: TnKanbanWidgetProvider.Companion.KbRow): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.tn_day_row)
        row.setTextViewText(R.id.dr_title, r.title)
        row.setTextViewText(R.id.dr_meta, r.meta)
        row.setFloat(R.id.dr_title, "setTextSize", 13f * fontScale)
        row.setFloat(R.id.dr_meta, "setTextSize", 11f * fontScale)
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

        val toggleFill = Intent().apply {
            action = ToggleReceiver.ACTION_TOGGLE
            putExtra(ToggleReceiver.EXTRA_ENTRY_ID, r.entryId)
            putExtra(ToggleReceiver.EXTRA_ITEM_ID, r.itemId)
        }
        row.setOnClickFillInIntent(R.id.dr_check, toggleFill)

        val openFill = Intent().apply {
            action = ToggleReceiver.ACTION_OPEN_CHAT
            putExtra(ToggleReceiver.EXTRA_CHAT_ID, r.chatId)
            putExtra(ToggleReceiver.EXTRA_ENTRY_ID, r.entryId)
        }
        row.setOnClickFillInIntent(R.id.dr_root, openFill)
        row.setOnClickFillInIntent(R.id.dr_title, openFill)
        if (r.subPreview != null) row.setOnClickFillInIntent(R.id.dr_subs, openFill)
        row.setOnClickFillInIntent(R.id.dr_meta, openFill)
        return row
    }

    override fun getLoadingView(): RemoteViews? {
        val v = RemoteViews(context.packageName, R.layout.tn_day_row)
        v.setTextViewText(R.id.dr_title, "...")
        v.setInt(R.id.dr_meta, "setViewVisibility", android.view.View.GONE)
        v.setInt(R.id.dr_check, "setViewVisibility", android.view.View.GONE)
        return v
    }

    override fun getViewTypeCount(): Int = 2 // column header + card row

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}

package com.qingdan.qingdan.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.qingdan.qingdan.R

/**
 * 学习通 · 待办（v1.0.6，只读）。默认 2×4。
 *
 * 学习通是**外部只读快照**：没刷新过时显示「打开应用刷新学习通」，不能显示成
 * 「没有待办」——后者是假消息。截止时间是绝对时间，过期条目由 Dart 侧筛掉，
 * 这里不再判断。
 */
class ChaoxingWidgetProvider : BaseWidgetProvider() {
    override fun build(
        ctx: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ): RemoteViews {
        val limit = rowLimit(isTall(mgr, widgetId))
        val rv = RemoteViews(ctx.packageName, R.layout.widget_chaoxing)
        rv.setOnClickPendingIntent(R.id.w_root, WidgetNav.open(ctx, "chaoxing", 12))

        val snap = WidgetSnapshot.read(ctx, WidgetSnapshot.CHAOXING)
        val fetched = snap?.optBoolean("fetched", false) == true
        val total = if (fetched) snap?.optInt("count", 0) ?: 0 else 0
        val dueSoon = if (fetched) snap?.optInt("dueSoon", 0) ?: 0 else 0
        val todos = if (fetched) snap?.optJSONArray("todos") else null

        rv.setTextViewText(R.id.w_header, if (fetched) "学习通 · 待办 $total" else "学习通 · 待办")
        rv.setTextViewText(R.id.w_count, if (dueSoon > 0) "$dueSoon 条 24h 内" else "")

        var shown = 0
        val count = minOf(limit, todos?.length() ?: 0)
        for (i in 0 until count) {
            val t = todos!!.getJSONObject(i)
            val course = t.optString("course")
            val due = if (t.isNull("due")) null else t.optLong("due")
            val meta = listOf(course, WidgetSnapshot.formatDue(due))
                .filter { it.isNotEmpty() }
                .joinToString(" · ")
            rv.setViewVisibility(WidgetRows.ROW_IDS[i], View.VISIBLE)
            rv.setTextViewText(WidgetRows.TITLE_IDS[i], t.optString("title"))
            rv.setTextViewText(WidgetRows.META_IDS[i], meta)
            rv.setOnClickPendingIntent(
                WidgetRows.ROW_IDS[i],
                WidgetNav.open(ctx, "chaoxing", 300 + WidgetRows.ROW_IDS[i]),
            )
            shown++
        }
        hideRows(rv, shown)

        when {
            !fetched -> {
                rv.setViewVisibility(R.id.w_empty, View.VISIBLE)
                rv.setTextViewText(R.id.w_empty, ctx.getString(R.string.widget_chaoxing_stale))
            }
            total == 0 -> {
                rv.setViewVisibility(R.id.w_empty, View.VISIBLE)
                rv.setTextViewText(R.id.w_empty, ctx.getString(R.string.widget_chaoxing_empty))
            }
            else -> rv.setViewVisibility(R.id.w_empty, View.GONE)
        }

        val more = total - shown
        if (more > 0) {
            rv.setViewVisibility(R.id.w_more, View.VISIBLE)
            rv.setTextViewText(R.id.w_more, ctx.getString(R.string.widget_more, more))
        } else if (fetched) {
            rv.setViewVisibility(R.id.w_more, View.VISIBLE)
            rv.setTextViewText(
                R.id.w_more,
                "更新于 ${WidgetSnapshot.formatUpdated(snap?.optLong("fetchedAt", 0))}",
            )
        } else {
            rv.setViewVisibility(R.id.w_more, View.GONE)
        }
        return rv
    }
}

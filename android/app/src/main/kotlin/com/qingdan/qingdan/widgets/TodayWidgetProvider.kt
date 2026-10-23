package com.qingdan.qingdan.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.qingdan.qingdan.R
import org.json.JSONObject

/**
 * 清单 · 今天（v1.0.6，只读）。
 *
 * 只画快照里属于**今天**的未完成任务；快照日期不是今天就整卡显示「打开应用
 * 查看今天的安排」——挂着昨天的任务却写「今天」是更坏的一种错。
 * 点一条任务 → 直接推该任务详情（`task:<id>`）。
 */
class TodayWidgetProvider : BaseWidgetProvider() {
    override fun build(
        ctx: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ): RemoteViews {
        val tall = isTall(mgr, widgetId)
        val limit = rowLimit(tall)
        val rv = RemoteViews(ctx.packageName, R.layout.widget_today)
        rv.setTextViewText(
            R.id.w_header,
            "今天 · ${WidgetSnapshot.weekdayCn()} ${WidgetSnapshot.mmdd()}",
        )
        rv.setOnClickPendingIntent(R.id.w_root, WidgetNav.open(ctx, "today", 10))

        val snap = WidgetSnapshot.read(ctx, WidgetSnapshot.TODAY)
        val fresh = snap?.optString("date") == WidgetSnapshot.todayKey()
        val tasks = if (fresh) snap?.optJSONArray("tasks") else null
        val total = if (fresh) snap?.optInt("total", 0) ?: 0 else 0

        rv.setTextViewText(R.id.w_count, if (fresh) "$total 项" else "")

        var shown = 0
        val count = minOf(limit, tasks?.length() ?: 0)
        for (i in 0 until count) {
            val item: JSONObject = tasks!!.getJSONObject(i)
            rv.setViewVisibility(WidgetRows.ROW_IDS[i], View.VISIBLE)
            rv.setTextViewText(WidgetRows.TIME_IDS[i], item.optString("due"))
            rv.setTextViewText(WidgetRows.TITLE_IDS[i], item.optString("title"))
            rv.setOnClickPendingIntent(
                WidgetRows.ROW_IDS[i],
                WidgetNav.open(
                    ctx,
                    "task:${item.optString("id")}",
                    100 + WidgetRows.ROW_IDS[i],
                ),
            )
            shown++
        }
        hideRows(rv, shown)

        val empty = when {
            !fresh -> ctx.getString(R.string.widget_today_stale)
            total == 0 -> ctx.getString(R.string.widget_today_empty)
            else -> null
        }
        if (empty != null) {
            rv.setViewVisibility(R.id.w_empty, View.VISIBLE)
            rv.setTextViewText(R.id.w_empty, empty)
        } else {
            rv.setViewVisibility(R.id.w_empty, View.GONE)
        }

        if (fresh && total > shown) {
            rv.setViewVisibility(R.id.w_more, View.VISIBLE)
            rv.setTextViewText(
                R.id.w_more,
                ctx.getString(R.string.widget_more, total - shown),
            )
        } else if (fresh) {
            rv.setViewVisibility(R.id.w_more, View.GONE)
        }
        return rv
    }
}

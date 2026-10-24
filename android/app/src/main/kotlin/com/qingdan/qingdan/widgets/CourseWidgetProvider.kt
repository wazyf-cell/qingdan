package com.qingdan.qingdan.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import com.qingdan.qingdan.R

/**
 * 课表 · 今日（v1.0.6，只读）。默认 2×4 显示五节，2×2 只留两节。
 *
 * 「没有学期」「学期外」「今天没课」必须是三句不同的话：合成一句「暂无课程」
 * 会让用户以为课丢了（课表页此前就因为这类空态被误判过）。
 */
class CourseWidgetProvider : BaseWidgetProvider() {
    override fun build(
        ctx: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ): RemoteViews {
        val limit = rowLimit(isTall(mgr, widgetId))
        val rv = RemoteViews(ctx.packageName, R.layout.widget_course)
        rv.setOnClickPendingIntent(R.id.w_root, WidgetNav.open(ctx, "course", 11))

        val snap = WidgetSnapshot.read(ctx, WidgetSnapshot.COURSE)
        val fresh = snap?.optString("date") == WidgetSnapshot.todayKey()
        val state = if (fresh) snap?.optString("state") ?: "no_semester" else ""
        val courses = if (fresh && state == "ok") snap?.optJSONArray("courses") else null
        val total = courses?.length() ?: 0

        if (state == "ok") {
            rv.setTextViewText(R.id.w_header, "第 ${snap?.optInt("week", 0)} 周")
            rv.setTextViewText(R.id.w_sub, WidgetSnapshot.weekdayCn())
        } else {
            rv.setTextViewText(R.id.w_header, "课表")
            rv.setTextViewText(R.id.w_sub, "今日")
        }
        rv.setTextViewText(R.id.w_count, if (total > 0) "$total 门" else "")

        var shown = 0
        val count = minOf(limit, total)
        for (i in 0 until count) {
            val c = courses!!.getJSONObject(i)
            val start = c.optString("start")
            val end = c.optString("end")
            val room = c.optString("room")
            val time = if (start.isNotEmpty() && end.isNotEmpty()) "$start–$end" else c.optString("section")
            val meta = listOf(time, room).filter { it.isNotEmpty() }.joinToString(" · ")
            rv.setViewVisibility(WidgetRows.ROW_IDS[i], View.VISIBLE)
            rv.setInt(
                WidgetRows.COLOR_IDS[i],
                "setBackgroundColor",
                WidgetPalette.course(ctx, c.optInt("color", 0)),
            )
            rv.setTextViewText(WidgetRows.TITLE_IDS[i], c.optString("name"))
            rv.setTextViewText(WidgetRows.META_IDS[i], meta)
            // 点课不会定位到某一节（列表页没有这一层的入口），统一进课表页。
            rv.setOnClickPendingIntent(
                WidgetRows.ROW_IDS[i],
                WidgetNav.open(ctx, "course", 200 + WidgetRows.ROW_IDS[i]),
            )
            shown++
        }
        hideRows(rv, shown)

        val empty = when {
            !fresh -> ctx.getString(R.string.widget_course_stale)
            state == "no_semester" -> ctx.getString(R.string.widget_course_no_semester)
            state == "outside_semester" -> ctx.getString(R.string.widget_course_outside)
            total == 0 -> ctx.getString(R.string.widget_course_empty)
            else -> null
        }
        if (empty != null) {
            rv.setViewVisibility(R.id.w_empty, View.VISIBLE)
            rv.setTextViewText(R.id.w_empty, empty)
        } else {
            rv.setViewVisibility(R.id.w_empty, View.GONE)
        }

        if (total > shown) {
            rv.setViewVisibility(R.id.w_more, View.VISIBLE)
            rv.setTextViewText(R.id.w_more, ctx.getString(R.string.widget_more, total - shown))
        } else {
            rv.setViewVisibility(R.id.w_more, View.GONE)
        }
        return rv
    }
}

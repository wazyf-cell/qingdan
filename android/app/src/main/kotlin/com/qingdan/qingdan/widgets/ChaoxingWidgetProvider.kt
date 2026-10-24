package com.qingdan.qingdan.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.qingdan.qingdan.R

/**
 * 学习通 · 待办（v1.0.6，只读）。默认 2×4。
 *
 * 学习通是**外部只读快照**：没刷新过时显示「打开应用刷新学习通」，不能显示成
 * 「没有待办」——后者是假消息。截止时间是绝对时间，过期条目由 Dart 侧筛掉。
 *
 * 1.0.9 起列表改成集合（`ListView`）：最多 15 条都能滚动看完，超过 15 条才在
 * 页脚写「还有 N 条」。2×2 与 2×4 共用同一份内容，不再按高度砍行。
 */
class ChaoxingWidgetProvider : BaseWidgetProvider() {
    override fun build(
        ctx: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ): RemoteViews {
        val rv = RemoteViews(ctx.packageName, R.layout.widget_chaoxing)
        rv.setOnClickPendingIntent(R.id.w_root, WidgetNav.open(ctx, "chaoxing", 12))
        rv.setTextViewText(R.id.w_header, "学习通")
        rv.setTextViewText(R.id.w_sub, "待办")

        val snap = WidgetSnapshot.read(ctx, WidgetSnapshot.CHAOXING)
        val fetched = snap?.optBoolean("fetched", false) == true
        val total = if (fetched) snap?.optInt("count", 0) ?: 0 else 0
        val dueSoon = if (fetched) snap?.optInt("dueSoon", 0) ?: 0 else 0
        val todos = if (fetched) snap?.optJSONArray("todos") else null
        val listed = minOf(todos?.length() ?: 0, ChaoxingWidgetService.MAX_ROWS)

        rv.setTextViewText(R.id.w_count, if (fetched) "$total 条" else "")

        // 集合本身由 Service 提供；这里只负责把适配器接上，并让每一行共用
        // 同一个「打开学习通」模板。行内的 fill-in intent 只带 data。
        val adapter = Intent(ctx, ChaoxingWidgetService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            data = Uri.parse("qingdan://widget/chaoxing/$widgetId")
        }
        rv.setRemoteAdapter(R.id.w_list, adapter)
        rv.setPendingIntentTemplate(R.id.w_list, WidgetNav.template(ctx))

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

        if (fetched) {
            val stamp = WidgetSnapshot.formatUpdated(snap?.optLong("fetchedAt", 0))
            val more = total - listed
            rv.setViewVisibility(R.id.w_more, View.VISIBLE)
            rv.setTextViewText(
                R.id.w_more,
                if (stamp.isEmpty()) "已刷新" else "更新于 $stamp",
            )
            // 两条信息只能留一条时优先「还有 N 条」：超过 15 条被截断是用户
            // 必须知道的，24h 提醒在应用里还有别的入口。只有 24h 提醒用警示橙，
            // 「还有 N 条」是普通说明，别让它看起来像出了问题。
            val dueColor = if (more > 0) R.color.widget_text_secondary else R.color.widget_warn
            rv.setTextColor(R.id.w_due, ctx.getColor(dueColor))
            when {
                more > 0 -> {
                    rv.setViewVisibility(R.id.w_due, View.VISIBLE)
                    rv.setTextViewText(R.id.w_due, "还有 $more 条")
                }
                dueSoon > 0 -> {
                    rv.setViewVisibility(R.id.w_due, View.VISIBLE)
                    rv.setTextViewText(R.id.w_due, "$dueSoon 条 24h 内")
                }
                else -> rv.setViewVisibility(R.id.w_due, View.GONE)
            }
        } else {
            rv.setViewVisibility(R.id.w_more, View.GONE)
            rv.setViewVisibility(R.id.w_due, View.GONE)
        }
        return rv
    }

    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        super.onUpdate(ctx, mgr, ids)
        // 卡片本体已经更新过，集合数据要单独通知，否则列表停在上次拉到的内容。
        mgr.notifyAppWidgetViewDataChanged(ids, R.id.w_list)
    }

    override fun onAppWidgetOptionsChanged(
        ctx: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(ctx, mgr, widgetId, newOptions)
        mgr.notifyAppWidgetViewDataChanged(widgetId, R.id.w_list)
    }
}

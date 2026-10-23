package com.qingdan.qingdan.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews

/**
 * 三个卡片的共同骨架：`onUpdate` / 尺寸变化都走一次 [build]。
 *
 * 尺寸不做两套布局：同一份布局里藏行。`minHeight >= 180dp` 视为 2×4（五行），
 * 否则 2×2（两行）。这样用户拖动改尺寸时内容自然增减，不用维护两份 XML。
 */
abstract class BaseWidgetProvider : AppWidgetProvider() {
    protected abstract fun build(
        ctx: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
    ): RemoteViews

    protected fun isTall(mgr: AppWidgetManager, widgetId: Int): Boolean {
        val options = mgr.getAppWidgetOptions(widgetId)
        return options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) >= 180
    }

    protected fun rowLimit(tall: Boolean): Int =
        if (tall) WidgetRows.TALL_ROWS else WidgetRows.SMALL_ROWS

    /** 后面的行一律隐藏（小尺寸、或这一屏没那么多条目）。 */
    protected fun hideRows(rv: RemoteViews, from: Int) {
        for (i in from until WidgetRows.ROW_IDS.size) {
            rv.setViewVisibility(WidgetRows.ROW_IDS[i], View.GONE)
        }
    }

    override fun onUpdate(
        ctx: Context,
        mgr: AppWidgetManager,
        ids: IntArray,
    ) {
        for (id in ids) mgr.updateAppWidget(id, build(ctx, mgr, id))
    }

    override fun onAppWidgetOptionsChanged(
        ctx: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        mgr.updateAppWidget(widgetId, build(ctx, mgr, widgetId))
    }
}

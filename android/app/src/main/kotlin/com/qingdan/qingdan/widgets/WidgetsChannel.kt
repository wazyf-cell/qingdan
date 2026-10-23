package com.qingdan.qingdan.widgets

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 小组件 → 原生（v1.0.6）：让桌面重画 / 问支不支持钉卡片 / 发起钉卡片 / 回桌面。
 *
 * 通道名与 `lib/platform/widget_bridge.dart` 成对。所有方法都回 bool：设置页
 * 只按「成没成」提示，不把原生异常原文甩给用户。
 */
object WidgetsChannel {
    private const val CHANNEL = "qingdan/widgets"

    private val PROVIDERS: Map<String, Class<*>> = mapOf(
        "today" to TodayWidgetProvider::class.java,
        "course" to CourseWidgetProvider::class.java,
        "chaoxing" to ChaoxingWidgetProvider::class.java,
    )

    fun register(engine: FlutterEngine, ctx: Context) {
        val channel =
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "refreshWidgets" -> {
                    refresh(ctx)
                    result.success(true)
                }
                "isPinSupported" -> result.success(pinSupported(ctx))
                "pinWidget" -> {
                    val key = call.argument<String>("provider") ?: ""
                    result.success(pin(ctx, key))
                }
                "goHome" -> result.success(goHome(ctx))
                else -> result.notImplemented()
            }
        }
    }

    /** 三个 Provider 各自收到一次 APPWIDGET_UPDATE，带上自己现有的 id。 */
    private fun refresh(ctx: Context) {
        val mgr = AppWidgetManager.getInstance(ctx)
        for (cls in PROVIDERS.values) {
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, cls))
            if (ids.isEmpty()) continue
            val intent = Intent(ctx, cls)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            ctx.sendBroadcast(intent)
        }
    }

    private fun pinSupported(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return AppWidgetManager.getInstance(ctx).isRequestPinAppWidgetSupported
    }

    /**
     * 系统确认框由桌面弹，点「添加」才真的落卡片；这里能做的只是把请求发出去，
     * 返回 false 表示本机桌面不支持走请求，调用方要改成「长按桌面添加」的说明。
     */
    private fun pin(ctx: Context, key: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val cls = PROVIDERS[key] ?: return false
        val mgr = AppWidgetManager.getInstance(ctx)
        if (!mgr.isRequestPinAppWidgetSupported) return false
        return try {
            mgr.requestPinAppWidget(ComponentName(ctx, cls), null, null)
        } catch (e: Exception) {
            false
        }
    }

    private fun goHome(ctx: Context): Boolean = try {
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_HOME)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }
}

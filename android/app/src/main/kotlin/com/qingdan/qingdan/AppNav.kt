package com.qingdan.qingdan

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 快捷方式 → Flutter 的路由通道（v1.0.6）。
 *
 * 冷启动时 `onCreate` 拿到的 intent 早于 Dart 侧挂监听，因此这里先暂存
 * （[pending]），等 Dart 调 `initialRoute` 时再交付；之后的 intent（应用已在
 * 后台）直接 `invokeMethod("route")`。少了这个暂存，第一次点快捷方式会没反应 ——
 * 只有第二次之后才正常，是最容易漏测的形状。
 *
 * 路由来自 `res/xml/shortcuts.xml` 的 `qingdan://shortcut/<route>`；小组件点击
 * 也复用同一条通道（`qingdan://open/<route>`，见 WidgetNav）。
 */
object AppNav {
    private const val CHANNEL = "qingdan/nav"
    private const val SCHEME = "qingdan"

    private var channel: MethodChannel? = null
    private var pending: String? = null
    private var ready = false

    fun register(engine: FlutterEngine) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialRoute" -> {
                    ready = true
                    val route = pending
                    pending = null
                    result.success(route)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** 解析 intent 里的路由；不是本应用的导航 intent 就忽略。 */
    fun handle(intent: Intent?) {
        val route = routeOf(intent) ?: return
        if (ready) channel?.invokeMethod("route", route) else pending = route
        // 消费掉 data：Activity 因任何原因重建时不把同一条路由再放一遍（会重复推详情页）。
        intent?.data = null
    }

    private fun routeOf(intent: Intent?): String? {
        val data: Uri = intent?.data ?: return null
        if (data.scheme != SCHEME) return null
        val route = data.lastPathSegment ?: return null
        return if (data.host == "shortcut" || data.host == "open") route else null
    }
}

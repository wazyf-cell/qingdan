package com.qingdan.qingdan

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * C3 系统权限深链的 Android 侧。
 *
 * 为什么用 Intent 而不是在应用里做开关：通知权限与电池优化都由系统持有，
 * 应用只能把人送过去、不能替用户点。返回值只表示「系统页有没有成功拉起」，
 * 不代表用户最后改成了什么——那本来也回读不到。
 */
object SystemIntents {
    /** 与 lib/platform/system_intents.dart 的通道名成对，改一边必须改另一边。 */
    private const val CHANNEL = "qingdan/system"

    fun register(activity: FlutterActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, reply ->
            val opened: Boolean? = when (call.method) {
                // 8.0 以下没有「本应用通知页」，按规格回落到应用详情页
                "openNotificationSettings" -> start(activity, notificationIntent(activity) ?: detailsIntent(activity))
                "openAppNotificationSettings" -> notificationIntent(activity)?.let { start(activity, it) } ?: false
                "openBatteryOptimizationSettings" -> start(activity, batteryIntent())
                "openAppDetails" -> start(activity, detailsIntent(activity))
                // 更新通道的「GitHub 仓库」与「去发布页」：交给系统默认浏览器。
                // 协议在这里再判一次——Dart 侧已经挡过一道，但这条通道谁都能调。
                "openUrl" -> call.argument<String>("url")
                    ?.let { Uri.parse(it) }
                    ?.takeIf { it.scheme == "https" || it.scheme == "http" }
                    ?.let { start(activity, Intent(Intent.ACTION_VIEW, it)) }
                    ?: false
                else -> null
            }
            if (opened == null) reply.notImplemented() else reply.success(opened)
        }
    }

    /** API 26 才有；返回 null 表示这台设备没有该页面，由调用方决定回落。 */
    private fun notificationIntent(activity: FlutterActivity): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        } else {
            null
        }

    private fun detailsIntent(activity: FlutterActivity): Intent =
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null),
        )

    /**
     * 用白名单列表页，不用 ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS：
     * 后者直接弹系统授权框（Google Play 政策受限，对用户也更粗暴），
     * 列表页让用户先看见全局再自己决定。
     */
    private fun batteryIntent(): Intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)

    private fun start(activity: FlutterActivity, intent: Intent): Boolean =
        try {
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false // 定制 ROM 可能删掉某个系统设置页；Dart 侧统一按 false 处理
        }
}

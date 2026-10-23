package com.qingdan.qingdan

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

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
            // 安装时间不是「打开某个系统页」，返回值是两个毫秒时间戳，单独回。
            // 更新说明靠它区分「全新安装」与「从旧版升级」：1.0.2 没有写过
            // app.lastSeenVersion，只看偏好分不出这两种情况。
            if (call.method == "installTimes") {
                val pm = activity.packageManager
                val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getPackageInfo(activity.packageName, PackageManager.PackageInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(activity.packageName, 0)
                }
                reply.success(
                    mapOf(
                        "firstInstallTime" to info.firstInstallTime,
                        "lastUpdateTime" to info.lastUpdateTime,
                    ),
                )
                return@setMethodCallHandler
            }
            // 应用内更新（1.0.4）：ABI 用来挑对的那份 APK；签名用来在进系统安装器
            // 之前就发现「这台设备是另一个签名的旧包」，而不是让用户吃一句英文报错。
            if (call.method == "deviceAbi") {
                reply.success(Build.SUPPORTED_ABIS.firstOrNull())
                return@setMethodCallHandler
            }
            if (call.method == "packageSignature") {
                reply.success(selfSignature(activity.packageManager, activity.packageName))
                return@setMethodCallHandler
            }
            if (call.method == "apkSignature") {
                reply.success(call.argument<String>("path")?.let { apkSignature(activity, it) })
                return@setMethodCallHandler
            }
            if (call.method == "canInstallPackages") {
                val pm = activity.packageManager
                reply.success(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        pm.canRequestPackageInstalls()
                    } else {
                        true // 8.0 以下没有这个开关，装包时由系统直接问
                    },
                )
                return@setMethodCallHandler
            }
            if (call.method == "openInstallPermission") {
                // 允许后系统不会回调我们；Dart 侧让用户回来后再点一次。
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.fromParts("package", activity.packageName, null))
                reply.success(start(activity, intent))
                return@setMethodCallHandler
            }
            if (call.method == "installApk") {
                reply.success(installApk(activity, call.argument<String>("path")))
                return@setMethodCallHandler
            }
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

    /** 本机已装包当前签名的 SHA-256（小写十六进制）；取不到返回 null。 */
    private fun selfSignature(pm: PackageManager, packageName: String): String? =
        try {
            // 必须带 GET_SIGNING_CERTIFICATES：flags 传 0 时 `signingInfo` 是 null，
            // 这次真机验收就是这样把「签名一致」误判成不一致的。
            val flags =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    PackageManager.GET_SIGNING_CERTIFICATES
                } else {
                    @Suppress("DEPRECATION")
                    PackageManager.GET_SIGNATURES
                }
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(flags.toLong()))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(packageName, flags)
            }
            certDigest(info)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }

    /**
     * 一个 APK 文件里**当前**签名证书的 SHA-256。
     *
     * 用 `getPackageArchiveInfo` 只读文件、不安装；Dart 侧拿它和已装版本比对，
     * 不一致就根本不进系统安装器——那一步只会甩一句英文的 UPDATE_INCOMPATIBLE。
     */
    private fun apkSignature(activity: FlutterActivity, path: String): String? {
        val file = File(path)
        if (!file.exists()) return null
        val pm = activity.packageManager
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                @Suppress("DEPRECATION")
                PackageManager.GET_SIGNATURES
            }
        val info: PackageInfo? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageArchiveInfo(path, flags)
        }
        return info?.let(::certDigest)
    }

    /** 取「当前签名者」的第一张证书；签名轮换时 `apkContentsSigners` 才是正在用的那把。 */
    private fun certDigest(info: PackageInfo): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = info.signingInfo ?: return null
            // 即使是「新旧两把证书都签了」的轮换包，apkContentsSigners 也是当前这一把。
            val first = signing.apkContentsSigners.firstOrNull() ?: return null
            return sha256Hex(first.toByteArray())
        }
        @Suppress("DEPRECATION")
        val first = info.signatures?.firstOrNull() ?: return null
        return sha256Hex(first.toByteArray())
    }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }

    /** 把缓存里的 APK 交给系统安装器。用户还要在系统界面点一次「安装」。 */
    private fun installApk(activity: FlutterActivity, path: String?): Boolean {
        if (path.isNullOrEmpty()) return false
        val file = File(path)
        if (!file.exists()) return false
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: IllegalArgumentException) {
            // FileProvider 配置与目录对不上时 getUriForFile 会抛这个
            false
        }
    }
}

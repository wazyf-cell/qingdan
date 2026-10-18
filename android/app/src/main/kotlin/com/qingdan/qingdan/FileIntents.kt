package com.qingdan.qingdan

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * M6-D §9.2 导出落地的 Android 侧：SAF「另存为」(ACTION_CREATE_DOCUMENT) + 往选中的
 * URI 回写字节。通道名与 `lib/platform/file_intents.dart` 成对（`qingdan/file`）。
 *
 * 结果回传走「`MainActivity` override `onActivityResult` → 转交本对象」这条最朴素的
 * 路。两条看起来更现代的都编译不过：androidx 的 `registerForActivityResult` 要
 * `activity-ktx` 依赖（本工程没引，`Unresolved reference`）；embedding 的
 * `FlutterActivity.OnActivityResultListener` 在当前引擎版本里已经不存在了。
 * 第一、二版分别挂在这两处（2026-10-18 实测）。
 *
 * 三个边界各有一条专门处理（缺一个就是「点了没反应」事故）：
 *  1. 用户取消（`RESULT_CANCELED`）→ `reply.success(null)`，Dart 视为「取消，什么都不写」；
 *  2. 同一个 `MethodChannel.Result` 只能回复一次，重复 reply 抛 `IllegalStateException`
 *     → 回复前先把 pending 摘走置 null；在途时又来了新请求，旧的先 `success(null)`；
 *  3. 结果回来后立刻摘掉 activity result 监听，不留悬挂回调。
 *
 * 「不可用」与「取消」用不同出口：`ActivityNotFound` 走 `reply.error(...)`（Dart 抛异常
 * → 界面落应用目录兜底），取消走 `reply.success(null)`。
 */
object FileIntents {
    private const val CHANNEL = "qingdan/file"

    /** 本文件独占的请求码；同一时刻至多一个在途 createDocument。 */
    private const val REQ_CREATE = 0x5101

    private var pending: MethodChannel.Result? = null

    fun register(activity: FlutterActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, reply -> handle(activity, call, reply) }
    }

    private fun handle(
        activity: FlutterActivity,
        call: MethodCall,
        reply: MethodChannel.Result,
    ) {
        when (call.method) {
            "createDocument" -> createDocument(activity, call, reply)
            "writeToUri" -> reply.success(writeToUri(activity, call))
            else -> reply.notImplemented()
        }
    }

    private fun createDocument(
        activity: FlutterActivity,
        call: MethodCall,
        reply: MethodChannel.Result,
    ) {
        // 边界 2：上一个还没回，先替它回 null（规格：拿不到就让用户重试），绝不持有两个 Result
        pending?.success(null)
        pending = reply
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = call.argument<String>("mime") ?: "*/*"
            putExtra(Intent.EXTRA_TITLE, call.argument<String>("fileName") ?: "export")
        }
        try {
            activity.startActivityForResult(intent, REQ_CREATE)
        } catch (_: ActivityNotFoundException) {
            val out = pending
            pending = null
            // 某些 ROM 删掉了文档提供者：这是「不可用」不是「取消」，用 error 让 Dart 落兜底
            reply.error("unavailable", "系统没有可打开「另存为」的组件", null)
        }
    }

    /**
     * 由 `MainActivity.onActivityResult` 转交。返回 true 表示这个 requestCode 归本文件，
     * Activity 不必再往下传给 super（我们没在别处用同一个请求码）。
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_CREATE) return false
        val out = pending
        pending = null // 先摘走：保证任何 Result 至多被回复一次
        if (out == null) return true // 边界 3：进程被回收后回来，没人等了
        val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        out.success(uri?.toString()) // 取消或没带 URI → null（边界 1）
        return true
    }

    private fun writeToUri(activity: FlutterActivity, call: MethodCall): Boolean {
        val uriStr = call.argument<String>("uri") ?: return false
        val bytes: ByteArray = call.argument<ByteArray>("bytes") ?: return false
        return try {
            // "w" 截断重写：重复导出同一文件不能把上一份的尾巴留在后面
            val stream = activity.contentResolver.openOutputStream(Uri.parse(uriStr), "w")
                ?: return false
            stream.use { it.write(bytes) }
            true
        } catch (_: IOException) {
            false // 只读 URI、provider 抽风：统一 false，由 Dart 落兜底或报失败
        }
    }
}

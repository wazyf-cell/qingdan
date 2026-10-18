package com.qingdan.qingdan

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * M6-D §9.2 导出落地的 Android 侧：SAF「另存为」(ACTION_CREATE_DOCUMENT) + 往选中的
 * URI 回写字节。通道名与 lib/platform/file_intents.dart 成对（qingdan/file）。
 *
 * 三个边界各有一条专门处理（缺一个就是「点了没反应」事故）：
 *  1. 用户取消 RESULT_CANCELED → reply.success(null)，Dart 视为「取消，什么都不写」；
 *  2. 同一个 MethodChannel.Result 只能回复一次，重复 reply 抛 IllegalStateException
 *     → 回复前先把 pending 取出并置 null；处理中又来啦新请求时，旧的先 success(null)；
 *  3. 进程被系统回收后拿不到 pending Result → 回调取到 null 直接放弃（旧 Flutter
 *     引擎随进程一起没了，用户回来重导一次即可；**本轮未在真机验证，属推断**）。
 *
 * 「不可用」与「取消」用不同出口：ActivityNotFound 走 reply.error(...)（Dart 抛异常
 * → 界面落应用目录兜底），取消走 reply.success(null)。
 */
object FileIntents {
    private const val CHANNEL = "qingdan/file"

    /** 同一时刻至多一个在途 createDocument（用户连点两次不会叠两个系统弹窗）。 */
    private var pending: MethodChannel.Result? = null

    fun register(activity: FlutterActivity, engine: FlutterEngine) {
        // configureFlutterEngine 在 onCreate 阶段调用，早于 RESUMED，注册 launcher 合法。
        val launcher: ActivityResultLauncher<Intent> =
            activity.registerForActivityResult(
                ActivityResultContracts.StartActivityForResult()
            ) { result ->
                val reply = pending
                pending = null // 先摘走：保证任何 Result 至多被回复一次
                if (reply == null) return@registerForActivityResult // 边界 3
                val uri: Uri? =
                    if (result.resultCode == Activity.RESULT_OK) result.data?.data else null
                reply.success(uri?.toString()) // 取消或没带 URI → null（边界 1）
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, reply -> handle(activity, launcher, call, reply) }
    }

    private fun handle(
        activity: FlutterActivity,
        launcher: ActivityResultLauncher<Intent>,
        call: MethodCall,
        reply: MethodChannel.Result,
    ) {
        when (call.method) {
            "createDocument" -> createDocument(launcher, call, reply)
            "writeToUri" -> reply.success(writeToUri(activity, call))
            else -> reply.notImplemented()
        }
    }

    private fun createDocument(
        launcher: ActivityResultLauncher<Intent>,
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
            launcher.launch(intent)
        } catch (_: ActivityNotFoundException) {
            pending = null
            // 某些 ROM 删掉了文档提供者：这是「不可用」不是「取消」，用 error 让 Dart 落兜底
            reply.error("unavailable", "系统没有可打开「另存为」的组件", null)
        }
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

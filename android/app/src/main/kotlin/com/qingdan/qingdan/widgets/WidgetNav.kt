package com.qingdan.qingdan.widgets

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.qingdan.qingdan.MainActivity

/**
 * 小组件点击 → 应用内路由。
 *
 * 复用 `AppNav` 的 `qingdan://open/<route>`（host = open），路由字符串与长按
 * 快捷方式同一套：`today` / `course` / `chaoxing` / `task:<id>`。
 * `FLAG_IMMUTABLE` 是 Android 12+ 的硬要求；`UPDATE_CURRENT` 让同一行任务
 * 换内容后点击仍落到新任务。
 */
object WidgetNav {
    fun open(ctx: Context, route: String, requestCode: Int): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("qingdan://open/$route")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        return PendingIntent.getActivity(
            ctx,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

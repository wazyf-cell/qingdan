package com.qingdan.qingdan.widgets

import android.content.Context
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 读取 Flutter 写下的三份小组件快照（v1.0.6）。
 *
 * 键名与 `lib/features/widgets/widget_snapshot_service.dart` 的常量成对：
 * SharedPreferences 文件固定叫 `FlutterSharedPreferences`，Dart 写入时会给键加
 * `flutter.` 前缀。**不要**在这里开 SQLite —— 库有迁移与同步语义，schema 不是
 * 对外契约；快照只含「这一屏要显示的字段」。
 */
object WidgetSnapshot {
    private const val PREFS = "FlutterSharedPreferences"
    private const val PREFIX = "flutter."

    const val TODAY = "widget.today"
    const val COURSE = "widget.course"
    const val CHAOXING = "widget.chaoxing"

    private val WEEKDAYS =
        arrayOf("周日", "周一", "周二", "周三", "周四", "周五", "周六")

    /** 快照缺失或内容坏掉都返回 null；小组件显示「打开应用」，不崩。 */
    fun read(ctx: Context, key: String): JSONObject? {
        val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(PREFIX + key, null) ?: return null
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            null
        }
    }

    /** `2026-10-24`，与 Dart 侧 `widgetDateKey` 完全同形。 */
    fun todayKey(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    fun weekdayCn(): String {
        val index = Calendar.getInstance().get(Calendar.DAY_OF_WEEK)
        return WEEKDAYS[index - 1]
    }

    fun mmdd(): String = SimpleDateFormat("M/d", Locale.US).format(Date())

    /** 学习通截止时间：`10-25 23:59`；null → 「无截止」。 */
    fun formatDue(ms: Long?): String {
        if (ms == null) return "无截止"
        return SimpleDateFormat("MM-dd HH:mm", Locale.US).format(Date(ms))
    }

    /** 小组件角上的「更新于」：当天只给时分，跨天带月日。 */
    fun formatUpdated(ms: Long?): String {
        if (ms == null) return ""
        val d = Date(ms)
        val sameDay = SimpleDateFormat("yyyyMMdd", Locale.US).format(d) ==
            SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
        val pattern = if (sameDay) "HH:mm" else "MM-dd HH:mm"
        return SimpleDateFormat(pattern, Locale.US).format(d)
    }
}

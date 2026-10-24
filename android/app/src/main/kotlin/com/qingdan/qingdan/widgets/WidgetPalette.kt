package com.qingdan.qingdan.widgets

import android.content.Context
import android.content.res.Configuration

/**
 * 课表色条的颜色来源：与 Flutter 的 `CoursePalette` 同一套 8 色。
 *
 * 小组件不读 SQLite，也不从 Dart 传颜色（快照里只有 `colorIndex`），
 * 所以这里必须与 `lib/theme/app_palette.dart` 手工保持一致；改色两边一起改。
 */
object WidgetPalette {
    private val LIGHT = intArrayOf(
        0xFF0E7C86.toInt(), // 0 松石
        0xFF6741D8.toInt(), // 1 靛紫
        0xFFA61E7E.toInt(), // 2 洋红
        0xFF8A6D1F.toInt(), // 3 古铜
        0xFF4A5568.toInt(), // 4 石墨
        0xFF2F6B4F.toInt(), // 5 森绿
        0xFF9A5B24.toInt(), // 6 赭石
        0xFF1C6E9B.toInt(), // 7 海蓝
    )

    private val DARK = intArrayOf(
        0xFF3FA9B5.toInt(),
        0xFFA08AE0.toInt(),
        0xFFD958A8.toInt(),
        0xFFD2A54A.toInt(),
        0xFF8B95A5.toInt(),
        0xFF6FB894.toInt(),
        0xFFC98A4B.toInt(),
        0xFF58A9D6.toInt(),
    )

    fun course(ctx: Context, index: Int): Int {
        val night = ctx.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val palette = if (night) DARK else LIGHT
        val safe = if (index < 0) 0 else index % palette.size
        return palette[safe]
    }
}

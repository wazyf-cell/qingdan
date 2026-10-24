package com.qingdan.qingdan.widgets

import com.qingdan.qingdan.R

/**
 * 「清单」与「课表」布局里固定的 5 行控件 id。
 *
 * 学习通卡片改用集合（`ListView`），行数由 `ChaoxingWidgetService` 决定，
 * 不再受这里的 5 行限制；这两个卡片仍用固定行：一天的任务/课再多也只是少数，
 * 用小尺寸时不值得为滚动多背一个 Service。
 */
object WidgetRows {
    val ROW_IDS = intArrayOf(
        R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5,
    )
    val TITLE_IDS = intArrayOf(
        R.id.row1_title, R.id.row2_title, R.id.row3_title,
        R.id.row4_title, R.id.row5_title,
    )

    /** 只有「清单」布局有独立时间列。 */
    val TIME_IDS = intArrayOf(
        R.id.row1_time, R.id.row2_time, R.id.row3_time,
        R.id.row4_time, R.id.row5_time,
    )

    /** 课表布局的第二行说明。 */
    val META_IDS = intArrayOf(
        R.id.row1_meta, R.id.row2_meta, R.id.row3_meta,
        R.id.row4_meta, R.id.row5_meta,
    )

    /** 只有「课表」布局有课程色条。 */
    val COLOR_IDS = intArrayOf(
        R.id.row1_color, R.id.row2_color, R.id.row3_color,
        R.id.row4_color, R.id.row5_color,
    )

    /** 2×4 的行数；2×2 只留两行。 */
    const val TALL_ROWS = 5
    const val SMALL_ROWS = 2
}

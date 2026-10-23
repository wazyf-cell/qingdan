package com.qingdan.qingdan.widgets

import com.qingdan.qingdan.R

/**
 * 三个小组件布局里固定的 5 行控件 id。
 *
 * 布局没有用集合（RemoteViewsService）：卡片最多 5 条，固定行更容易做「点某一条
 * 进它自己的详情」，也省掉一个 Service。2×2 时 Provider 只点亮前两行。
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

    /** 课表 / 学习通布局的第二行说明。 */
    val META_IDS = intArrayOf(
        R.id.row1_meta, R.id.row2_meta, R.id.row3_meta,
        R.id.row4_meta, R.id.row5_meta,
    )

    /** 2×4 的行数；2×2 只留两行。 */
    const val TALL_ROWS = 5
    const val SMALL_ROWS = 2
}

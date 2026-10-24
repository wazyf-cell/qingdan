package com.qingdan.qingdan.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.qingdan.qingdan.R
import org.json.JSONObject

/**
 * 「学习通 · 待办」卡片的集合数据源（v1.0.9）。
 *
 * 读的还是 Dart 写下的那份 SharedPreferences 快照，不碰 SQLite。最多给
 * [MAX_ROWS] 条：15 条以内全部可滚动显示，超过的部分由 Provider 写在页脚，
 * 不在这里假装数据不存在。
 */
class ChaoxingWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext)

    private data class Row(
        val title: String,
        val meta: String,
        val urgent: Boolean,
    )

    private class Factory(private val ctx: Context) : RemoteViewsFactory {
        private var rows: List<Row> = emptyList()

        override fun onCreate() = Unit

        override fun onDataSetChanged() {
            rows = load()
        }

        private fun load(): List<Row> {
            val snap = WidgetSnapshot.read(ctx, WidgetSnapshot.CHAOXING)
                ?: return emptyList()
            if (!snap.optBoolean("fetched", false)) return emptyList()
            val todos = snap.optJSONArray("todos") ?: return emptyList()
            val now = System.currentTimeMillis()
            val soon = now + 24L * 60 * 60 * 1000
            val n = minOf(todos.length(), MAX_ROWS)
            val out = ArrayList<Row>(n)
            for (i in 0 until n) {
                val t: JSONObject = todos.optJSONObject(i) ?: continue
                val due: Long? = if (t.isNull("due")) null else t.optLong("due")
                val course = t.optString("course")
                val meta = listOf(course, WidgetSnapshot.formatDue(due))
                    .filter { it.isNotEmpty() }
                    .joinToString(" · ")
                // 「24h 内」与 Dart 侧 dueSoon 同一口径：还没到点、且只剩不到一天。
                val urgent = due != null && due > now && due <= soon
                out.add(Row(t.optString("title"), meta, urgent))
            }
            return out
        }

        override fun getCount(): Int = rows.size

        override fun getViewAt(position: Int): RemoteViews? {
            val row = rows.getOrNull(position) ?: return null
            return RemoteViews(ctx.packageName, R.layout.widget_chaoxing_row).apply {
                setTextViewText(R.id.row_title, row.title)
                setTextViewText(R.id.row_meta, row.meta)
                // 颜色必须每次都设：ListView 会复用行视图，不设的话上一条的橙色
                // 会留在这一条上（真机截图里 11-01 的作业被染成了「24h 内」）。
                setTextColor(
                    R.id.row_meta,
                    ctx.getColor(
                        if (row.urgent) R.color.widget_warn
                        else R.color.widget_text_secondary,
                    ),
                )
                // 模板 PendingIntent 只到 MainActivity；这里补上路由 data。
                setOnClickFillInIntent(
                    R.id.row_root,
                    Intent().setData(Uri.parse("qingdan://open/chaoxing")),
                )
            }
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 1

        override fun getItemId(position: Int): Long = position.toLong()

        override fun hasStableIds(): Boolean = false

        override fun onDestroy() = Unit
    }

    companion object {
        /** 卡片最多列多少条；再多就在页脚写「还有 N 条」。 */
        const val MAX_ROWS = 15
    }
}

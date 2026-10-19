/// 学习通「作业」页（`mooc1-api.chaoxing.com/work/stu-work`）的 HTML 解析。
///
/// **来源声明**（AGENTS.md 禁止事项要求逐个文件标注）：选择器与取值位置逐条
/// 照抄用户目录里的油猴脚本 `扩展/作业列表.js`（AGPL-3.0-or-later，上游
/// Cooanyh/chaoxing-list）——`extractTasks` :757-791（`div[role="option"]` 内
/// `p`=标题、第 1 个 span=状态、第 2 个=课程、`.fr`=剩余时间、`li[data]` 里
/// taskrefId/courseId/clazzId）、完成判定 :169-173（`className.includes("status")`
/// 即未提交）、剩余时间解析 :3268-3281。只重写解析这层，未拷贝其 Vue UI。
///
/// 两个页面本身不给的事实，按扩展界面的同法补：
/// - **绝对截止时间**：页面只有「剩余241小时」，扩展渲染的「10-18 22:59 截止」
///   是 抓取时刻 + 剩余 推出来的，这里同样推成 [ChaoxingTask.dueAt]。
/// - **完整课程名**：页面上的课程 span 被服务端截断成《课程丙...》，
///   用 `data` 里的 courseId 回查课程表补全。
library;

import 'chaoxing_html.dart';
import 'chaoxing_models.dart';
import 'chaoxing_time.dart';

class ChaoxingHomework {
  static final RegExp _kLi =
      RegExp(r'<li\b[^>]*?data="([^"]*)"[\s\S]*?</li>');
  static final RegExp _kOption = RegExp(r'<div role="option">([\s\S]*?)</div>');
  static final RegExp _kTitle = RegExp(r'<p[^>]*>([\s\S]*?)</p>');
  static final RegExp _kSpan = RegExp(r'<span([^>]*)>([\s\S]*?)</span>');
  static final RegExp _kClass = RegExp(r'class="([^"]*)"');

  /// [courseNames] 为 courseId → 完整课程名；[now] 为抓取时刻（推截止时间用）。
  static List<ChaoxingTask> parsePage(
    String html, {
    required Map<String, String> courseNames,
    required DateTime now,
  }) {
    final List<ChaoxingTask> out = <ChaoxingTask>[];
    for (final RegExpMatch li in _kLi.allMatches(html)) {
      final String block = li.group(0)!;
      final Match? option = _kOption.firstMatch(block);
      final Match? title = _kTitle.firstMatch(block);
      if (option == null || title == null) continue;
      // `data` 里是 `&amp;` 分隔的，先还原实体再拆参数，否则第二个键会变成
      // 字面量 `amp;msgId`（原来那版靠 Uri.tryParse 顺带做了这件事）。
      final String data = unescapeHtml(li.group(1)!);
      final Map<String, String> params = queryOf(data);
      String status = '';
      String course = '';
      String left = '';
      bool overdue = false;
      bool classHasStatus = false;
      for (final RegExpMatch span in _kSpan.allMatches(option.group(1)!)) {
        final String text = htmlText(span.group(2)!);
        if (text.isEmpty) continue;
        final String cls = _kClass.firstMatch(span.group(1)!)?.group(1) ?? '';
        if (status.isEmpty &&
            !text.startsWith('《') &&
            !text.startsWith('剩余') &&
            !text.contains('过期')) {
          status = text;
          classHasStatus = cls.contains('status');
        } else if (course.isEmpty && text.startsWith('《')) {
          course = text.replaceAll('《', '').replaceAll('》', '');
        } else if (left.isEmpty && text.startsWith('剩余')) {
          left = text;
        } else if (text.contains('过期')) {
          overdue = true;
        }
      }
      final Duration? remaining = parseRemaining(left);
      final bool finished = !classHasStatus ||
          status.contains('已完成') ||
          status.contains('待批阅');
      final String head = htmlText(title.group(1)!);
      out.add(ChaoxingTask(
        id: params['taskrefId'] ?? params['activeId'] ?? head,
        courseId: params['courseId'] ?? '',
        courseName: courseNames[params['courseId']] ?? course,
        title: head,
        kind: '作业',
        source: ChaoxingSource.homework,
        ongoing: !overdue,
        startAt: null,
        dueAt: remaining == null ? null : now.add(remaining),
        serverStatus: status.isEmpty ? null : status,
        serverDone: finished,
        unread: block.contains('class="redPoint"'),
        // 同一串 data 里就带 clazzId（脚本 :757-791 也在读它），早先没取出来，
        // 导致「详情」URL 拼不出来（M6B §B3）。缺省就是缺省，不猜。
        clazzId: params['clazzId'],
        // 2026-10-19 实测：这一页 `li[data]` 的值**就是**那条入口地址
        // （`android/mtaskmsgspecial?…&enc_task=…`，页面自己的 `goTask(this)`
        // 拿它当 url 用）。整条留着，详情页要靠它取正文——参数拆出来只剩
        // 三个 id，`enc_task` 一丢就再也进不去了。不是 http 开头的按缺省处理。
        detailEntryUrl: data.startsWith('http') ? data : null,
      ));
    }
    return ChaoxingTask.dedupe(out);
  }
}

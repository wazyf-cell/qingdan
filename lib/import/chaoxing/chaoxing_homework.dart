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

import 'chaoxing_models.dart';

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
      final Map<String, String> params =
          Uri.tryParse(_unescape(li.group(1)!))?.queryParameters ??
              const <String, String>{};
      String status = '';
      String course = '';
      String left = '';
      bool overdue = false;
      bool classHasStatus = false;
      for (final RegExpMatch span in _kSpan.allMatches(option.group(1)!)) {
        final String text = _unescape(span.group(2)!).trim();
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
      final Duration? remaining = _parseLeft(left);
      final bool finished = !classHasStatus ||
          status.contains('已完成') ||
          status.contains('待批阅');
      out.add(ChaoxingTask(
        id: params['taskrefId'] ?? params['activeId'] ?? title.group(1)!,
        courseId: params['courseId'] ?? '',
        courseName: courseNames[params['courseId']] ?? course,
        title: _unescape(title.group(1)!).trim(),
        kind: '作业',
        ongoing: !overdue,
        startAt: null,
        dueAt: remaining == null ? null : now.add(remaining),
        serverStatus: status.isEmpty ? null : status,
        serverDone: finished,
        unread: block.contains('class="redPoint"'),
      ));
    }
    return ChaoxingTask.dedupe(out);
  }

  /// 「剩余241小时」/「剩余120小时55分钟」/「剩余1天0小时」→ Duration。
  /// 含「过期」视为已结束（脚本 :3269 同义）。
  static Duration? _parseLeft(String text) {
    if (text.isEmpty || text.contains('过期')) return null;
    final int days = _num(text, r'(\d+)\s*天');
    final int hours = _num(text, r'(\d+)\s*小时');
    final int minutes = _num(text, r'(\d+)\s*分');
    if (days == 0 && hours == 0 && minutes == 0) return null;
    return Duration(days: days, hours: hours, minutes: minutes);
  }

  static int _num(String text, String pattern) =>
      int.tryParse(RegExp(pattern).firstMatch(text)?.group(1) ?? '') ?? 0;

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

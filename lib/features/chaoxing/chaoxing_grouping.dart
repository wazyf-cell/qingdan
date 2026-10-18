/// 学习通面板的视图模型：扩展成品工具栏的四个控件（课程筛选 / 仅看未完成 /
/// 仅看可提交 / 排序）+ 搜索 + 两个页签（全部作业 / 课堂活动）。
///
/// 语义对齐扩展：「仅看未完成」= 藏掉已完成与已结束；「仅看可提交」= 只留
/// 没过期且没交的（扩展里未提交且未过期才会出现在待办区）。排序选项照抄
/// 脚本 :3258-3265 的五档，默认「截止最早优先」。
library;

import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/import/chaoxing/chaoxing_time.dart';

enum ChaoxingTab {
  homework('全部作业'),
  activities('课堂活动');

  const ChaoxingTab(this.label);

  final String label;
}

enum ChaoxingSortBy {
  timeAsc('截止最早优先'),
  timeDesc('截止最晚优先'),
  course('按课程'),
  status('按状态'),
  name('按名称');

  const ChaoxingSortBy(this.label);

  final String label;
}

class ChaoxingViewSettings {
  const ChaoxingViewSettings({
    this.hidden = const <String>{},
    this.onlyUnfinished = false,
    this.onlySubmittable = false,
    this.sortBy = ChaoxingSortBy.timeAsc,
    this.tab = ChaoxingTab.homework,
  });

  /// 长按隐藏的条目键（本地便签，不进库不同步）。
  final Set<String> hidden;
  final bool onlyUnfinished;
  final bool onlySubmittable;
  final ChaoxingSortBy sortBy;
  final ChaoxingTab tab;

  ChaoxingViewSettings copyWith({
    Set<String>? hidden,
    bool? onlyUnfinished,
    bool? onlySubmittable,
    ChaoxingSortBy? sortBy,
    ChaoxingTab? tab,
  }) =>
      ChaoxingViewSettings(
        hidden: hidden ?? this.hidden,
        onlyUnfinished: onlyUnfinished ?? this.onlyUnfinished,
        onlySubmittable: onlySubmittable ?? this.onlySubmittable,
        sortBy: sortBy ?? this.sortBy,
        tab: tab ?? this.tab,
      );
}

class ChaoxingRow {
  const ChaoxingRow(this.task, this.state);

  final ChaoxingTask task;
  final ChaoxingTaskState state;
}

/// 作业页条目带服务端状态原文，活动页条目不带——这就是两个页签的分界。
List<ChaoxingTask> tasksOfTab(List<ChaoxingTask> tasks, ChaoxingTab tab) => tasks
    .where((ChaoxingTask t) =>
        (t.serverStatus != null) == (tab == ChaoxingTab.homework))
    .toList();

List<ChaoxingRow> buildRows(
  List<ChaoxingTask> tasks,
  ChaoxingViewSettings s,
  DateTime now, {
  String query = '',
  String course = '',
}) {
  final String q = query.trim().toLowerCase();
  final List<ChaoxingRow> rows = <ChaoxingRow>[];
  for (final ChaoxingTask t in tasks) {
    if (s.hidden.contains(t.key)) continue;
    final ChaoxingTaskState state = t.stateAt(now, done: false);
    if (s.onlyUnfinished &&
        (state == ChaoxingTaskState.done || state == ChaoxingTaskState.ended)) {
      continue;
    }
    if (s.onlySubmittable &&
        state != ChaoxingTaskState.todo &&
        state != ChaoxingTaskState.notStarted) {
      continue;
    }
    if (course.isNotEmpty && t.courseName != course) continue;
    if (q.isNotEmpty &&
        !t.title.toLowerCase().contains(q) &&
        !t.courseName.toLowerCase().contains(q)) {
      continue;
    }
    rows.add(ChaoxingRow(t, state));
  }
  rows.sort(_comparator(s.sortBy));
  return rows;
}

/// 课程筛选下拉的选项（当前页签数据里出现过的课程）。
List<String> courseOptions(List<ChaoxingTask> tasks) =>
    (tasks.map((ChaoxingTask t) => t.courseName).toSet().toList()..sort());

Comparator<ChaoxingRow> _comparator(ChaoxingSortBy sortBy) =>
    (ChaoxingRow a, ChaoxingRow b) => _compare(sortBy, a, b);

int _compare(ChaoxingSortBy sortBy, ChaoxingRow a, ChaoxingRow b) {
  final int byTitle = a.task.title.compareTo(b.task.title);
  switch (sortBy) {
    case ChaoxingSortBy.timeAsc:
      final int byDue = _dueAsc(a.task.dueAt, b.task.dueAt);
      return byDue != 0 ? byDue : byTitle;
    case ChaoxingSortBy.timeDesc:
      final int byDue = _dueDesc(a.task.dueAt, b.task.dueAt);
      return byDue != 0 ? byDue : byTitle;
    case ChaoxingSortBy.course:
      final int byCourse = a.task.courseName.compareTo(b.task.courseName);
      if (byCourse != 0) return byCourse;
      final int byDue = _dueAsc(a.task.dueAt, b.task.dueAt);
      return byDue != 0 ? byDue : byTitle;
    case ChaoxingSortBy.status:
      final int byState = kStateOrder
          .indexOf(a.state)
          .compareTo(kStateOrder.indexOf(b.state));
      if (byState != 0) return byState;
      final int byDue = _dueAsc(a.task.dueAt, b.task.dueAt);
      return byDue != 0 ? byDue : byTitle;
    case ChaoxingSortBy.name:
      return byTitle;
  }
}

/// 无截止时间排最后（两种方向都一样，否则「没截止」会顶到最前）。
int _dueAsc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

int _dueDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

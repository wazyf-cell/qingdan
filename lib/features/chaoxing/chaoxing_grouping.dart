/// 学习通面板的视图模型：扩展成品工具栏的四个控件（课程筛选 / 仅看未完成 /
/// 仅看可提交 / 排序）+ 搜索 + 三个页签（全部作业 / 全部考试 / 课堂活动）。
///
/// **来源声明**（AGENTS.md 禁止事项要求逐个文件标注）：筛选与排序的语义取自
/// 用户的油猴脚本 `扩展/作业列表.js`（上游 https://github.com/Cooanyh/chaoxing-list，
/// AGPL-3.0-or-later，作者 lcandy2 / Coren）——排序档位 `sortOptions` :3258-3264、
/// 智能排序（未完成 + 剩余时间短的在上）:3283、默认排序注释 :3352；
/// **考试自成一个列表**（`examItems` :2022，与 `homeworkItems` 并列，视图标题
/// `case 'exam': return '全部考试'` :5044，取数走 `getViewItems` :5056 的独立分支，
/// 仪表盘上还有一张单独的「全部考试」卡片 :5642-5651）——所以这里是三个页签，
/// 不是把考试并进作业。
/// 这里只重写「有哪几个开关、每档叫什么、怎么比、哪页归哪个页签」这层视图语义，
/// 未拷贝其 Vue 模板与遥测代码。
///
/// 语义对齐扩展：「仅看未完成」= 藏掉已完成与已结束；「仅看可提交」= 只留
/// 没过期且没交的（扩展里未提交且未过期才会出现在待办区）。排序选项照抄
/// 脚本 :3258-3265 的五档，默认「截止最早优先」。
library;

import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/import/chaoxing/chaoxing_time.dart';

enum ChaoxingTab {
  homework('全部作业'),
  exam('全部考试'),
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

/// 作业页条目带服务端状态原文，活动页条目不带——这是作业/活动两页签的老分界。
/// 考试页**也带**状态原文（`ks_state` / 作答状态列），所以它必须先按来源页判走，
/// 否则会整页混进「全部作业」（脚本也是各页一个列表：`examItems` :2022 独立于
/// `homeworkItems`，视图标题 `case 'exam': return '全部考试'` :5044）。
List<ChaoxingTask> tasksOfTab(List<ChaoxingTask> tasks, ChaoxingTab tab) =>
    tasks.where((ChaoxingTask t) => tabOf(t) == tab).toList();

/// 一条属于哪个页签（`chaoxing_pane.dart` 与筛选弹层共用这一个判据）。
ChaoxingTab tabOf(ChaoxingTask t) {
  if (t.source == ChaoxingSource.exam) return ChaoxingTab.exam;
  return t.serverStatus != null ? ChaoxingTab.homework : ChaoxingTab.activities;
}

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

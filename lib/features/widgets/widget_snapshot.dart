/// 桌面小组件的数据快照（纯函数，无 IO，可单测）。
///
/// 原生小组件读不懂 Dart 模型，也不该去开 SQLite（schema 一改就崩）；这里只把
/// 「渲染这一屏需要的字段」压成 JSON 字符串，由 `WidgetSnapshotService` 写进
/// SharedPreferences，Kotlin 侧按需截断显示。
///
/// 三条边界：
/// - **只读**：快照没有写回通道，小组件里勾不了任务。
/// - **带日期**：快照记录自己属于哪一天，原生发现不是今天就显示「打开应用」，
///   而不是把昨天的任务挂上「今天」的标题。
/// - **不翻数据**：课程名、任务标题、学习通课程名原样保留。
library;

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/chaoxing/chaoxing_counts.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

const List<String> kWidgetWeekdays = <String>[
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// `2026-10-24`（本地日）。
String widgetDateKey(DateTime now) {
  final DateTime d = now.toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

String _two(int v) => v.toString().padLeft(2, '0');

String _hhmm(int minutes) =>
    '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';

/// 清单 · 今天：与「今天」视图同一口径（未完成、有到期时间、到期早于明天 0 点）。
Map<String, Object?> buildTodaySnapshot({
  required List<Task> allActive,
  required DateTime now,
}) {
  final DateTime todayEnd =
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  final List<Task> today = allActive
      .where((Task t) =>
          !t.completed &&
          t.dueDate != null &&
          t.dueDate!.toLocal().isBefore(todayEnd))
      .toList()
    ..sort((Task a, Task b) => a.dueDate!.compareTo(b.dueDate!));

  return <String, Object?>{
    'v': 1,
    'date': widgetDateKey(now),
    'weekday': kWidgetWeekdays[now.weekday - 1],
    'total': today.length,
    'tasks': <Map<String, Object?>>[
      for (final Task t in today)
        <String, Object?>{
          'id': t.id,
          'title': t.title,
          'due': _hhmm(t.dueDate!.toLocal().hour * 60 +
              t.dueDate!.toLocal().minute),
        },
    ],
  };
}

/// 课表 · 今天。
///
/// [courses] 是已按「今天 + 当前周」过滤好的课；[details] 是该学期作息，
/// 用来把节次换算成起止时间。没有学期 / 学期外都给 `state`，不伪造一屏空白课。
Map<String, Object?> buildCourseSnapshot({
  required Semester? semester,
  required List<Course> courses,
  required List<TimeDetail> details,
  required DateTime now,
}) {
  final String date = widgetDateKey(now);
  final String weekday = kWidgetWeekdays[now.weekday - 1];
  if (semester == null) {
    return <String, Object?>{
      'v': 1,
      'date': date,
      'weekday': weekday,
      'state': 'no_semester',
      'courses': const <Map<String, Object?>>[],
    };
  }
  final int? week = semester.weekOf(now);
  if (week == null) {
    return <String, Object?>{
      'v': 1,
      'date': date,
      'weekday': weekday,
      'state': 'outside_semester',
      'semester': semester.name,
      'courses': const <Map<String, Object?>>[],
    };
  }

  final Map<int, TimeDetail> bySection = <int, TimeDetail>{
    for (final TimeDetail d in details) d.section: d,
  };
  final int nowMinutes = now.hour * 60 + now.minute;
  final List<Course> sorted = List<Course>.of(courses)
    ..sort((Course a, Course b) => a.startSection.compareTo(b.startSection));

  int nextIndex = -1;
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  for (int i = 0; i < sorted.length; i++) {
    final Course c = sorted[i];
    final TimeDetail? start = bySection[c.startSection];
    final TimeDetail? end = bySection[c.endSection];
    final String startText = start == null ? '' : _hhmm(start.startMinutes);
    final String endText = end == null ? '' : _hhmm(end.endMinutes);
    if (nextIndex < 0 && end != null && end.endMinutes > nowMinutes) {
      nextIndex = i;
    }
    rows.add(<String, Object?>{
      'name': c.name,
      'room': c.location ?? '',
      'section': c.startSection == c.endSection
          ? '第 ${c.startSection} 节'
          : '第 ${c.startSection}-${c.endSection} 节',
      'start': startText,
      'end': endText,
      'color': c.colorIndex ?? 0,
    });
  }

  return <String, Object?>{
    'v': 1,
    'date': date,
    'weekday': weekday,
    'state': 'ok',
    'semester': semester.name,
    'week': week,
    'totalWeeks': semester.totalWeeks,
    'nextIndex': nextIndex,
    'courses': rows,
  };
}

/// 学习通 · 待办。与底部角标同一口径：未隐藏、状态仍为待办。
///
/// 数据是**外部快照**，刷新才有；`fetched: false` 时原生要显示「打开应用刷新」，
/// 不能显示成「没有待办」。
Map<String, Object?> buildChaoxingSnapshot({
  required List<ChaoxingTask> tasks,
  required Set<String> hidden,
  required DateTime now,
  required DateTime? fetchedAt,
}) {
  final List<ChaoxingTask> todos = tasks
      .where((ChaoxingTask t) =>
          !hidden.contains(t.key) &&
          t.stateAt(now, done: false) == ChaoxingTaskState.todo)
      .toList()
    ..sort((ChaoxingTask a, ChaoxingTask b) {
      final DateTime? ad = a.dueAt;
      final DateTime? bd = b.dueAt;
      if (ad == null && bd == null) return a.title.compareTo(b.title);
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

  return <String, Object?>{
    'v': 1,
    'date': widgetDateKey(now),
    'fetched': fetchedAt != null,
    'fetchedAt': fetchedAt?.millisecondsSinceEpoch,
    'count': countTodos(
      tasks: tasks,
      hidden: hidden,
      now: now,
      fetched: fetchedAt != null,
    ),
    'dueSoon': countTodos(
      tasks: tasks,
      hidden: hidden,
      now: now,
      fetched: fetchedAt != null,
      within: const Duration(hours: 24),
    ),
    // 没刷过就是「不知道」，连条目也不给：否则小组件会显示一份永远不更新的
    // 旧清单，而且用户看到它之后更不会去应用里刷新。
    'todos': fetchedAt == null
        ? const <Map<String, Object?>>[]
        : <Map<String, Object?>>[
            for (final ChaoxingTask t in todos)
              <String, Object?>{
                'title': t.title,
                'course': t.courseName,
                'kind': t.kind,
                'due': t.dueAt?.millisecondsSinceEpoch,
                // 与课表同一套按课名派生的 8 色，课表里没有的课也能拿到稳定颜色。
                'color': courseColorIndex(t.courseName),
              },
          ],
  };
}

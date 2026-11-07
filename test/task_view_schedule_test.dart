import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/task_view_query.dart';

/// 智能清单成员、顺序与已完成排序（固定 now = 2026-10-26 12:00）。
void main() {
  final DateTime now = DateTime(2026, 10, 26, 12);

  Task t(
    String id, {
    DateTime? start,
    DateTime? due,
    DateTime? end,
    bool completed = false,
    DateTime? completedTime,
    DateTime? modifiedTime,
    int sortOrder = 0,
  }) =>
      Task(
        id: id,
        title: id,
        startDate: start,
        dueDate: due,
        endDate: end,
        completed: completed,
        completedTime: completedTime,
        modifiedTime: modifiedTime,
        sortOrder: sortOrder,
      );

  final Task startToday = t('startToday', start: DateTime(2026, 10, 26, 7));
  final Task dueToday = t('dueToday', due: DateTime(2026, 10, 26, 18));
  final Task startTomorrow = t('startTomorrow', start: DateTime(2026, 10, 27, 7));
  final Task dueLater = t('dueLater', due: DateTime(2026, 11, 3, 7));
  final Task noDate = t('noDate');
  final Task startYesterday = t('startYesterday', start: DateTime(2026, 10, 25, 7));
  final Task done = t('done',
      start: DateTime(2026, 10, 26, 7), completed: true, completedTime: now);
  final List<Task> active = <Task>[
    startToday,
    dueToday,
    startTomorrow,
    dueLater,
    noDate,
    startYesterday,
  ];

  test('今天：开始或截止任一命中；无日期不进', () {
    final List<String> ids = filterForView(kSmartToday, active, now: now)
        .map((Task t) => t.id)
        .toList();
    expect(ids, containsAll(<String>['startToday', 'dueToday', 'startYesterday']));
    expect(ids, isNot(contains('startTomorrow')));
    expect(ids, isNot(contains('dueLater')));
    expect(ids, isNot(contains('noDate')));
  });

  test('最近7天：明天/以后在，8天后不在', () {
    final List<String> ids = filterForView(kSmartNext7, active, now: now)
        .map((Task t) => t.id)
        .toList();
    expect(ids, containsAll(<String>[
      'startToday',
      'dueToday',
      'startTomorrow',
      'startYesterday',
    ]));
    expect(ids, isNot(contains('dueLater')));
  });

  test('所有：无日期也在，已完成不在', () {
    final List<String> ids = filterForView(kSmartAll, <Task>[...active, done], now: now)
        .map((Task t) => t.id)
        .toList();
    expect(ids, contains('noDate'));
    expect(ids, isNot(contains('done')));
  });

  test('已完成：调用方给什么就保留什么', () {
    expect(filterForView(kSmartCompleted, <Task>[done], now: now), <Task>[done]);
  });

  test('今天分组顺序：已过期 → 已开始 → 今天；组内按关注时间', () {
    final List<Task> today = filterForView(kSmartToday, active, now: now);
    final List<String> ids = sortSmartTasks(today, grouped: true, now: now)
        .map((Task t) => t.id)
        .toList();
    expect(ids, <String>['startYesterday', 'startToday', 'dueToday']);
  });

  test('最近7天分组：今天 → 明天 → 以后', () {
    final List<Task> next7 = filterForView(kSmartNext7, active, now: now);
    final List<String> ids = sortSmartTasks(next7, grouped: true, now: now)
        .map((Task t) => t.id)
        .toList();
    // startYesterday 在已开始组；其余按关注时间。
    expect(ids, <String>[
      'startYesterday',
      'startToday',
      'dueToday',
      'startTomorrow',
    ]);
  });

  test('所有视图不分组，按关注时间；无日期排最后', () {
    final List<Task> all = filterForView(kSmartAll, active, now: now);
    final List<String> ids =
        sortSmartTasks(all, grouped: false, now: now).map((Task t) => t.id).toList();
    expect(ids, <String>[
      'startYesterday',
      'startToday',
      'dueToday',
      'startTomorrow',
      'dueLater',
      'noDate',
    ]);
  });

  test('已完成按 completionTime 倒序，缺失回退 modifiedTime', () {
    final List<Task> completed = <Task>[
      t('a', completed: true, completedTime: DateTime(2026, 10, 26, 9)),
      t('b', completed: true, completedTime: DateTime(2026, 10, 26, 11)),
      t('c', completed: true, completedTime: DateTime(2026, 10, 26, 10)),
      t('d', completed: true, modifiedTime: DateTime(2026, 10, 26, 12)),
    ];
    final List<String> ids =
        sortCompletedTasks(completed).map((Task t) => t.id).toList();
    expect(ids, <String>['d', 'b', 'c', 'a']);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/widgets/widget_snapshot.dart';

/// 「清单·今天」小组件跟新规则：开始或截止任一命中；截止时刻优先，否则开始。
void main() {
  final DateTime now = DateTime(2026, 10, 26, 12);

  Task t(
    String id, {
    DateTime? start,
    DateTime? due,
    bool completed = false,
  }) =>
      Task(
        id: id,
        title: id,
        startDate: start,
        dueDate: due,
        completed: completed,
      );

  test('包含开始今天/昨天，排除明天/无日期；截止优先于开始', () {
    final Map<String, Object?> snap = buildTodaySnapshot(
      now: now,
      allActive: <Task>[
        t('startToday', start: DateTime(2026, 10, 26, 7)),
        t('startYesterday', start: DateTime(2026, 10, 25, 7)),
        t('dueToday', due: DateTime(2026, 10, 26, 8)),
        t('both',
            start: DateTime(2026, 10, 26, 7),
            due: DateTime(2026, 10, 26, 9)),
        t('startTomorrow', start: DateTime(2026, 10, 27, 7)),
        t('noDate'),
        t('done',
            start: DateTime(2026, 10, 26, 7), completed: true),
      ],
    );
    final List<Map<String, Object?>> rows =
        (snap['tasks']! as List<Map<String, Object?>>);
    expect(rows.map((Map<String, Object?> r) => r['id']).toList(),
        <String>['startYesterday', 'both', 'startToday', 'dueToday']);
    expect(rows.map((Map<String, Object?> r) => r['due']).toList(),
        <String>['07:00', '09:00', '07:00', '08:00']);
    expect(snap['total'], 4);
  });

  test('只有日期、没有时刻：包含但不显示时刻', () {
    final Map<String, Object?> snap = buildTodaySnapshot(
      now: now,
      allActive: <Task>[
        t('dateOnly', start: DateTime(2026, 10, 26)),
        t('dueDateOnly', due: DateTime(2026, 10, 26)),
      ],
    );
    final List<Map<String, Object?>> rows =
        (snap['tasks']! as List<Map<String, Object?>>);
    expect(rows.map((Map<String, Object?> r) => r['due']).toList(),
        <String>['', '']);
  });

  test('空列表保持完整形状', () {
    final Map<String, Object?> snap =
        buildTodaySnapshot(now: now, allActive: const <Task>[]);
    expect(snap['total'], 0);
    expect(snap['tasks'], isEmpty);
    expect(snap['date'], '2026-10-26');
  });
}

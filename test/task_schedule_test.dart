import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_schedule.dart';

/// 2026-10-26 定案的日期规则：开始/截止任一命中、关注时间、分组、行文案。
/// 固定 now = 2026-10-26 12:00。
void main() {
  final DateTime now = DateTime(2026, 10, 26, 12);

  Task t({
    String title = '任务',
    DateTime? start,
    DateTime? due,
    DateTime? end,
    bool completed = false,
  }) =>
      Task(
        id: title,
        title: title,
        startDate: start,
        dueDate: due,
        endDate: end,
        completed: completed,
      );

  void member(
    String name, {
    DateTime? start,
    DateTime? due,
    DateTime? end,
    bool completed = false,
    required bool today,
    required bool next7,
    required TaskDateGroup group,
    required String? line,
    bool overdue = false,
  }) {
    test(name, () {
      final Task task = t(
          title: name,
          start: start,
          due: due,
          end: end,
          completed: completed);
      expect(inToday(task, now), today, reason: '今天');
      expect(inNext7(task, now), next7, reason: '最近7天');
      expect(groupOf(task, now), group, reason: '分组');
      final ({String? text, bool overdue}) got = taskDateLine(task, now);
      expect(got.text, line, reason: '行文案');
      expect(got.overdue, overdue, reason: '逾期色');
    });
  }

  final DateTime t7 = DateTime(2026, 10, 26, 7);
  final DateTime t18 = DateTime(2026, 10, 26, 18);
  final DateTime t0 = DateTime(2026, 10, 26);
  final DateTime t23 = DateTime(2026, 10, 26, 23, 59);
  final DateTime y7 = DateTime(2026, 10, 25, 7);
  final DateTime y0 = DateTime(2026, 10, 25);
  final DateTime m7 = DateTime(2026, 10, 27, 7);
  final DateTime m0 = DateTime(2026, 10, 27);
  final DateTime p6 = DateTime(2026, 11, 1, 7);
  final DateTime p7 = DateTime(2026, 11, 2);
  final DateTime p8 = DateTime(2026, 11, 3, 7);

  group('成员 / 分组 / 行文案', () {
    member('A1 开始今天07:00', start: t7, today: true, next7: true, group: TaskDateGroup.today, line: '07:00 开始');
    member('A2 开始昨天07:00', start: y7, today: true, next7: true, group: TaskDateGroup.started, line: '10/25 07:00 开始');
    member('A3 开始明天07:00', start: m7, today: false, next7: true, group: TaskDateGroup.tomorrow, line: '明 07:00 开始');
    member('A4 开始11/1', start: p6, today: false, next7: true, group: TaskDateGroup.later, line: '11/1 07:00 开始');
    member('A5 开始11/2（7天边界外）', start: DateTime(2026, 11, 2, 7), today: false, next7: false, group: TaskDateGroup.later, line: '11/2 07:00 开始');
    member('A6 开始11/3', start: p8, today: false, next7: false, group: TaskDateGroup.later, line: '11/3 07:00 开始');
    member('A7 开始今天00:00', start: t0, today: true, next7: true, group: TaskDateGroup.today, line: '今天 开始');
    member('A8 开始今天23:59', start: t23, today: true, next7: true, group: TaskDateGroup.today, line: '23:59 开始');
    member('A9 开始明天00:00', start: m0, today: false, next7: true, group: TaskDateGroup.tomorrow, line: '明天 开始');
    member('A10 截止今天07:00', due: t7, today: true, next7: true, group: TaskDateGroup.overdue, line: '07:00', overdue: true);
    member('A11 截止今天18:00', due: t18, today: true, next7: true, group: TaskDateGroup.today, line: '18:00');
    member('A12 截止今天00:00（日期型）', due: t0, today: true, next7: true, group: TaskDateGroup.today, line: '今天');
    member('A13 截止昨天07:00', due: y7, today: true, next7: true, group: TaskDateGroup.overdue, line: '10/25 07:00', overdue: true);
    member('A14 截止昨天00:00', due: y0, today: true, next7: true, group: TaskDateGroup.overdue, line: '10/25', overdue: true);
    member('A15 截止明天07:00', due: m7, today: false, next7: true, group: TaskDateGroup.tomorrow, line: '明 07:00');
    member('A16 截止明天00:00', due: m0, today: false, next7: true, group: TaskDateGroup.tomorrow, line: '明天');
    member('A17 截止11/1', due: p6, today: false, next7: true, group: TaskDateGroup.later, line: '11/1 07:00');
    member('A18 截止11/2（边界外）', due: p7, today: false, next7: false, group: TaskDateGroup.later, line: '11/2');
    member('A19 截止11/3', due: p8, today: false, next7: false, group: TaskDateGroup.later, line: '11/3 07:00');
    member('A20 开始今天 + 截止明天', start: t7, due: m7, today: true, next7: true, group: TaskDateGroup.today, line: '07:00 开始 · 明 07:00 截止');
    member('A21 开始昨天 + 截止明天', start: y7, due: m7, today: true, next7: true, group: TaskDateGroup.started, line: '10/25 07:00 开始 · 明 07:00 截止');
    member('A22 开始今天 + 截止11/3', start: t7, due: p8, today: true, next7: true, group: TaskDateGroup.today, line: '07:00 开始 · 11/3 07:00 截止');
    member('A23 开始11/3 + 截止今天18:00', start: p8, due: t18, today: true, next7: true, group: TaskDateGroup.today, line: '11/3 07:00 开始 · 18:00 截止');
    member('A24 无日期', today: false, next7: false, group: TaskDateGroup.later, line: null);
    member('A25 开始=截止今天07:00', start: t7, due: t7, today: true, next7: true, group: TaskDateGroup.overdue, line: '07:00', overdue: true);
    member('A26 开始07:00 + 截止18:00', start: t7, due: t18, today: true, next7: true, group: TaskDateGroup.today, line: '07:00 开始 · 18:00 截止');
    member('A27 开始=截止今天00:00', start: t0, due: t0, today: true, next7: true, group: TaskDateGroup.today, line: '今天');
    member('A28 已完成（开始+截止）', start: t7, due: t18, completed: true, today: false, next7: false, group: TaskDateGroup.today, line: '07:00 开始 · 18:00 截止');
    member('A30 开始今天 + 结束09:00', start: t7, end: DateTime(2026, 10, 26, 9), today: true, next7: true, group: TaskDateGroup.today, line: '07:00–09:00');
    member('A31 开始昨天 + 结束09:00', start: y7, end: DateTime(2026, 10, 25, 9), today: true, next7: true, group: TaskDateGroup.started, line: '10/25 07:00–09:00');
    member('A32 开始明天 + 结束09:00', start: m7, end: DateTime(2026, 10, 27, 9), today: false, next7: true, group: TaskDateGroup.tomorrow, line: '明 07:00–09:00');
    member('A33 开始11/3 + 结束09:00', start: p8, end: DateTime(2026, 11, 3, 9), today: false, next7: false, group: TaskDateGroup.later, line: '11/3 07:00–09:00');
    member('A34 开始+结束+截止13:00', start: t7, end: DateTime(2026, 10, 26, 9), due: DateTime(2026, 10, 26, 13), today: true, next7: true, group: TaskDateGroup.today, line: '07:00–09:00 · 截止 13:00');
    member('A35 截止=结束13:00', start: t7, end: DateTime(2026, 10, 26, 13), due: DateTime(2026, 10, 26, 13), today: true, next7: true, group: TaskDateGroup.today, line: '07:00–13:00 截止');
  });

  test('B1 分组顺序：已过期 → 已开始 → 今天 → 明天 → 以后', () {
    final List<TaskDateGroup> groups = <TaskDateGroup>[
      TaskDateGroup.overdue,
      TaskDateGroup.started,
      TaskDateGroup.today,
      TaskDateGroup.tomorrow,
      TaskDateGroup.later,
    ];
    final List<int> ranks = groups.map(groupRank).toList();
    expect(ranks, <int>[0, 1, 2, 3, 4]);
  });

  test('日期型截止今天不标红（Q11）', () {
    expect(dueIsOverdue(t0, now), isFalse);
    expect(dueIsOverdue(y0, now), isTrue);
    expect(dueIsOverdue(DateTime(2026, 10, 26, 7), now), isTrue);
  });

  test('format dateText：今天/明天/其他 + 时刻', () {
    expect(dateText(t7, now), '07:00');
    expect(dateText(t0, now), '今天');
    expect(dateText(m7, now), '明 07:00');
    expect(dateText(m0, now), '明天');
    expect(dateText(p8, now), '11/3 07:00');
    expect(dateText(p7, now), '11/2');
  });
}

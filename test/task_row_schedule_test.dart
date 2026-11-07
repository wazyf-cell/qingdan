import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/tasks/task_row.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 任务行的开始/结束/截止文案；有时间段的行用 56dp 两行，截止型仍 40dp。
void main() {
  final DateTime now = DateTime(2026, 10, 26, 12);

  Future<void> pump(WidgetTester tester, Task task) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: TaskRow(
          task: task,
          now: now,
          onToggle: () {},
          onOpenDetail: () {},
          onDelete: () {},
          onRestore: () {},
          onDeleteForever: () {},
          onChangePriority: (_) {},
          onEditDate: () {},
          onCopyAsText: () {},
          onMoveToList: (_) {},
        ),
      ),
    ));
    await tester.pump();
  }

  Task t(String title,
          {DateTime? start, DateTime? due, DateTime? end, bool completed = false}) =>
      Task(
        id: title,
        title: title,
        startDate: start,
        dueDate: due,
        endDate: end,
        completed: completed,
      );

  testWidgets('只有开始：第二行「07:00 开始」，行高 56',
      (WidgetTester tester) async {
    await pump(tester, t('a', start: DateTime(2026, 10, 26, 7)));
    expect(find.text('07:00 开始'), findsOneWidget);
    expect(tester.getSize(find.byType(TaskRow)).height, 56);
  });

  testWidgets('只有截止：右侧仍显示时刻，行高 40', (WidgetTester tester) async {
    await pump(tester, t('b', due: DateTime(2026, 10, 26, 18)));
    expect(find.text('18:00'), findsOneWidget);
    expect(tester.getSize(find.byType(TaskRow)).height, 40);
  });

  testWidgets('开始 + 截止：同一行两段，行高 56', (WidgetTester tester) async {
    await pump(tester,
        t('c', start: DateTime(2026, 10, 26, 7), due: DateTime(2026, 10, 26, 18)));
    expect(find.text('07:00 开始 · 18:00 截止'), findsOneWidget);
    expect(tester.getSize(find.byType(TaskRow)).height, 56);
  });

  testWidgets('开始 + 结束 + 截止：区间 + 截止', (WidgetTester tester) async {
    await pump(
        tester,
        t('d',
            start: DateTime(2026, 10, 26, 7),
            end: DateTime(2026, 10, 26, 9),
            due: DateTime(2026, 10, 26, 13)));
    expect(find.text('07:00–09:00 · 截止 13:00'), findsOneWidget);
  });

  testWidgets('无日期：不显示日期，行高 40', (WidgetTester tester) async {
    await pump(tester, t('e'));
    expect(find.textContaining('开始'), findsNothing);
    expect(find.textContaining('截止'), findsNothing);
    expect(tester.getSize(find.byType(TaskRow)).height, 40);
  });

  testWidgets('日期型截止今天不标红，已完成截止过去也不标红',
      (WidgetTester tester) async {
    await pump(tester, t('f', due: DateTime(2026, 10, 26)));
    final Text dateOnly = tester.widget<Text>(find.text('今天'));
    expect(dateOnly.style?.color, AppColors.light().textSecondary);

    await pump(tester,
        t('g', due: DateTime(2026, 10, 25, 7), completed: true));
    final Text done = tester.widget<Text>(find.text('10/25 07:00'));
    expect(done.style?.color, AppColors.light().textSecondary);
  });
}

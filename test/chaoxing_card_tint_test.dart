import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_card.dart';
import 'package:qingdan/features/chaoxing/chaoxing_grouping.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 2026-10-26 用户报：作业卡片有红/黄/绿底，考试与课堂活动没有。
/// 根因是着色条件只放行 `todo`，而这两类在开始前是 `notStarted`。
/// 这里直接断言卡片最终画出来的底色与 6dp 竖条，不靠状态函数自证。
final DateTime kNow = DateTime(2026, 10, 26, 12);

ChaoxingTask task({
  required ChaoxingSource source,
  required String kind,
  DateTime? startAt,
  DateTime? dueAt,
  bool ongoing = true,
  String? status = '未提交',
  bool serverDone = false,
}) =>
    ChaoxingTask(
      id: 't1',
      courseId: 'c1',
      courseName: '课程甲',
      title: '条目一',
      kind: kind,
      ongoing: ongoing,
      startAt: startAt,
      dueAt: dueAt,
      source: source,
      serverStatus: status,
      serverDone: serverDone,
    );

Future<BoxDecoration> decorationOf(WidgetTester tester, ChaoxingTask t) async {
  tester.view.physicalSize = const Size(411, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ChaoxingCard(
        row: ChaoxingRow(t, t.stateAt(kNow, done: false)),
        now: kNow,
        onHide: () {},
      ),
    ),
  ));
  final Container box = tester.widget<Container>(find
      .descendant(
          of: find.byType(ChaoxingCard), matching: find.byType(Container))
      .first);
  return box.decoration! as BoxDecoration;
}

void expectTint(BoxDecoration d, Color tint, Color stripe) {
  expect(d.color, tint);
  final Border border = d.border! as Border;
  expect(border.left.color, stripe);
  expect(border.left.width, AppDimens.dueStripeWidth);
}

void expectNoTint(BoxDecoration d) {
  expect(d.color, isNull);
  expect((d.border! as Border).left.color, Colors.transparent);
}

void main() {
  testWidgets('未开始的考试 3 小时内截止 → 红底红条',
      (WidgetTester tester) async {
    final BoxDecoration d = await decorationOf(
        tester,
        task(
            source: ChaoxingSource.exam,
            kind: '考试',
            startAt: kNow.add(const Duration(hours: 1)),
            dueAt: kNow.add(const Duration(hours: 3))));
    expectTint(d, AppColors.light().dueUrgentBg, AppColors.light().overdue);
  });

  testWidgets('未开始的考试 48 小时截止 → 黄底黄条',
      (WidgetTester tester) async {
    final BoxDecoration d = await decorationOf(
        tester,
        task(
            source: ChaoxingSource.exam,
            kind: '考试',
            startAt: kNow.add(const Duration(hours: 1)),
            dueAt: kNow.add(const Duration(hours: 48))));
    expectTint(
        d, AppColors.light().dueNearBg, AppColors.light().priorityMedium);
  });

  testWidgets('未开始的课堂活动 5 天后截止 → 绿底绿条',
      (WidgetTester tester) async {
    final BoxDecoration d = await decorationOf(
        tester,
        task(
            source: ChaoxingSource.activity,
            kind: '签到',
            startAt: kNow.add(const Duration(hours: 1)),
            dueAt: kNow.add(const Duration(days: 5))));
    expectTint(d, AppColors.light().dueSafeBg, AppColors.light().success);
  });

  testWidgets('未开始的作业仍是旧规则：不上色',
      (WidgetTester tester) async {
    final BoxDecoration d = await decorationOf(
        tester,
        task(
            source: ChaoxingSource.homework,
            kind: '作业',
            startAt: kNow.add(const Duration(hours: 1)),
            dueAt: kNow.add(const Duration(hours: 3))));
    expectNoTint(d);
  });

  testWidgets('已结束的考试不上色（红/黄/绿只标还没处理的）',
      (WidgetTester tester) async {
    final BoxDecoration d = await decorationOf(
        tester,
        task(
            source: ChaoxingSource.exam,
            kind: '考试',
            startAt: kNow.subtract(const Duration(days: 2)),
            dueAt: kNow.subtract(const Duration(days: 1))));
    expectNoTint(d);
  });

  testWidgets('进行中的活动保持原有上色', (WidgetTester tester) async {
    final BoxDecoration d = await decorationOf(
        tester,
        task(
            source: ChaoxingSource.activity,
            kind: '签到',
            startAt: kNow.subtract(const Duration(minutes: 30)),
            dueAt: kNow.add(const Duration(hours: 3))));
    expectTint(d, AppColors.light().dueUrgentBg, AppColors.light().overdue);
  });
}

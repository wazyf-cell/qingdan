// 「全部考试」页签的面板级测试：**411dp 与 1280dp 各 pump 一遍**（项目铁律：
// 双端分发的界面两端都要验，S4b 那四处移动端布局缺陷就是只 pump 桌面壳漏掉的）。
//
// 钉四件事：
//  1. 三个页签都在（考试自成一栏，依据脚本 :5044 的视图标题「全部考试」与
//     :5056/:5068 的独立 `examItems`，不是并进「全部作业」）；
//  2. 考试只出现在考试栏，作业栏与活动栏一条不漏进来；
//  3. 用户贴的那场（2026-10-11 22:00 结束，「现在」= 2026-10-19 12:00）：
//     默认栏里是一张标着「已过期」的卡（与扩展 :5674 的已过期档同形），
//     打开「仅看未完成」后**整条从列表消失**——这就是「结束时间已过 → 不进列表」；
//  4. 未登录空态那句「…列出还没交的作业和考试」不再是半真半假：同一个面板上
//     就摆着「全部考试」这一栏。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_grouping.dart';
import 'package:qingdan/features/chaoxing/chaoxing_keys.dart';
import 'package:qingdan/theme/app_colors.dart';
// 扩展方法（setTab 等）不会随 harness 的传递导入进作用域，必须直接 import 模型库。
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_harness.dart';

final DateTime kNow = kCxNow; // 2026-10-18 12:00（夹具的固定钟）

/// 用户那场考试的「已经考完」版本：结束时刻 2026-10-11 22:00，早于固定钟 7 天。
ChaoxingTask endedExam() => cxExam('991',
    courseId: '240000001',
    examId: '991',
    title: '第一次单元测验',
    startAt: DateTime(2026, 10, 11, 8, 0),
    dueAt: DateTime(2026, 10, 11, 22, 0),
    ongoing: false,
    status: '已完成');

ChaoxingTask openExam() => cxExam('992',
    courseId: '240000002',
    examId: '992',
    title: '期中测验',
    startAt: kNow.subtract(const Duration(hours: 1)),
    dueAt: kNow.add(const Duration(hours: 6)),
    status: '未提交');

/// 卡片最终画出来的底色（外层 Container 的 BoxDecoration）。
Color? cardTint(WidgetTester tester, Finder card) {
  final Container box = tester.widget<Container>(find
      .descendant(of: card, matching: find.byType(Container))
      .first);
  return (box.decoration! as BoxDecoration).color;
}

List<ChaoxingTask> mixed() => <ChaoxingTask>[
      cxHomework('h1', dueAt: kNow.add(const Duration(hours: 3))),
      cxActivity('a1', clazzId: 'z1', dueAt: kNow.add(const Duration(hours: 9))),
      endedExam(),
      openExam(),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (String label, double width) in
      <(String, double)>[('手机 411dp', 411), ('桌面 1280dp', 1280)]) {
    testWidgets('$label：三个页签齐，考试只进「全部考试」栏', (WidgetTester tester) async {
      final ChaoxingHarness h = ChaoxingHarness();
      await h.start(tasks: mixed());
      await h.pump(tester, width: width, height: 915);

      expect(h.key(ChaoxingKeys.tabHomework), findsOneWidget);
      expect(h.key(ChaoxingKeys.tabExam), findsOneWidget);
      expect(h.key(ChaoxingKeys.tabActivity), findsOneWidget);
      expect(find.text('全部考试'), findsOneWidget,
          reason: '$label：栏名逐字照脚本 :5044 的视图标题');
      // 默认在作业栏：一条考试都不该漏进来。
      expect(h.cardOf(openExam()), findsNothing);
      expect(h.cardOf(endedExam()), findsNothing);
      expect(h.cardOf(mixed()[0]), findsOneWidget);

      await h.tapIo(tester, h.key(ChaoxingKeys.tabExam));
      expect(h.model.settings.tab, ChaoxingTab.exam);
      expect(h.cardOf(openExam()), findsOneWidget);
      expect(h.cardOf(endedExam()), findsOneWidget);
      expect(h.cardOf(mixed()[0]), findsNothing, reason: '$label：作业不该混进考试栏');
      expect(h.cardOf(mixed()[1]), findsNothing, reason: '$label：活动同理');
      // 2026-10-26：考试卡片要有开始 / 截止两行。
      expect(find.text('开始 10-18 11:00'), findsOneWidget);
      expect(find.textContaining('截止 10-18 18:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label：考完的那场——默认标「已过期」，开「仅看未完成」就消失',
        (WidgetTester tester) async {
      final ChaoxingHarness h = ChaoxingHarness();
      await h.start(tasks: mixed());
      await h.pump(tester, width: width, height: 915);
      await h.tapIo(tester, h.key(ChaoxingKeys.tabExam));

      expect(h.cardOf(endedExam()), findsOneWidget);
      expect(find.textContaining('已过期'), findsOneWidget,
          reason: '$label：卡片必须说实话（扩展 :5674 的已过期档），不再编倒计时');
      expect(find.text('开始 10-11 08:00'), findsOneWidget);
      expect(find.textContaining('截止 10-11 22:00'), findsOneWidget);
      expect(find.textContaining('截止 10-18 18:00（剩'), findsOneWidget,
          reason: '$label：同一栏里还没考完的那条正常显示倒计时');

      await h.tapIo(tester, h.key(ChaoxingKeys.filter));
      await h.tapIo(tester, h.key(ChaoxingKeys.filterUnfinished));
      await h.tapIo(tester, h.key(ChaoxingKeys.filterApply));
      await tester.pumpAndSettle();

      expect(h.model.settings.onlyUnfinished, isTrue);
      expect(h.cardOf(endedExam()), findsNothing,
          reason: '$label：「结束时间已过 → 不进列表」的可执行判据');
      expect(h.cardOf(openExam()), findsOneWidget,
          reason: '同栏里还没考完的那条不受影响，不是整栏空掉');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('未开始的考试/活动在各自页签也带三色底（2026-10-26 用户报）',
      (WidgetTester tester) async {
    final ChaoxingTask upcomingExam = cxExam('994',
        courseId: '240000004',
        examId: '994',
        title: '下周测验',
        startAt: kNow.add(const Duration(hours: 1)),
        dueAt: kNow.add(const Duration(hours: 48)),
        status: '未提交');
    final ChaoxingTask upcomingActivity = ChaoxingTask(
        id: 'a9',
        courseId: '240000005',
        courseName: '课程丙',
        title: '活动9',
        kind: '签到',
        ongoing: true,
        startAt: kNow.add(const Duration(hours: 1)),
        dueAt: kNow.add(const Duration(days: 5)),
        clazzId: 'z9');
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: <ChaoxingTask>[upcomingExam, upcomingActivity]);
    await h.pump(tester, width: 411);

    await h.tapIo(tester, h.key(ChaoxingKeys.tabExam));
    expect(cardTint(tester, h.cardOf(upcomingExam)),
        AppColors.light().dueNearBg);

    await h.tapIo(tester, h.key(ChaoxingKeys.tabActivity));
    expect(cardTint(tester, h.cardOf(upcomingActivity)),
        AppColors.light().dueSafeBg);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未登录空态那句「作业和考试」有对应界面（不许留假承诺）',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: const <ChaoxingTask>[], loggedIn: false);
    await h.pump(tester, width: 411);

    expect(find.text('登录一次超星账号，这里就会列出还没交的作业和考试'), findsOneWidget);
    expect(h.key(ChaoxingKeys.tabExam), findsOneWidget,
        reason: '承诺的那一栏真的在面板上，不是只有作业');
  });

  test('角标只数待办：考完的那场不计入', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: mixed());
    expect(h.model.todoCount, 3, reason: '作业 1 + 活动 1 + 未考的考试 1');
    expect(h.model.dueSoonCount, 3, reason: '三条都还在 24 小时内');
    expect(ChaoxingTab.exam.label, '全部考试');
  });

  test('页签偏好存得回：tabExam 是持久化枚举的第 3 个值', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: mixed());
    await h.model.setTab(ChaoxingTab.exam);
    expect(h.model.settings.tab, ChaoxingTab.exam);
    expect(ChaoxingTab.values.length, 3);
  });
}

// 断点形态与底部角标（自 `mobile_nav_test.dart` 按被测对象拆出，断言一条未改）。
//
// 720–1039dp 图标栏（曾整条不可用：`onTap` 空实现 + 选中态硬编码 + 无设置入口）、
// ≥1040dp 三栏形态不受影响、以及窄屏底部角标的计数与配色（非紧急蓝 / 24 小时内
// 到期红，且设置里可整开关掉）。
//
// 窄屏清单页那一半在 `mobile_nav_shell_test.dart`；共用夹具在
// `mobile_nav_harness.dart`。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/theme/app_colors.dart';

import 'mobile_nav_harness.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late MobileNavHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late SidebarModel sidebar;
  late ChaoxingModel chaoxing;
  late SettingsModel settings;

  setUp(() async {
    h = await MobileNavHarness.open();
    sidebar = h.sidebar;
    chaoxing = h.chaoxing;
    settings = h.settings;
  });

  tearDown(() async => h.close());

  Future<void> pumpAtWidth(WidgetTester tester, double width,
          {String? viewId}) =>
      h.pumpAtWidth(tester, width, viewId: viewId);

  testWidgets('两栏形态图标栏：点击切视图、选中态跟随、设置入口存在',
      (WidgetTester tester) async {
    await pumpAtWidth(tester, 800);

    // 此前图标栏三处不可用：onTap 空实现、selected 硬编码在「今天」、无设置入口。
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    final AppColors colors =
        AppColors.of(tester.element(find.byIcon(Icons.layers_outlined)));
    Color iconColor(IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon)).color!;
    expect(iconColor(Icons.wb_sunny_outlined), colors.accent);
    expect(iconColor(Icons.layers_outlined), isNot(colors.accent));

    await tester.tap(find.byIcon(Icons.layers_outlined));
    await tester.pump();

    expect(sidebar.selectedId, kSmartAll);
    expect(iconColor(Icons.layers_outlined), colors.accent);
    expect(iconColor(Icons.wb_sunny_outlined), isNot(colors.accent));
  });

  testWidgets('三栏形态（≥1040dp）不受影响：无抽屉按钮，标题仍在列表区',
      (WidgetTester tester) async {
    await pumpAtWidth(tester, 1280);

    expect(find.byIcon(Icons.menu), findsNothing);
    expect(topBarTitle, findsNothing);
    expect(paneTitle, findsOneWidget);
    expect(titleOf(tester, paneTitle), '今天');
  });

  testWidgets('底部角标：清单=今天未完成，学习通 24 小时内有到期 → 红底',
      (WidgetTester tester) async {
    List<Badge> badges(WidgetTester tester) => tester
        .widgetList<Badge>(find.descendant(
            of: find.byType(NavigationBar), matching: find.byType(Badge)))
        .toList();
    await pumpAtWidth(tester, 390);

    // 种的那条「买牛奶」今天到期 → 只有清单页签挂一个角标，数字 1。
    expect(badges(tester), hasLength(1));
    expect(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text('1')),
        findsOneWidget);

    final DateTime now = DateTime.now();
    chaoxing.fetchedAt = now;
    chaoxing.tasks = <ChaoxingTask>[
      ChaoxingTask(
          id: 'a1',
          courseId: 'c1',
          courseName: '数据结构',
          title: '第一章作业',
          kind: '作业',
          ongoing: true,
          serverStatus: '未提交',
          dueAt: now.add(const Duration(hours: 6))),
    ];
    // 直接塞字段不会通知；tick() 才是「模型动了一下」的真话（生产里由 refresh 发）。
    chaoxing.tick();
    await tester.pump();

    // 目的地顺序 == ShellTab 声明顺序：[0] 清单、[1] 学习通。
    expect(badges(tester), hasLength(2));
    expect(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text('1')),
        findsNWidgets(2));
    final AppColors shellColors =
        AppColors.of(tester.element(find.byType(NavigationBar)));
    // 两枚角标必须**不同色**：`Badge` 的默认底色就是 error 红，不显式给色的话
    // 「普通计数」和「24 小时内到期」看着一样，红就白给了。
    expect(badges(tester).first.backgroundColor, shellColors.accent);
    expect(badges(tester)[1].backgroundColor, shellColors.overdue,
        reason: '24 小时内有到期必须是红底');

    // 开关关掉：一个角标都不留（定案第 10 条「设置里可关」）。
    await settings.setShowBadges(false);
    await tester.pump();
    expect(badges(tester), isEmpty);
  });
}

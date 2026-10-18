// 窄屏（<720dp）壳形态回归测试 —— 清单页那一半（自 `mobile_nav_test.dart`
// 按被测对象拆出，断言一条未改）。
//
// 缺陷来源：单栏形态只有 `drawer:` 而没有 `AppBar`，Flutter 不会自动生成
// 汉堡按钮，主导航（智能清单/各清单/回收站/设置）只能靠边缘滑动进入，
// Android 真机走查实测用户在手机上完全找不到入口（见 §2.6 顶栏规范）。
//
// 两栏图标栏 / 三栏形态 / 底部角标在 `mobile_nav_breakpoint_badge_test.dart`；
// 共用夹具在 `mobile_nav_harness.dart`。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/task_list_use_case.dart';
import 'package:qingdan/features/shell/placeholder_panes.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';

import 'mobile_nav_harness.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late MobileNavHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late TaskListUseCase listUseCase;

  setUp(() async {
    h = await MobileNavHarness.open();
    listUseCase = h.listUseCase;
  });

  tearDown(() async => h.close());

  Future<void> pumpAtWidth(WidgetTester tester, double width,
          {String? viewId}) =>
      h.pumpAtWidth(tester, width, viewId: viewId);

  testWidgets('窄屏主导航是底部 4 页签：标签常驻可见，不再有抽屉', (WidgetTester tester) async {
    await pumpAtWidth(tester, 390);

    // M5 定案第 1、5 条：窄屏取消抽屉，主导航换成底部 4 页签。
    // 原断言「顶栏有汉堡按钮 → 点开抽屉看到回收站/设置」随形态作废；
    // 汉堡按钮当年是为了救「手机上找不到主导航」而加的，现在底部栏本身就是导航，
    // 再留汉堡就是两套主导航并存。
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final String label in <String>['清单', '学习通', '课表', '设置']) {
      // 只数底部栏里的那一份：M5-S2 起清单页自带「清单 ▾」切换按钮，
      // 按全树文案找会撞成两个。
      expect(
          find.descendant(
              of: find.byType(NavigationBar), matching: find.text(label)),
          findsOneWidget,
          reason: '页签「$label」不可见');
    }
    // §2.6：页标题归 56dp 顶栏（移动 17sp），仍显示当前视图名。
    expect(topBarTitle, findsOneWidget);
    expect(titleOf(tester, topBarTitle), '今天');
  });

  test('页签与视图互相同步：selectedId 仍是唯一真相', () {
    // 这条取代原「抽屉内选完清单后抽屉自动收起」——抽屉没了，
    // 要守住的是「两个状态不打架」这个不变量。
    // 用独立的模型：共享的 `sidebar` 挂着 TaskPaneModel 监听，
    // 切页签会触发查库，而 FakeAsync 区结束后库已被 tearDown 关掉。
    final SidebarModel m = SidebarModel(listUseCase: listUseCase);
    expect(m.tab, ShellTab.tasks);

    m.selectTab(ShellTab.course);
    expect(m.selectedId, kCourseWeek);
    m.selectTab(ShellTab.chaoxing);
    expect(m.selectedId, kChaoxing);

    // 回到「清单」页签要恢复离开前的视图，不该弹回「今天」。
    m.selectTab(ShellTab.tasks);
    expect(m.selectedId, kSmartToday);

    // 设置不是任务视图：切过去不动 selectedId，切回来还是原视图。
    m.select(kSmartAll);
    m.selectTab(ShellTab.settings);
    expect(m.selectedId, kSmartAll);
    m.selectTab(ShellTab.tasks);
    expect(m.selectedId, kSmartAll);

    // 反向：侧栏/快捷键改选中项时，页签跟着投影。
    m.select(kTrash);
    expect(m.tab, ShellTab.tasks);
    m.select(kChaoxing);
    expect(m.tab, ShellTab.chaoxing);
  });

  testWidgets('窄屏不重复渲染标题；右下角「＋」开快捷添加抽屉', (WidgetTester tester) async {
    await pumpAtWidth(tester, 390);

    // 标题只在顶栏出现一次：列表区标题行不得再渲染一遍 20sp 同名标题。
    expect(paneTitle, findsNothing);
    // §2.6 移动线框的右上角箭头与内嵌详情重复 → 不该在。
    expect(find.byIcon(Icons.chevron_left), findsNothing);

    // 2026-10-18 第二轮定案：「＋」开的是**能挑日期 / 优先级 / 清单的抽屉**，
    // 顶部输入框仍是「一行文本 + 自然语言日期」的快建，两者入口不同。
    final Finder fab = find.byKey(const ValueKey<String>('add-task'));
    expect(fab, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('compose-title')), findsNothing);

    await tester.tap(fab);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('compose-title')), findsOneWidget);
    for (final String key in <String>[
      'compose-list',
      'compose-priority',
      'compose-start',
      'compose-due',
      'compose-save',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget,
          reason: '抽屉里缺 $key');
    }
    // 「添加」在未填标题时必须是死的，否则点了就是建一条空标题的任务。
    expect(tester.widget<FilledButton>(
            find.byKey(const ValueKey<String>('compose-save')))
        .onPressed,
        isNull);
  });

  testWidgets('窄屏点任务行推全屏详情页（需求规格书 :172 两级页面）',
      (WidgetTester tester) async {
    await pumpAtWidth(tester, 390);

    await tester.tap(find.text('买牛奶'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(DetailPaneHost), findsOneWidget);
  });

  testWidgets('窄屏回收站工具行不重复页标题，操作项保留', (WidgetTester tester) async {
    await pumpAtWidth(tester, 390, viewId: kTrash);

    expect(paneTitle, findsNothing);
    expect(topBarTitle, findsOneWidget);
    expect(titleOf(tester, topBarTitle), '回收站');
    expect(find.text('清空回收站'), findsOneWidget);
    // 回收站没有快速添加框，「＋」不该跟着过来（2026-10-18 定案第 2 问）。
    expect(find.byKey(const ValueKey<String>('add-task')), findsNothing);
  });
}

// 学期切换面板（M6-D §7.1）：**切换**那一半（自 `semester_switcher_test.dart`
// 按被测对象拆出，断言一条未改）。
//
// 面板列出两个学期、只有当前学期打勾；点另一行 = 切当前学期（顶栏跟着翻、读的
// 是新学期的课、库也真的改了）；手机 411dp 上切换与菜单都可用且不溢出。
//
// 删除学期（确认文案 / 级联 / 「至少保留一个学期」）在
// `semester_switcher_delete_test.dart`；共用夹具在 `semester_switcher_harness.dart`。
// 411dp 与 1280dp 各 pump 一次（总纲铁律 8）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/semester_sheet.dart';

import 'dao_test_helper.dart';
import 'semester_switcher_harness.dart';

void main() {
  ensureSqfliteFfi();

  late SemesterSwitcherHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late Database db;
  late CoursePaneModel model;

  setUp(() async {
    h = await SemesterSwitcherHarness.open();
    db = h.db;
    model = h.model;
  });

  tearDown(() async => h.close());

  Future<void> seedTwoSemesters(WidgetTester tester) =>
      h.seedTwoSemesters(tester);

  Future<void> pumpAt(WidgetTester tester, {required double width}) =>
      h.pumpAt(tester, width: width);

  Future<void> openSheet(WidgetTester tester) => h.openSheet(tester);

  Future<void> openMenu(WidgetTester tester, String id) => h.openMenu(tester, id);

  Future<String> idOf(WidgetTester tester, String name) => h.idOf(tester, name);

  Future<void> settle(WidgetTester tester, {int steps = 12}) =>
      h.settle(tester, steps: steps);

  testWidgets('桌面 1280：面板列出两个学期，只有当前学期打勾', (tester) async {
    await seedTwoSemesters(tester);
    await pumpAt(tester, width: 1280);
    expect(tester.widget<Text>(byKey('semester-switcher-label')).data, 'A 学期');

    await openSheet(tester);
    final String idA = await idOf(tester, 'A 学期');
    final String idB = await idOf(tester, 'B 学期');
    expect(byKey('semester-row-$idA'), findsOneWidget);
    expect(byKey('semester-row-$idB'), findsOneWidget);
    // 「只有一个勾」钉的是**画出来的对勾数量**，不是行数。
    expect(
        find.descendant(
            of: byKey('semester-row-$idA'), matching: find.byIcon(Icons.check)),
        findsOneWidget);
    expect(
        find.descendant(
            of: byKey('semester-row-$idB'), matching: find.byIcon(Icons.check)),
        findsNothing);
  });

  testWidgets('点另一行 = 切当前学期：顶栏跟着翻、读的是新学期的课、库也真的改了',
      (tester) async {
    await seedTwoSemesters(tester);
    await pumpAt(tester, width: 1280);
    await openSheet(tester);
    final String idB = await idOf(tester, 'B 学期');

    await tester.tap(byKey('semester-row-$idB'));
    await tester.pump();
    await settle(tester);
    expect(model.semester?.id, idB, reason: '12 趟往返内没切过去 = 写链卡住了');

    await tester.pumpAndSettle();
    expect(find.byType(SemesterListView), findsNothing,
        reason: '切完必须关面板，留着用户不知道自己在哪个学期');
    expect(weekLabel(tester), '第 5 周 / 共 20 周',
        reason: 'B 学期 08-11 开学，今天 09-08 是第 5 周、共 20 周');
    expect(find.text('大学英语'), findsOneWidget);
    expect(find.text('高等数学'), findsNothing, reason: '周视图只读当前学期的课');
    expect(find.text('已切换到「B 学期」'), findsOneWidget,
        reason: '回执走课表页顶部的行内回执，不是 SnackBar');

    final List<Map<String, Object?>> active = (await io(tester,
        () => db.query('semesters', where: 'is_active = 1')))!;
    expect(active.map((Map<String, Object?> r) => r['id']), <Object?>[idB],
        reason: '库里必须真的换了过去，不是只改了内存对象');

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('手机 411dp：切换与菜单都可用，且不溢出', (tester) async {
    await seedTwoSemesters(tester);
    await pumpAt(tester, width: 411);
    await openSheet(tester);
    final String idB = await idOf(tester, 'B 学期');
    expect(byKey('semester-row-$idB'), findsOneWidget);

    await tester.tap(byKey('semester-row-$idB'));
    await tester.pump();
    await settle(tester);
    await tester.pumpAndSettle();
    expect(model.semester?.id, idB);
    expect(weekLabel(tester), '第 5 周 / 共 20 周');
    expect(tester.takeException(), isNull, reason: '移动端不得有 RenderFlex 溢出');

    // 再开一次面板看 ⋮ 菜单：四个动作都得在 411dp 上排得下。
    await openSheet(tester);
    await openMenu(tester, idB);
    expect(find.text('重命名 / 改开学日期与总周数'), findsOneWidget);
    expect(find.text('把第 5 周设为本周'), findsOneWidget);
    expect(byKey('semester-del-$idB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

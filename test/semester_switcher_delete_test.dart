// 学期切换面板（M6-D §7.1 / §6.1）：**删除**那一半（自
// `semester_switcher_test.dart` 按被测对象拆出，断言一条未改）。
//
// 钉的是删除确认框的连带课程数与「不进回收站、无法撤销」原文、四步级联真的物理
// 删掉课程与作息，以及删到只剩一个学期时删除项禁用 + tooltip。
//
// 切换那一半在 `semester_switcher_switch_test.dart`；共用夹具在
// `semester_switcher_harness.dart`（`seedTwoSemesters` 里 B 学期的「2 门课程」
// 就是确认框要读到的连带数量）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/features/course/semester_sheet.dart';

import 'dao_test_helper.dart';
import 'semester_switcher_harness.dart';

void main() {
  ensureSqfliteFfi();

  late SemesterSwitcherHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late Database db;
  late SemesterUseCase semesters;

  setUp(() async {
    h = await SemesterSwitcherHarness.open();
    db = h.db;
    semesters = h.semesters;
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

  Future<void> settleAndPaint(WidgetTester tester) => h.settleAndPaint(tester);

  testWidgets('删除学期：确认框写连带课程数与「无法撤销」，删完只剩一个学期',
      (tester) async {
    await seedTwoSemesters(tester);
    await pumpAt(tester, width: 1280);
    await openSheet(tester);
    final String idB = await idOf(tester, 'B 学期');

    await openMenu(tester, idB);
    await tester.tap(byKey('semester-del-$idB'));
    // 菜单项点下去后 `_delete` 先查连带课程数（一趟真库往返），确认框是**它回来
    // 之后**才弹的：假时钟区里那个 Future 永远不完成。
    await tester.pump();
    await settle(tester, steps: 4);
    await tester.pumpAndSettle();
    expect(find.text('删除学期「B 学期」？'), findsOneWidget);
    expect(
        find.text('删除学期「B 学期」会同时删除其中 2 门课程与作息，'
            '且不进回收站、无法撤销（回收站只管待办任务）。确定？'),
        findsOneWidget,
        reason: '§6.1 原文：连带数量 + 不进回收站 + 无法撤销');

    await tester.tap(byKey('semester-del-confirm'));
    await tester.pump();
    await settleAndPaint(tester);
    expect(find.text('已删除「B 学期」'), findsOneWidget);
    expect(find.byType(SemesterListView), findsOneWidget,
        reason: '删除的回显在面板里，面板不该自己关掉');

    final List<Semester> rest = (await io(tester, () => semesters.allSemesters()))!;
    expect(rest.map((Semester s) => s.name), <String>['A 学期']);
    expect(rest.single.isActive, isTrue, reason: '删的是非当前学期，当前学期不动');
    expect(
        (await io(tester, () => db.query('courses',
            where: 'semester_id = ?', whereArgs: <Object?>[idB])))!,
        isEmpty,
        reason: '课程与作息必须一起物理删（§6.1 四步级联）');
    expect(await io(tester, () => semesters.courseCountForDeletion(idB)), 0);
  });

  testWidgets('只剩一个学期时删除项禁用并给 tooltip「至少保留一个学期」', (tester) async {
    await seedTwoSemesters(tester);
    await pumpAt(tester, width: 1280);
    await openSheet(tester);
    final String idB = await idOf(tester, 'B 学期');
    await openMenu(tester, idB);
    await tester.tap(byKey('semester-del-$idB'));
    await tester.pump();
    await settle(tester, steps: 4);
    await tester.pumpAndSettle();
    await tester.tap(byKey('semester-del-confirm'));
    await tester.pump();
    await settleAndPaint(tester);

    final String idA = await idOf(tester, 'A 学期');
    await openMenu(tester, idA);
    final PopupMenuItem<String> item =
        tester.widget<PopupMenuItem<String>>(byKey('semester-del-$idA'));
    expect(item.enabled, isFalse,
        reason: '删光了 findActive() 就没学期可读（§6.1）');
    expect(find.byTooltip('至少保留一个学期'), findsOneWidget);
    // 真去点它也不会删（禁用项吞掉点击），库里仍然是 1 个学期。
    await tester.tap(byKey('semester-del-$idA'));
    await tester.pumpAndSettle();
    expect(byKey('semester-del-confirm'), findsNothing);
    expect((await io(tester, () => semesters.allSemesters()))!.length, 1);
  });
}

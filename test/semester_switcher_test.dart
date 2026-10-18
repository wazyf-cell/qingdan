import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/semester_sheet.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// 学期切换面板（M6-D §7.1）：切学期、当前学期只有一个勾、删学期、
/// 删到只剩一个学期时拒删。
///
/// ★ 本项目数据库测试的规矩：碰库的动作一律包 `tester.runAsync`；**按钮在假时钟
/// 区点、动画靠 `pumpAndSettle` 推，然后立刻回 `runAsync` 轮询到写链跑完**才出来
/// ——固定等 400ms 会把事务冻在 BEGIN/COMMIT 之间，`tearDown` 的 `db.close()`
/// 永不返回（见 `course_week_navigation_test.dart` 头部注释）。
/// 411dp 与 1280dp 各 pump 一次（总纲铁律 8）。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late AppServices services;
  late SemesterUseCase semesters;
  late TimetableUseCase templates;
  late CourseUseCase courses;
  late CoursePaneModel model;

  // 固定「今天」= 2025-09-08（周一）。A 学期 08-04 开学 → 今天第 6 周；
  // B 学期 08-11 开学、共 20 周 → 今天第 5 周。两学期的周数不同，切换后顶栏
  // 必须跟着翻，否则等于切了个寂寞。
  final DateTime today = DateTime.utc(2025, 9, 8);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: kLatestSchemaVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await runMigrations(db, fromVersion: 0, toVersion: version);
        },
      ),
    );
    services = AppServices(db: db);
    semesters = SemesterUseCase(services);
    templates = TimetableUseCase(services);
    courses = CourseUseCase(services);
    model = CoursePaneModel(
        semesterUseCase: semesters, courseUseCase: courses, clock: () => today);
  });

  tearDown(() async => db.close());

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  /// 让界面里那条读写链在真实异步区跑完。`sqflite_common_ffi` 对同一个库的操作
  /// **按发起顺序排队**，所以本用例自己连发 [steps] 条查询并等它们返回，就保证
  /// 排在它们前面的那几步（含写事务的 COMMIT）也全落地了；全程留在真实异步区，
  /// 绝不把半截事务带进假时钟。
  Future<void> settle(WidgetTester tester, {int steps = 12}) =>
      io(tester, () async {
        for (int i = 0; i < steps; i++) {
          await semesters.allSemesters();
        }
      });

  /// 链的最后一步是弹层自己那趟「重读列表」，它只在真实异步区里推进；再 settle
  /// 一轮并推帧，回执才会出现在树上。
  Future<void> settleAndPaint(WidgetTester tester) async {
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester, steps: 6);
    await tester.pumpAndSettle();
  }

  Future<String> idOf(WidgetTester tester, String name) async =>
      (await io(tester, () async {
        final List<Semester> all = await semesters.allSemesters();
        return all.firstWhere((Semester s) => s.name == name).id;
      }))!;

  /// 两个学期 + 一张能给网格画出节的默认作息 + A 一门课、B 两门课
  /// （B 的「2 门课程」是删除确认框里要读到的连带数量）。
  Future<void> seedTwoSemesters(WidgetTester tester) =>
      io(tester, () async {
        await semesters.createSemester(
            name: 'A 学期',
            firstWeekDate: DateTime.utc(2025, 8, 4),
            totalWeeks: 16);
        await semesters.createSemester(
            name: 'B 学期',
            firstWeekDate: DateTime.utc(2025, 8, 11),
            totalWeeks: 20,
            setActive: false);
        final String? error = await semesters.saveDefaultTimetable(<TimeDetail>[
          TimeDetail(
              id: '', timetableId: '', section: 1, startMinutes: 480, endMinutes: 525),
          TimeDetail(
              id: '', timetableId: '', section: 2, startMinutes: 535, endMinutes: 580),
        ]);
        expect(error, isNull);
        final List<Semester> all = await semesters.allSemesters();
        final Semester a = all.firstWhere((Semester s) => s.name == 'A 学期');
        final Semester b = all.firstWhere((Semester s) => s.name == 'B 学期');
        await courses.create(
            name: '高等数学',
            weekday: 1,
            startSection: 1,
            endSection: 1,
            weeks: <int>[6],
            semesterId: a.id);
        await courses.create(
            name: '大学英语',
            weekday: 1,
            startSection: 2,
            endSection: 2,
            weeks: <int>[5],
            semesterId: b.id);
        await courses.create(
            name: '补充课',
            weekday: 3,
            startSection: 1,
            endSection: 1,
            weeks: <int>[5],
            semesterId: b.id);
      });

  Future<void> pumpAt(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await io(tester, () => model.load());
    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          Provider<SemesterUseCase>.value(value: semesters),
          Provider<TimetableUseCase>.value(value: templates),
          Provider<CourseUseCase>.value(value: courses),
          ChangeNotifierProvider<CoursePaneModel>.value(value: model),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: CoursePane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder byKey(String k) => find.byKey(ValueKey<String>(k));

  String weekLabel(WidgetTester tester) =>
      tester.widget<Text>(byKey('week-label')).data ?? '';

  /// 打开学期面板：点按钮在假时钟区（入场动画），列表那趟读库必须进真实异步区。
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(byKey('semester-switcher'));
    await tester.pumpAndSettle();
    await settle(tester, steps: 4);
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String id) async {
    await tester.tap(byKey('semester-menu-$id'));
    await tester.pumpAndSettle();
  }

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

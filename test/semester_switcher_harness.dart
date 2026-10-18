// 学期切换面板测试的共用夹具（自 `semester_switcher_test.dart` 拆出；非 `_test`
// 文件，flutter test 不直接执行）。
//
// 拆分后的两份文件：
//  - `semester_switcher_switch_test.dart` —— 列表面板、切当前学期、手机 411dp 形态
//  - `semester_switcher_delete_test.dart` —— 删除学期的确认文案、级联与「至少留一个」
//
// 夹具、等待套路与时序常数字字照搬，未做任何调整。
//
// ★ 本项目数据库测试的规矩：碰库的动作一律包 `tester.runAsync`；**按钮在假时钟
// 区点、动画靠 `pumpAndSettle` 推，然后立刻回 `runAsync` 轮询到写链跑完**才出来
// ——固定等 400ms 会把事务冻在 BEGIN/COMMIT 之间，`tearDown` 的 `db.close()`
// 永不返回（见 `course_week_navigation_test.dart` 头部注释）。
library;

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
import 'package:qingdan/theme/app_theme.dart';

Finder byKey(String k) => find.byKey(ValueKey<String>(k));

String weekLabel(WidgetTester tester) =>
    tester.widget<Text>(byKey('week-label')).data ?? '';

Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
    tester.runAsync<T?>(body);

class SemesterSwitcherHarness {
  SemesterSwitcherHarness();

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

  /// 原 `setUp` 的 body，顺序一字未动。
  static Future<SemesterSwitcherHarness> open() async {
    final SemesterSwitcherHarness h = SemesterSwitcherHarness();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    h.db = await databaseFactory.openDatabase(
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
    h.services = AppServices(db: h.db);
    h.semesters = SemesterUseCase(h.services);
    h.templates = TimetableUseCase(h.services);
    h.courses = CourseUseCase(h.services);
    h.model = CoursePaneModel(
        semesterUseCase: h.semesters,
        courseUseCase: h.courses,
        clock: () => h.today);
    return h;
  }

  Future<void> close() => db.close();

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
}

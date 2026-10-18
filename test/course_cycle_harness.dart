// 同槽循环角标测试的共用夹具（照 `course_grid_test.dart` 的写法抽出来，
// 供 course_cycle_test.dart / course_cycle_geom_test.dart 两份用）。
//
// ★ 坑照抄：testWidgets 里所有碰数据库的动作都必须包 `tester.runAsync`，
//   否则 sqflite 的真实 future 在 FakeAsync 区里永不完成，整条测试**挂死**而不是
//   报错。所以建库放在 `setUp`（不在 FakeAsync 区内，裸 await 安全），
//   测试体内一律走 [CycleHarness.io]。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 环境（真异步区里建好，测试体不直接 await 它）。
class CycleEnv {
  CycleEnv._(this.db, this.semesters, this.courses, this.model);

  final Database db;
  final SemesterUseCase semesters;
  final CourseUseCase courses;
  final CoursePaneModel model;

  // 2025-09-01 周一 = 第 1 周；固定「今天」= 2025-09-08（第 2 周周一）。
  static final DateTime mondayWeek1 = DateTime.utc(2025, 9, 1);
  static final DateTime today = DateTime.utc(2025, 9, 8);

  static Future<CycleEnv> open() async {
    final Database db = await databaseFactory.openDatabase(
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
    final AppServices services = AppServices(db: db);
    final SemesterUseCase semesters = SemesterUseCase(services);
    final CourseUseCase courses = CourseUseCase(services);
    return CycleEnv._(
      db,
      semesters,
      courses,
      CoursePaneModel(
          semesterUseCase: semesters,
          courseUseCase: courses,
          clock: () => today),
    );
  }

  Future<void> close() => db.close();

  /// 三节作息。默认 45 分钟一节、课间 10 分钟（×0.9dp/分钟 → 一节 40.5dp、空档 9dp），
  /// 这样「1-2 节」与「2-3 节」各自的位置与高度都算得清，又能测跨度不等的组。
  ///
  /// [sectionMinutes] / [gapMinutes] 是给「短节次」用例留的口子：**每节时长是自由
  /// 输入**（`timetable_generate_form.dart` 的「每节时长」框走 `_intOf`，
  /// `time_table.dart` 的校验只管 `end > start`），30 分钟、20 分钟一节的作息
  /// 真能落库，块高 = `0.9×分钟 − 2` 会掉到 36dp 以下。
  Future<void> seedSemester({
    int totalWeeks = 4,
    int sectionMinutes = 45,
    int gapMinutes = 10,
  }) async {
    await semesters.createSemester(
        name: '2025-2026-1',
        firstWeekDate: mondayWeek1,
        totalWeeks: totalWeeks);
    final List<TimeDetail> details = <TimeDetail>[];
    int start = 480;
    for (int section = 1; section <= 3; section++) {
      final int end = start + sectionMinutes;
      details.add(_detail(section, start, end));
      start = end + gapMinutes;
    }
    expect(await semesters.saveDefaultTimetable(details), isNull);
  }

  static TimeDetail _detail(int section, int start, int end) => TimeDetail(
      id: '', timetableId: '', section: section, startMinutes: start, endMinutes: end);

  Future<Course> add({
    required String name,
    int weekday = 2,
    int start = 1,
    int end = 2,
    List<int> weeks = const <int>[2],
    String? location,
    String? teacher,
  }) async {
    final Semester? s = await semesters.activeSemester();
    return courses.create(
        name: name,
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: weeks,
        location: location,
        teacher: teacher,
        semesterId: s!.id);
  }
}

/// 测试体这一侧的操作壳：一切查库都过 runAsync。
class CycleHarness {
  CycleHarness(this.tester, this.env);

  final WidgetTester tester;
  final CycleEnv env;

  Future<T?> io<T>(Future<T> Function() body) => tester.runAsync<T>(body);

  Future<void> seed({
    int totalWeeks = 4,
    int sectionMinutes = 45,
    int gapMinutes = 10,
  }) =>
      io(() => env.seedSemester(
          totalWeeks: totalWeeks,
          sectionMinutes: sectionMinutes,
          gapMinutes: gapMinutes));

  Future<Course> add({
    required String name,
    int weekday = 2,
    int start = 1,
    int end = 2,
    List<int> weeks = const <int>[2],
    String? location,
    String? teacher,
  }) async =>
      (await io(() => env.add(
          name: name,
          weekday: weekday,
          start: start,
          end: end,
          weeks: weeks,
          location: location,
          teacher: teacher)))!;

  Future<void> reload() async => await io(() => env.model.load());

  /// 改名但**不换 id**（组身份不变、只是「起始节次→课名」的次序变了）。
  Future<void> rename(Course course, String to) async =>
      await io(() => env.courses.update(course.copyWith(name: to)));

  Future<void> pumpGrid({required double width}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await reload();
    await tester.pumpWidget(
      // 点块本体的那条路要读 `CourseUseCase`（弹层的编辑/删除回调用例层落库），
      // 所以 provider 树得按真实装配给齐，只挂 CoursePaneModel 会 ProviderNotFound。
      MultiProvider(
        providers: <SingleChildWidget>[
          Provider<SemesterUseCase>.value(value: env.semesters),
          Provider<CourseUseCase>.value(value: env.courses),
          ChangeNotifierProvider<CoursePaneModel>.value(value: env.model),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: CoursePane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> goToWeek(int week) async =>
      await io(() => env.model.selectWeek(week));
}

/// 某一门课的块（日列里 key 就是 `block-<id>`）。
Finder blockOf(String courseId) =>
    find.byKey(ValueKey<String>('block-$courseId'));

/// 角标图标本体（14dp glyph）。
Finder cycleIcon() => find.byIcon(Icons.sync_alt);

/// 20dp 圆底。
Finder cycleCircle() => find.byKey(const ValueKey<String>('cycle-badge-circle'));

/// 循环角标的点击热区：Tooltip 的框就是那个 36dp 盒子（= 角标的最外层）。
Finder cycleHitArea() =>
    find.ancestor(of: cycleIcon(), matching: find.byType(Tooltip));

/// 组内计数小字「2/3」。
Finder cycleCounter() =>
    find.byKey(const ValueKey<String>('cycle-counter-text'));

/// 点角标切到组内下一条，并把 200ms 动画推完。
///
/// 三帧各有各的用处，少一帧都会得到「两条都还在树上」的假象：
/// 1. `pump()` —— 让 onTap 的 setState 真正建出新块、退场动画从这一帧才开始计时
///    （`tester.tap` 自己不推进帧）；
/// 2. `pump(220ms)` —— 走完 200ms，旧块的控制器到 dismissed；
/// 3. `pump()` —— AnimatedSwitcher 在下一帧才把摘掉的那条从树上删掉。
Future<void> tapBadge(WidgetTester tester) async {
  await tester.tap(cycleHitArea());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
  await tester.pump();
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_block.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/course_week_header.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// 周视图渲染测试（F31 同槽全显 / F34 今日摘要 / 周末折叠 / 未排时间）。
///
/// ★ 所有碰数据库的动作都必须包在 `tester.runAsync` 里：testWidgets 的函数体
/// 跑在 FakeAsync 区，sqflite 的真实 future 在那个区里永不完成，整条测试会挂死
/// （本文件第一版就栽在这里）。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;

  // 2025-09-01 周一 = 第 1 周；固定「今天」= 2025-09-08（第 2 周周一）。
  final DateTime mondayWeek1 = DateTime.utc(2025, 9, 1);
  final DateTime today = DateTime.utc(2025, 9, 8);

  setUp(() async {
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
    final AppServices services = AppServices(db: db);
    semesters = SemesterUseCase(services);
    courses = CourseUseCase(services);
    model = CoursePaneModel(
        semesterUseCase: semesters,
        courseUseCase: courses,
        clock: () => today);
  });

  tearDown(() async => db.close());

  /// 在真实异步区里跑建数据 / 换周等所有查库动作。
  /// （`runAsync` 的返回类型是可空 Future，超时/未跑完时给 null。）
  Future<T?> io<T>(WidgetTester tester, Future<T> Function() body) =>
      tester.runAsync<T>(body);

  Future<void> seedSemester(WidgetTester tester,
      {int totalWeeks = 4}) async {
    await io(tester, () async {
        await semesters.createSemester(
            name: '2025-2026-1',
            firstWeekDate: mondayWeek1,
            totalWeeks: totalWeeks);
        final String? error =
            await semesters.saveDefaultTimetable(<TimeDetail>[
          TimeDetail(
              id: '',
              timetableId: '',
              section: 1,
              startMinutes: 480,
              endMinutes: 525),
          TimeDetail(
              id: '',
              timetableId: '',
              section: 2,
              startMinutes: 535,
              endMinutes: 580),
        ]);
        expect(error, isNull);
    });
  }

  Future<Course> addCourse(WidgetTester tester,
      {required String name,
      int weekday = 1,
      int start = 1,
      int end = 2,
      List<int> weeks = const <int>[2],
      String? location}) async {
    final Course? created = await io(tester, () async {
      final Semester? s = await semesters.activeSemester();
      return courses.create(
          name: name,
          weekday: weekday,
          startSection: start,
          endSection: end,
          weeks: weeks,
          location: location,
          semesterId: s!.id);
    });
    return created!;
  }

  Future<void> pump(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await io(tester, () => model.load());
    await tester.pumpWidget(
      ChangeNotifierProvider<CoursePaneModel>.value(
        value: model,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: CoursePane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> goToWeek(WidgetTester tester, int week) =>
      io(tester, () => model.selectWeek(week));

  Finder blockOf(String courseId) =>
      find.byKey(ValueKey<String>('block-$courseId'));

  testWidgets('F31：同一时间槽的两门课都渲染，不丢任何一条', (tester) async {
    await seedSemester(tester);
    final Course a =
        await addCourse(tester, name: '线性代数', weekday: 2, start: 1, end: 2);
    final Course b = await addCourse(tester,
        name: '大学英语',
        weekday: 2,
        start: 1,
        end: 2,
        location: '文成楼125');

    await pump(tester, width: 1280);

    expect(blockOf(a.id), findsOneWidget);
    expect(blockOf(b.id), findsOneWidget);
    expect(find.text('线性代数'), findsOneWidget);
    expect(find.text('大学英语'), findsOneWidget);
    // 堆叠：两条各占组跨度的一半，位置必须不同（谁在上取决于 DAO 的
    // `name ASC` 排序，与创建顺序无关，所以只断言「不重叠在同一位置」）。
    expect(tester.getTopLeft(blockOf(a.id)).dy,
        isNot(equals(tester.getTopLeft(blockOf(b.id)).dy)));
    expect(tester.getSize(blockOf(a.id)).height,
        closeTo(tester.getSize(blockOf(b.id)).height, 1e-6));
  });

  testWidgets('周标签与边界禁用：第 1 周禁 ‹、最后一周禁 ›', (tester) async {
    await seedSemester(tester, totalWeeks: 3);
    await pump(tester, width: 1280);

    expect(find.text('第 2 周 / 共 3 周'), findsOneWidget);

    await goToWeek(tester, 1);
    await tester.pumpAndSettle();
    expect(navIcon(tester, Icons.chevron_left).onPressed, isNull,
        reason: '第 1 周不给往前，也不给空周');

    await goToWeek(tester, 3);
    await tester.pumpAndSettle();
    expect(navIcon(tester, Icons.chevron_right).onPressed, isNull);
  });

  testWidgets('今天高亮只在当前周出现，切到别的周就没了', (tester) async {
    await seedSemester(tester);
    await pump(tester, width: 1280);

    expect(find.byKey(const ValueKey<String>('todayPill')), findsOneWidget);

    await goToWeek(tester, 3);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('todayPill')), findsNothing,
        reason: '非当前周不显示今天高亮（细化 §2.5:119）');
    expect(find.text('周一'), findsOneWidget, reason: '普通列头仍在');
  });

  testWidgets('F34：今天在学期内时出现今日摘要条，含时间与地点', (tester) async {
    await seedSemester(tester);
    await addCourse(tester,
        name: '高等数学', weekday: 1, start: 1, end: 2, location: '逸夫楼201');
    await pump(tester, width: 1280);

    expect(find.textContaining('今天 · 周一 9/8 · 1 节：08:00 高等数学@逸夫楼201'),
        findsOneWidget);

    // 界面 §4.1:47 的条件是「今天在学期内」而不是「正在显示本周」：
    // 摘要条说的是今天，翻到第 4 周它仍然成立，只有今天高亮会消失。
    await goToWeek(tester, 4);
    await tester.pumpAndSettle();
    expect(find.textContaining('今天 · 周一 9/8'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('todayPill')), findsNothing);
  });

  testWidgets('节次不在作息表的课进「未排时间」区，不被截断', (tester) async {
    await seedSemester(tester);
    await addCourse(tester, name: '实验课', weekday: 3, start: 13, end: 14);
    await pump(tester, width: 1280);

    expect(find.text('未排时间（1）'), findsOneWidget);
    // ExpansionTile 的 children 只在展开时才构建，先点开再断言。
    await tester.tap(find.text('未排时间（1）'));
    await tester.pumpAndSettle();
    expect(find.text('实验课'), findsOneWidget,
        reason: '课不能因为作息表没这节就消失');
    // 收纳区一行必须带星期（M6-A 收口那轮加的）：一屏十几条时同名课分不清，
    // 而且不带星期就看不出这门课落在哪一天。
    expect(find.text('周三 · 第 13-14 节'), findsOneWidget);
  });

  testWidgets('移动端默认折叠周末，点「周末」展开到 7 列', (tester) async {
    await seedSemester(tester);
    await pump(tester, width: 390);

    expect(find.text('周六'), findsNothing);
    expect(find.text('周五'), findsOneWidget);

    await tester.tap(find.text('周末'));
    await tester.pumpAndSettle();
    expect(find.text('周六'), findsOneWidget);
    expect(find.text('收起周末'), findsOneWidget);
  });

  testWidgets('没有学期时是空态而不是崩', (tester) async {
    await pump(tester, width: 1280);
    expect(find.text('还没有学期，先建一个学期和作息表'), findsOneWidget);
    expect(find.byType(CourseBlock), findsNothing);
  });

  test('weekLabel 纯文案：无学期时不显示「/ 共 0 周」', () {
    expect(weekLabel(2, 16), '第 2 周 / 共 16 周');
    expect(weekLabel(1, 0), '第 1 周');
  });
}

/// 取周导航按钮（‹ ›）。
IconButton navIcon(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(icon), matching: find.byType(IconButton)));

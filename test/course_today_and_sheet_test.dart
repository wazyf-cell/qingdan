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
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_block_sheet.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// M5-S5 漏掉的三条 + 一条真缺陷（2026-10-18 复核）。
///
/// 1. 摘要条 `onTap` 参数一直存在但**没人传**（§2.8:140 点击定位今天）；
/// 2. 今天落在周末时，「定位今天」必须连带展开周末，否则那一列根本不在屏幕上；
/// 3. 学期外「今天」按钮看着能点、点了空转（`todayWeek` 是 0）→ 置灰；
/// 4. 课程块弹层显式限高 60% 屏高 + 可滚动（§2.8:143）。
///
/// ★ 数据库动作一律包 `tester.runAsync`（`course_week_navigation_test.dart` 同一套陷阱）。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late AppServices services;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;

  final DateTime today = DateTime(2026, 10, 18, 9, 50); // 周日
  const List<int> allWeeks = <int>[
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20
  ];

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
    services = AppServices(db: db);
    semesters = SemesterUseCase(services);
    courses = CourseUseCase(services);
    model = CoursePaneModel(
        semesterUseCase: semesters, courseUseCase: courses, clock: () => today);
  });

  tearDown(() async => db.close());

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  /// [firstMonday] 决定今天落在学期内还是外（2026-08-31 → 第 7 周）。
  Future<void> seed(WidgetTester tester, DateTime firstMonday) {
    return io(tester, () async {
      final String id = (await semesters.createSemester(
              name: '2026-2027-1',
              firstWeekDate: firstMonday,
              totalWeeks: 20))
          .id;
      expect(
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
          ]),
          isNull);
      // 今天（周日）有一节课：摘要条要显示节数，且周末折叠时那一列看不见。
      await courses.create(
          name: '选修课',
          weekday: 7,
          startSection: 1,
          endSection: 2,
          weeks: allWeeks,
          location: '航北301',
          semesterId: id);
    });
  }

  Future<void> pumpPane(WidgetTester tester,
      {double width = 411, double height = 900}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<CourseUseCase>.value(value: courses),
        ChangeNotifierProvider<CoursePaneModel>.value(value: model),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: CoursePane()),
      ),
    ));
    await tester.pump();
    await io(tester,
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
  }

  String weekLabel(WidgetTester tester) => tester
          .widget<Text>(find.byKey(const ValueKey<String>('week-label')))
          .data ??
      '';

  TextButton todayButton(WidgetTester tester) =>
      tester.widget<TextButton>(find.widgetWithText(TextButton, '今天'));

  testWidgets('学期外：「今天」置灰（不是看着能点其实空转）', (tester) async {
    await seed(tester, DateTime.utc(2026, 12, 1)); // 今天还没开学
    await pumpPane(tester);

    expect(model.todayInSemester, isFalse);
    expect(weekLabel(tester), '第 1 周 / 共 20 周');
    expect(todayButton(tester).enabled, isFalse,
        reason: 'todayWeek 是 0，点了只会走一次空转的 selectWeek(0)');
    expect(find.textContaining('今天 · 周日'), findsNothing,
        reason: '学期外摘要条整条不渲染（定案：不是灰显）');
  });

  testWidgets('学期内：点摘要条 = 翻到今天那周，并连带展开周末', (tester) async {
    await seed(tester, DateTime.utc(2026, 8, 31)); // 今天 = 第 7 周
    await pumpPane(tester);
    await io(tester, () => model.selectWeek(3));
    await tester.pumpAndSettle();

    expect(weekLabel(tester), '第 3 周 / 共 20 周');
    expect(find.text('周日'), findsNothing, reason: '周末折叠着');
    expect(todayButton(tester).enabled, isTrue);

    await tester.tap(find.textContaining('今天 · 周日'));
    await tester.pumpAndSettle();

    expect(weekLabel(tester), '第 7 周 / 共 20 周');
    expect(model.showWeekend, isTrue,
        reason: '今天是周日，不展开周末就等于没定位到');
    expect(find.text('周日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('课程块弹层：限高 60% 屏高，长内容滚动而不是撑爆', (tester) async {
    tester.view.physicalSize = const Size(411, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Course long = Course(
      id: 'c1',
      uid: 'u1',
      name: '软件质量保证与测试' * 6,
      weekday: 1,
      startSection: 1,
      endSection: 2,
      weeks: allWeeks,
      teacher: '某老师' * 8,
      location: '航北楼实验中心' * 8,
    );
    final SectionLayout layout = layoutSections(<TimeDetail>[
      TimeDetail(
          id: '',
          timetableId: '',
          section: 1,
          startMinutes: 480,
          endMinutes: 525),
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCourseBlockSheet(ctx,
                    course: long, layout: layout, isMobile: true),
                child: const Text('open'),
              ),
            ),
          )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: '不限高不滚动时长内容会把 Column 撑爆');
    final Size shell = tester
        .getSize(find.byKey(const ValueKey<String>('block-sheet-shell')));
    expect(shell.height, lessThanOrEqualTo(640 * 0.6 + 0.5));

    await tester.tap(find.byKey(const ValueKey<String>('block-edit')));
    await tester.pumpAndSettle();
  });
}

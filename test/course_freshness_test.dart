import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_freshness.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'package:qingdan/data/migrations.dart';

import 'dao_test_helper.dart';

/// 顶部「上次更新 / 导入时间」与点开的导入历史（M6-A A8 + M6-D §八 学期维度）。
///
/// v6 给 `import_batches` 补了 `semester_id` 后：
/// * 导进 A 学期的批次**不得**让 B 学期显示「N 分钟前导入」；
/// * 老批次（semester_id NULL）不参与任何学期的导入读数，历史面板里
///   显示「（学期未知）」，不许假装属于当前学期。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late AppServices services;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;
  late String semesterId;

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
    services = AppServices(db: db);
    semesters = SemesterUseCase(services);
    courses = CourseUseCase(services);
    model = CoursePaneModel(
        semesterUseCase: semesters, courseUseCase: courses, clock: () => today);
    semesterId = (await semesters.createSemester(
            name: '2025-2026-1',
            firstWeekDate: DateTime.utc(2025, 8, 4),
            totalWeeks: 16))
        .id;
    await semesters.saveDefaultTimetable(<TimeDetail>[
      TimeDetail(
          id: '', timetableId: '', section: 1, startMinutes: 480, endMinutes: 525),
    ]);
  });

  tearDown(() async => db.close());

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  Future<void> addBatch(WidgetTester tester, ImportBatch batch,
          {String? semesterId}) =>
      io(tester,
          () => services.courseDao.insertBatch(batch, semesterId: semesterId));

  Future<void> pumpAt(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 先 seed 再 load：反过来这一行读到的是空库（项目踩过的坑）。
    await io(tester, () => model.load());
    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          Provider<SemesterUseCase>.value(value: semesters),
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

  String freshnessText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey<String>('course-freshness'))).data ??
      '';

  testWidgets('导入过（本学期批次）：那一行写「导入 · 文件名」，点开能看到批次',
      (tester) async {
    await addBatch(tester,
        ImportBatch(
            id: 'b1',
            fileName: '本学期.csv',
            importedAt: DateTime.utc(2025, 9, 7, 6, 32),
            countImported: 5,
            countUpdated: 1,
            countSkipped: 2),
        semesterId: semesterId);
    await pumpAt(tester, width: 1280);

    expect(freshnessText(tester), contains('导入'));
    expect(freshnessText(tester), contains('本学期.csv'));

    await tester.tap(find.byKey(const ValueKey<String>('course-freshness-tap')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('import-batch-b1')), findsOneWidget);
    expect(find.textContaining('新增 5'), findsOneWidget);
    expect(find.textContaining('跳过 2'), findsOneWidget);
    // 历史面板每条标注归属：这条是本学期（2025-2026-1）的批次。
    expect(find.textContaining('2025-2026-1'), findsWidgets);
  });

  testWidgets('没导入但手改过课：那一行写「更新」', (tester) async {
    await io(tester, () => courses.create(
        name: '高等数学',
        weekday: 1,
        startSection: 1,
        endSection: 1,
        weeks: const <int>[5],
        semesterId: semesterId));
    await pumpAt(tester, width: 1280);

    expect(freshnessText(tester), contains('更新'));
    expect(freshnessText(tester), isNot(contains('导入')));
  });

  testWidgets('全新库（没课也没导入）：整行不渲染', (tester) async {
    await pumpAt(tester, width: 1280);
    expect(find.byKey(const ValueKey<String>('course-freshness')), findsNothing);
  });

  test('导进 A 学期的批次不得让 B 学期显示「导入」（§八 学期维度）', () async {
    final String bId = (await semesters.createSemester(
            name: '第二学期',
            firstWeekDate: DateTime.utc(2025, 2, 2),
            totalWeeks: 16,
            setActive: false))
        .id;
    await services.courseDao.insertBatch(
        ImportBatch(
            id: 'only-a',
            fileName: 'A的课表.csv',
            importedAt: DateTime.utc(2025, 9, 7, 6, 32)),
        semesterId: semesterId);

    final CourseFreshness onB = await courses.freshness(bId);
    expect(onB.kind, isNot(CourseFreshnessKind.import),
        reason: 'B 学期没导过：哪怕只查了学期名，也不能借用 A 的导入时刻');
    final CourseFreshness onA = await courses.freshness(semesterId);
    expect(onA.kind, CourseFreshnessKind.import);
    expect(onA.fileName, 'A的课表.csv');
  });

  testWidgets('老批次（semester_id NULL）：不算导入读数，历史面板显示「（学期未知）」',
      (tester) async {
    await services.courseDao.insertBatch(ImportBatch(
        id: 'legacy',
        fileName: 'v6 前的导入.csv',
        importedAt: DateTime.utc(2025, 9, 7)));
    // 造一条「更新」：没有它整行不渲染，历史面板无从点开。
    await courses.create(
        name: '高等数学',
        weekday: 1,
        startSection: 1,
        endSection: 1,
        weeks: const <int>[5],
        semesterId: semesterId);
    await pumpAt(tester, width: 1280);

    expect(freshnessText(tester), contains('更新'),
        reason: '归属未知的老批次不许伪装成本学期的「导入」');
    expect(freshnessText(tester), isNot(contains('导入')));

    await tester.tap(find.byKey(const ValueKey<String>('course-freshness-tap')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('import-batch-legacy')),
        findsOneWidget);
    expect(find.textContaining('（学期未知）'), findsOneWidget);
  });

  testWidgets('历史面板的行数 = 批次条数（只留最近 10 次）', (tester) async {
    for (int i = 1; i <= 12; i++) {
      await addBatch(tester,
          ImportBatch(
              id: 'b$i',
              fileName: '第$i份.csv',
              importedAt: DateTime.utc(2025, 9, 1).add(Duration(days: i))),
          semesterId: semesterId);
    }
    await pumpAt(tester, width: 411);
    expect(freshnessText(tester), contains('导入'));

    await tester.tap(find.byKey(const ValueKey<String>('course-freshness-tap')));
    await tester.pumpAndSettle();
    for (int i = 3; i <= 12; i++) {
      expect(find.byKey(ValueKey<String>('import-batch-b$i')), findsOneWidget,
          reason: '第 $i 批应在最近 10 次里');
    }
    for (int i = 1; i <= 2; i++) {
      expect(find.byKey(ValueKey<String>('import-batch-b$i')), findsNothing,
          reason: '早于最近 10 次的不得出现在面板里');
    }
  });
}

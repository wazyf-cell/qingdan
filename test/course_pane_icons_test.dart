import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'package:qingdan/data/migrations.dart';

import 'dao_test_helper.dart';

/// 导入按钮的箭头方向（M6-A A7）。
///
/// 这条本身 trivial，但它是用户明确要求的可见行为：没有断言钉着，将来重构
/// 一定会被改回 `file_upload_outlined`（「上传」看起来更「像导入」）。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;

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
        semesterUseCase: semesters, courseUseCase: courses, clock: () => today);
    await semesters.createSemester(
        name: '2025-2026-1',
        firstWeekDate: DateTime.utc(2025, 8, 4),
        totalWeeks: 16);
    await semesters.saveDefaultTimetable(<TimeDetail>[
      TimeDetail(
          id: '', timetableId: '', section: 1, startMinutes: 480, endMinutes: 525),
    ]);
  });

  tearDown(() async => db.close());

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  Future<void> pumpAt(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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

  Icon iconOf(WidgetTester tester, String key) => tester.widget<Icon>(
      find.descendant(
          of: find.byKey(ValueKey<String>(key)), matching: find.byType(Icon)));

  Future<void> openSetup(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('btn-setup')));
    await tester.pumpAndSettle();
  }

  /// 弹层里朝上的箭头**只允许有一个，而且必须挂在导出那一行**（M6-D §9.2 的近路）。
  /// 原来的断言是「一个朝上的都没有」，导出接进来之后那句话已经不成立了。
  void expectSingleUpArrowIsExport(WidgetTester tester) {
    expect(iconOf(tester, 'setup-export').icon, Icons.file_upload_outlined,
        reason: '导出 = 数据出应用，箭头朝上（与导入相反）');
    expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget,
        reason: '除了导出那行，弹层里不许再有第二处朝上的：那说明某处导入还没改过来');
  }

  testWidgets('桌面 1280：头部与「学期与作息」里的导入箭头都朝下', (tester) async {
    await pumpAt(tester, width: 1280);

    expect(iconOf(tester, 'btn-import').icon, Icons.file_download_outlined,
        reason: '导入 = 数据进应用，箭头必须朝下');
    await openSetup(tester);
    expect(iconOf(tester, 'setup-import').icon, Icons.file_download_outlined);
    expectSingleUpArrowIsExport(tester);
  });

  testWidgets('手机 411：头部不给导入按钮（既有定案），弹层里那个朝下',
      (tester) async {
    await pumpAt(tester, width: 411);

    expect(find.byKey(const ValueKey<String>('btn-import')), findsNothing,
        reason: '411dp 头部一行已经排满，导入改从「学期与作息」进');
    await openSetup(tester);
    expect(iconOf(tester, 'setup-import').icon, Icons.file_download_outlined);
    expectSingleUpArrowIsExport(tester);
  });
}

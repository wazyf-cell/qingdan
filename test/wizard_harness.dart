// 导入向导测试的共享管线：真实内存库 + 打开向导 + 「点会查库的按钮」的套路。
//
// 两个向导测试文件都用它（端到端主路径 / 批量操作），因为踩过的坑是一样的：
// 建帧与等待必须留在 `tester.runAsync` 区内，否则步 3 的 initState 查库与
// PopupMenu 的 await 续体永远冲不出来。

import 'dart:convert';
import 'dart:typed_data';

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
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/import_wizard/import_wizard.dart';
import 'package:qingdan/features/course/import_wizard/wizard_file_picker.dart';
import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/theme/app_theme.dart';

class WizardHarness {
  WizardHarness._(this.db, this.services, this.pane);

  final Database db;
  final AppServices services;
  final CoursePaneModel pane;

  late final SemesterUseCase semesters = SemesterUseCase(services);
  late final CourseUseCase courses = CourseUseCase(services);
  late final ImportService importer = ImportService(services.courseDao);

  /// 默认备好一个 16 周学期 + 12 节作息：步 3 只负责展示，不是验证点。
  static Future<WizardHarness> open({
    bool withSemester = true,
    int totalWeeks = 16,
  }) async {
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
    final WizardHarness h = WizardHarness._(
        db, services, CoursePaneModel(
            semesterUseCase: SemesterUseCase(services),
            courseUseCase: CourseUseCase(services)));
    if (withSemester) {
      await h.semesters.createSemester(
          name: '2025-2026-1',
          firstWeekDate: DateTime(2025, 9, 1),
          totalWeeks: totalWeeks);
      await h.semesters.saveDefaultTimetable(generateTimeDetails(
          timetableId: '',
          firstStartMinutes: 480,
          lessonMinutes: 45,
          breakMinutes: 10,
          sectionCount: 12));
      await h.pane.load();
    }
    return h;
  }

  Future<void> close() => db.close();

  Future<List<Course>> activeCourses() => courses.activeCourses();

  ScheduleFileLoader loader(Uint8List bytes, {String name = '课表.xlsx'}) =>
      () async => (name: name, bytes: bytes);

  ScheduleFileLoader csvLoader(String csv, {String name = '课表.csv'}) =>
      loader(Uint8List.fromList(utf8.encode(csv)), name: name);

  Future<void> pumpWizard(WidgetTester tester,
      {required double width, required ScheduleFileLoader loadFile}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<CourseUseCase>.value(value: courses),
        Provider<ImportService>.value(value: importer),
        ChangeNotifierProvider<CoursePaneModel>.value(value: pane),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: Builder(builder: (BuildContext ctx) => TextButton(
                  key: const ValueKey<String>('open-wizard'),
                  onPressed: () => showImportWizard(ctx, loadFile: loadFile),
                  child: const Text('open'),
                )),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('open-wizard')));
    await tester.pumpAndSettle();
  }

  /// 点一个会触发查库/路由动画回调的控件：tap、建帧、等待都在真实异步区里。
  Future<void> tapIo(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await tester.pump();
    });
    await tester.pump();
  }

  /// 长按**不能**放进 `runAsync`：那里的假时钟不推进 kLongPressTimeout，
  /// 识别器只见到一次单击，于是行的 onTap（打开编辑抽屉）抢先触发（实测）。
  Future<void> longPressIo(WidgetTester tester, Finder finder) async {
    await tester.longPress(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) =>
      tapIo(tester, find.byKey(ValueKey<String>(key)));

  Future<void> tapText(WidgetTester tester, String text) =>
      tapIo(tester, find.text(text));

  Future<void> next(WidgetTester tester) => tapKey(tester, 'wizard-next');

  /// 步 2 → 步 4（调用方自己先选过文件）。每步都断言，卡在哪步报哪步。
  Future<void> driveToCorrection(WidgetTester tester) async {
    await next(tester);
    expect(find.byKey(const ValueKey<String>('map-0')), findsOneWidget,
        reason: '没走到步 2（列映射）');
    await next(tester);
    expect(find.byKey(const ValueKey<String>('semester-save')), findsOneWidget,
        reason: '没走到步 3（学期与作息）');
    await next(tester);
    expect(find.byKey(const ValueKey<String>('gate-banner')), findsOneWidget,
        reason: '没走到步 4（校正）');
  }
}

/// 七列模板的 CSV 文本；[rows] 每行给 7 个单元格。
String scheduleCsv(List<List<String>> rows) {
  const String header =
      '课程名称,星期,开始节数,结束节数,老师,地点,周数';
  return '$header\n${rows.map((List<String> r) => r.join(',')).join('\n')}\n';
}

List<String> cells({
  String name = '高等数学',
  String weekday = '1',
  String start = '1',
  String end = '2',
  String teacher = '小明',
  String location = '逸夫楼201',
  String weeks = '1-5',
}) =>
    <String>[name, weekday, start, end, teacher, location, weeks];

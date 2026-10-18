// 导入向导端到端测试的共用夹具（自 `import_wizard_test.dart` 拆出；非 `_test`
// 文件，flutter test 不直接执行）。
//
// 拆分后的两份文件：
//  - `import_wizard_e2e_test.dart` —— 桌面 1280 / 移动 411 的双形态主路径
//  - `import_wizard_gate_correction_test.dart` —— 闸门、步 3 导入目标学期、回跳作废
//
// 夹具与等待时长**逐字照搬原文件**（260ms 那一档）。不复用 `wizard_harness.dart`：
// 那份是批量操作用的 280ms 档，混用等于偷偷改动原用例的时序。
//
// ★ 本项目踩过的坑：建帧与等待必须留在 `tester.runAsync` 区内——步 3 的 `initState`
// 会发一次查库，若它在 FakeAsync 区里创建，那个 future 的续体永远等不到真实事件循环；
// `PopupMenuButton.onSelected` 跑在路由 pop 的 await 续体里，同理。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/import_wizard/import_wizard.dart';
import 'package:qingdan/features/course/import_wizard/wizard_file_picker.dart';
import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/theme/app_theme.dart';

const String kImportSamplePath = '相关来源或素材/课表模板.xlsx';

class ImportWizardHarness {
  ImportWizardHarness();

  late Database db;
  late AppServices services;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late TimetableUseCase timetables;
  late ImportService importer;
  late CoursePaneModel pane;
  late Uint8List xlsxBytes;

  /// 原 `setUp` 的-body，顺序一字未动。
  static Future<ImportWizardHarness> open() async {
    final ImportWizardHarness h = ImportWizardHarness();
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
    h.courses = CourseUseCase(h.services);
    h.timetables = TimetableUseCase(h.services);
    h.importer = ImportService(h.services.courseDao);
    h.pane = CoursePaneModel(
        semesterUseCase: h.semesters, courseUseCase: h.courses);
    // 学期与 12 节作息先备好：步 3 只负责展示与改，不是本用例的验证点。
    final Semester seeded = await h.semesters.createSemester(
        name: '2025-2026-1',
        firstWeekDate: DateTime(2025, 9, 1),
        totalWeeks: 16);
    // 节次写进**这个学期自己的**作息表（读路径 2026-10-19 起按学期）。
    await h.semesters.saveDetailsForSemester(seeded.id, generateTimeDetails(
        timetableId: '',
        firstStartMinutes: 480,
        lessonMinutes: 45,
        breakMinutes: 10,
        sectionCount: 12));
    await h.pane.load();
    h.xlsxBytes = File(kImportSamplePath).readAsBytesSync();
    return h;
  }

  Future<void> close() => db.close();

  ScheduleFileLoader loader(Uint8List bytes, {String name = '课表模板.xlsx'}) =>
      () async => (name: name, bytes: bytes);

  Future<void> openWizard(WidgetTester tester,
      {required double width, required ScheduleFileLoader loadFile}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<CourseUseCase>.value(value: courses),
        // 步 3 的「换成某个模板」两选读它（M6-D §7.5）。
        Provider<TimetableUseCase>.value(value: timetables),
        Provider<ImportService>.value(value: importer),
        ChangeNotifierProvider<CoursePaneModel>.value(value: pane),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: Builder(builder: (BuildContext ctx) => TextButton(
                  key: const ValueKey<String>('open-wizard'),
                  onPressed: () =>
                      showImportWizard(ctx, loadFile: loadFile),
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

  /// 点一个会触发查库的按钮：tap、建帧、等待**全在真实异步区里**做。
  /// 建帧必须留在 runAsync 内——步 3 的 `initState` 会发一次查库，若它在
  /// FakeAsync 区里创建，那个 future 的续体永远等不到真实事件循环。
  Future<void> tapIo(WidgetTester tester, String key) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      await tester.pump();
    });
    await tester.pump();
  }

  Future<void> next(WidgetTester tester) => tapIo(tester, 'wizard-next');

  /// 点菜单项/对话框按钮：`PopupMenuButton.onSelected` 是在路由 pop 的 await
  /// 续体里回调的，FakeAsync 区内 pumpAndSettle 冲不出来，必须在真实异步区里
  /// 点并等（实测：不加 runAsync 时回调晚于整条断言，测试假失败）。
  Future<void> tapTextIo(WidgetTester tester, String text) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(text));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      await tester.pump();
    });
    await tester.pump();
  }

  Future<List<Course>> readCourses(WidgetTester tester) async {
    late List<Course> rows;
    await tester.runAsync(() async => rows = await courses.activeCourses());
    return rows;
  }

  /// 步 2 → 步 4（调用方自己先选过文件）。每步都断言到位，卡在哪步就报哪步。
  Future<void> driveToCorrection(WidgetTester tester) async {
    await next(tester); // → 步 2
    expect(find.byKey(const ValueKey<String>('map-0')), findsOneWidget,
        reason: '没走到步 2（列映射）');
    await next(tester); // → 步 3
    expect(find.byKey(const ValueKey<String>('semester-save')), findsOneWidget,
        reason: '没走到步 3（学期与作息）');
    await next(tester); // → 步 4
    expect(find.byKey(const ValueKey<String>('gate-banner')), findsOneWidget,
        reason: '没走到步 4（校正）');
  }
}

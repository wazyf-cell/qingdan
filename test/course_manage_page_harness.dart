import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/features/course/course_manage_page.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// `course_manage_page_test.dart` 的夹具：真实内存库 + 课表域三个用例 + 周视图模型，
/// 外加「点一下并让写链在真实异步区跑完」这套点法。
///
/// 单独成文件只为守行数红线（单一源码文件 ≤300 行），语义与搬走前一字不差。
class ManageHarness {
  ManageHarness._(
      this.env, this.semesters, this.templates, this.courses, this.importer, this.model);

  final DaoTestDb env;
  final SemesterUseCase semesters;
  final TimetableUseCase templates;
  final CourseUseCase courses;
  final ImportService importer;
  final CoursePaneModel model;

  static Future<ManageHarness> create() async {
    SharedPreferences.setMockInitialValues(<String, Object>{}); // 模板库读 prefs
    final DaoTestDb env = await DaoTestDb.open();
    final AppServices services = AppServices(db: env.db);
    final SemesterUseCase semesters = SemesterUseCase(services);
    final TimetableUseCase templates = TimetableUseCase(services);
    final CourseUseCase courses = CourseUseCase(services);
    final ImportService importer = ImportService(services.courseDao);
    // 固定「今天」= 2025-09-08（周一）：A 学期 08-04 开学 = 第 6 周。
    final CoursePaneModel model = CoursePaneModel(
        semesterUseCase: semesters,
        courseUseCase: courses,
        clock: () => DateTime.utc(2025, 9, 8));
    return ManageHarness._(env, semesters, templates, courses, importer, model);
  }

  Future<void> close() => env.close();

  double heightOf(double width) => width < 720 ? 915 : 1400;
  Finder key(String k) => find.byKey(ValueKey<String>(k));

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  /// 让界面里那条读写链在真实异步区跑完：同一个库的 sqflite 操作按发起顺序排队，
  /// 自己连发 [steps] 趟查询并等回来，前面的写事务（含 COMMIT）也就落了。
  Future<void> settle(WidgetTester tester, {int steps = 12}) =>
      io(tester, () async {
        for (int i = 0; i < steps; i++) {
          await semesters.allSemesters();
        }
      });

  Future<String> idOf(WidgetTester tester, String name) async {
    final List<Semester> all = (await io(tester, semesters.allSemesters))!;
    return all.firstWhere((Semester s) => s.name == name).id;
  }

  /// 两个学期：A 是当前学期（该带勾），B 不是（该被切过去）。
  Future<void> seed(WidgetTester tester) => io(tester, () async {
        await semesters.createSemester(
            name: 'A 学期', firstWeekDate: DateTime.utc(2025, 8, 4));
        await semesters.createSemester(
            name: 'B 学期',
            firstWeekDate: DateTime.utc(2025, 8, 11),
            setActive: false);
        await model.load();
      });

  Future<void> pumpShell(WidgetTester tester, double width,
      {required Future<void> Function(BuildContext ctx) open}) async {
    tester.view.physicalSize = Size(width, heightOf(width));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<TimetableUseCase>.value(value: templates),
        Provider<CourseUseCase>.value(value: courses),
        // 向导外壳从 provider 树里读 ImportService（UI 不碰 DAO）。
        Provider<ImportService>.value(value: importer),
        ChangeNotifierProvider<CoursePaneModel>.value(value: model),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: Center(
                child: Builder(
                    builder: (BuildContext ctx) => TextButton(
                        key: const ValueKey<String>('open-shell'),
                        onPressed: () => open(ctx),
                        child: const Text('open'))))),
      ),
    ));
    await tester.pump();
  }

  Future<void> openManage(WidgetTester tester, double width) =>
      pumpShell(tester, width, open: showCourseManagePage);

  /// tap、建帧、等待全在真实异步区：新页首帧要读库（学期列表 + 模板库 load）。
  Future<void> tapIo(WidgetTester tester, String k) async {
    await tester.runAsync(() async {
      await tester.tap(key(k));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    await settle(tester, steps: 6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> popTop(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester, steps: 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }
}

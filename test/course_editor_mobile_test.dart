// 移动端课程编辑抽屉的两条真机缺陷回归（S4b 在 411dp 真机上抓到）。
//
// ① 星期 + 起始节 + 结束节挤一行时两个 stepper 各溢出 8.3dp；
// ② 键盘弹出后「保存」落在 IME 底下，点不到。
// 首版 F28 端到端测试跑的是 1280dp 桌面壳，所以这两条在手机上一直没被覆盖。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/features/course/course_day_axis.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/course_setup.dart';
import 'package:qingdan/features/course/course_week_header.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

DateTime _dateOf(int weekday) =>
    DateTime(2026, 10, 5).add(Duration(days: weekday - 1));

void main() {
  ensureSqfliteFfi();

  late Database db;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;

  const double screenH = 900;
  const double keyboardH = 300;

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
    model = CoursePaneModel(semesterUseCase: semesters, courseUseCase: courses);
    await semesters.createSemester(
        name: '2026-2027-1',
        firstWeekDate: DateTime(2026, 10, 5),
        totalWeeks: 16);
    await model.load();
  });

  tearDown(() async => db.close());

  Future<void> pumpMobileEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, screenH);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SemesterUseCase>.value(value: semesters),
          Provider<CourseUseCase>.value(value: courses),
          ChangeNotifierProvider<CoursePaneModel>.value(value: model),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: Builder(builder: (BuildContext ctx) => TextButton(
                    key: const ValueKey<String>('open-editor'),
                    onPressed: () =>
                        showCourseEditor(ctx,
                        isMobile: true,
                        totalWeeks: 16,
                        maxSection: 12),
                    child: const Text('open'),
                  )),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('open-editor')));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  }

  testWidgets('手机 411dp：星期独占一行，两个节次 stepper 落在下一行不溢出',
      (tester) async {
    await pumpMobileEditor(tester);

    // 溢出会以 RenderFlex overflowed 抛错直接让本用例红；这里再断言换行真的发生。
    final Rect weekday =
        tester.getRect(find.byKey(const ValueKey<String>('field-weekday')));
    final Rect start =
        tester.getRect(find.byKey(const ValueKey<String>('field-start')));
    final Rect end =
        tester.getRect(find.byKey(const ValueKey<String>('field-end')));
    expect(weekday.bottom, lessThanOrEqualTo(start.top + 1),
        reason: '星期在 stepper 上方，说明移动端走了两行布局');
    expect(start.top, end.top, reason: '两个 stepper 同一行');
    expect(start.right, lessThanOrEqualTo(end.left),
        reason: '两个 stepper 不重叠');
  });

  testWidgets('键盘弹出后「保存」仍在键盘上方可滚到（不被 IME 盖住）',
      (tester) async {
    await pumpMobileEditor(tester);

    tester.view.viewInsets =
        const FakeViewPadding(bottom: keyboardH);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final Rect sheet =
        tester.getRect(find.byType(DraggableScrollableSheet));
    expect(sheet.bottom, lessThanOrEqualTo(screenH - keyboardH + 1),
        reason: '抽屉必须让出键盘高度，否则里面的按钮永远点不到');

    final Finder save = find.byKey(const ValueKey<String>('btn-save'));
    await tester.dragUntilVisible(
      save,
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(screenH - keyboardH + 1),
        reason: '滚到底后保存键完整落在键盘之上');
  });

  testWidgets('手机 411dp：周次标签不换行，第二行不压到星期轴上', (tester) async {
    tester.view.physicalSize = const Size(411, screenH);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Column(
            children: <Widget>[
              CourseWeekHeader(
                week: 1,
                totalWeeks: 16,
                canPrev: false,
                canNext: true,
                isMobile: true,
                onAddCourse: _noop,
                onOpenSetup: _noop,
              ),
              CourseDayAxis(
                days: <int>[1, 2, 3, 4, 5],
                axisWidth: 32,
                dateOf: _dateOf,
                todayWeekday: null,
                isMobile: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Rect label = tester.getRect(find.text(weekLabel(1, 16)));
    final Rect axis = tester.getRect(find.text('周一'));
    // 头部只有 44dp：单行 16sp ≈19，两行 ≈37，真机上（中文字体行高更大）直接
    // 顶出头部压住星期轴。所以断言「只有一行高」而不是「没压到轴」——后者在
    // 测试字体下两行也塞得进 44dp，起不到约束作用（第一版就是这样漏的）。
    expect(label.height, lessThan(28), reason: '周次标签必须单行');
    expect(label.bottom, lessThanOrEqualTo(axis.top + 0.5),
        reason: '标签换出的第二行会压在星期轴上（真机 411dp 实测）');
    // 单行不换行还不够：四个按钮的默认内边距会把标签挤成「第 1 周 / 共 1…」。
    // 测试字体比真机字体更宽，所以这条只会比真机更严格。
    expect(label.width, greaterThanOrEqualTo(120),
        reason: '标签至少要 120dp 才装得下「第 1 周 / 共 16 周」');
  });
}

void _noop() {}

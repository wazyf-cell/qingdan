import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_block.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'package:qingdan/data/migrations.dart';

import 'dao_test_helper.dart';

/// 课程删除入口（M6-A A6）：块详情弹层与课程编辑器各一条路，都要二次确认。
///
/// 软删除对**用户**等于永久删除（课程没有回收站），所以断言只看两件事：
/// 库里 `deleted` 真的置 1 了、活跃查询再也捞不到它。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late AppServices services;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;
  late Semester semester;
  late Course course;

  // 开学 2025-08-04（周一），今天 2025-09-08（周一）相隔 35 天 = 整 5 周，
  // 所以今天是第 **6** 周（第 5 周的周一是 09-01）。`load()` 会把视图定位到
  // 今天那一周，要删的课必须落在第 6 周才看得见块。
  final DateTime today = DateTime.utc(2025, 9, 8);
  final DateTime firstMonday = DateTime.utc(2025, 8, 4);

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
    semester = await semesters.createSemester(
        name: '2025-2026-1', firstWeekDate: firstMonday, totalWeeks: 16);
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
    course = await courses.create(
        name: '高等数学',
        weekday: 1,
        startSection: 1,
        endSection: 2,
        weeks: const <int>[6],
        semesterId: semester.id);
  });

  tearDown(() async => db.close());

  /// 在真实异步区跑一段查库代码。返回值**必须是 nullable**：`runAsync` 对 `void`
  /// 回调永远给 null，早先写成带 `!` 的非空版本会让每个用例在 `pumpAt` 里
  /// 当场炸掉（`model.load()` 就是 void）。要非空结果的调用点自己 `!`。
  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  /// 点「确认删除」并**等整条链真的跑完**。分三步，顺序不能并成一步：
  ///
  /// 1. **在假时钟区点按钮**——确认框的退场动画、块弹层/编辑弹层的 `pop` 都靠假
  ///    时钟推进，`showCourseBlockSheet` 的 `await` 要到动画走完才返回；
  /// 2. `pumpAndSettle` 把这些动画走完（这一段还不碰库）；
  /// 3. **进真实异步区轮询到「模型里已经没有这门课」**——软删事务（BEGIN + update
  ///    + op-log + COMMIT）与 `load()` 的每次往返都要真实事件循环才回得来。
  ///
  /// 为什么不能像早先那样「在 runAsync 里 tap + 固定等 400ms」：那样确认框的退场
  /// 动画在冻结的假时钟里永远走不完，`confirmCourseDelete` 不返回，事务要么没
  /// 开始、要么被冻在 BEGIN 与 COMMIT 之间——日志里的
  /// `Warning database has been locked for 0:00:10.000000` 就是这个形状，随后
  /// `tearDown` 的 `db.close()` 等一个永不提交的事务，整条用例**挂死**（比失败贵）。
  ///
  /// 生产端不会踩：没有假时钟，动画按墙钟推进，删完再重载，事务按序提交。
  Future<void> confirmDeleteAndWait(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('delete-confirm')));
    await tester.pump();
    await tester.pumpAndSettle();
    await io(tester, () async {
      for (int i = 0;
          i < 80 && model.allCourses.any((Course c) => c.id == course.id);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(model.allCourses.any((Course c) => c.id == course.id), isFalse,
          reason: '2 秒内没跑完「软删 + 重载」，这条链在真实异步区里卡住了');
    });
  }

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

  Finder block() => find.byKey(ValueKey<String>('block-${course.id}'));

  /// 把「课程」这条实体的 op-log 捞出来（按写入顺序）。
  Future<List<Map<String, Object?>>> courseOps(WidgetTester tester) async =>
      (await io(tester, () => db.query(
            'op_log',
            where: 'entity_type = ?',
            whereArgs: <Object?>['course'],
            orderBy: 'rowid ASC',
          ))) ??
          <Map<String, Object?>>[];

  testWidgets('桌面：块详情删 → 确认 → 库里 deleted=1、活跃查询没了、周视图块消失',
      (tester) async {
    await pumpAt(tester, width: 1280);
    expect(block(), findsOneWidget);

    await tester.tap(block());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('block-delete')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('block-delete')));
    await tester.pumpAndSettle();
    // 确认框必须写明「无法找回」：课程没有回收站，不能给能找回的错觉。
    expect(find.textContaining('无法找回'), findsOneWidget);

    await confirmDeleteAndWait(tester);
    // 确认框与弹层的退场动画、以及重载后的重建都要推进帧才落到树上。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(block(), findsNothing, reason: '删除后这门课不再出现在课表上');
    expect(find.textContaining('已删除「高等数学」'), findsOneWidget);

    final Course? row = await io(tester, () => services.courseDao.findById(course.id));
    expect(row?.deleted, isTrue, reason: '落库的是软删除标记，行本身还在');
    final List<Course> active =
        (await io(tester, () => courses.activeCourses(semesterId: semester.id)))!;
    expect(active, isEmpty);

    final List<Map<String, Object?>> ops = await courseOps(tester);
    expect(ops, isNotEmpty);
    final Map<String, Object?> last = ops.last;
    // 计划文档写的是「op_log 里有 course/delete」，但本项目的软删除**按 update +
    // deleted 字段**传播（`intent_resolver` 据此判成 TRASH 态），不是物理 delete。
    // 断言按真实契约写：必须留痕，且痕迹里带着 deleted 字段。
    expect(last['operation'], 'update');
    expect('${last['changes_json']}', contains('deleted'),
        reason: '删了课却不记 op-log，另一台设备上这门课会永远留着');

    // 收尾：把回执的两个定时器跑完，否则「A Timer is still pending」判失败。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('确认框点取消：库里 deleted 仍是 0，课程块还在', (tester) async {
    await pumpAt(tester, width: 1280);
    await tester.tap(block());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('block-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('delete-cancel')));
    await tester.pumpAndSettle();

    final Course? row =
        await io(tester, () => services.courseDao.findById(course.id));
    expect(row?.deleted, isFalse, reason: '取消不得写库');
    expect(block(), findsOneWidget);
  });

  testWidgets('手机 411dp：编辑器底部「删除课程」走同一条确认路径', (tester) async {
    await pumpAt(tester, width: 411);
    await tester.tap(block());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('block-edit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('field-name')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('field-delete')), findsOneWidget,
        reason: '从编辑器里也应该能删（A6 改法 4）');

    await tester.tap(find.byKey(const ValueKey<String>('field-delete')));
    await tester.pumpAndSettle();
    await confirmDeleteAndWait(tester);
    // 弹层退场动画与重载后的重建都要推进帧才落到树上。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final Course? row =
        await io(tester, () => services.courseDao.findById(course.id));
    expect(row?.deleted, isTrue);
    expect(find.byType(CourseBlock), findsNothing);
    expect(find.textContaining('已删除「高等数学」'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('新建课程时不给删除按钮（没落库的课无从删）', (tester) async {
    await pumpAt(tester, width: 1280);
    await tester.tap(find.byKey(const ValueKey<String>('btn-add-course')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('field-name')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('field-delete')), findsNothing);
  });
}

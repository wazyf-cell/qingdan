/// 同步写库后课表面板必须自己重载（2026-10-11 S6-4 真机抓到的缺陷）。
///
/// 真机形状：Windows 从坚果云拉回 1 学期 + 5 门课 + 12 节作息，库里全在，
/// 但周视图仍显示「还没有学期」——因为 `CoursePaneModel` 只在首帧 `load()`
/// 一次。任务面板靠「切视图」顺带重载，所以同样的坑在任务域看不出来。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/sync/sync_coordinator.dart';
import 'package:qingdan/sync/sync_runner.dart';
import 'package:qingdan/sync/sync_report.dart';

import 'dao_test_helper.dart';
import 'sync_fakes.dart';

void main() {
  ensureSqfliteFfi();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late AppServices services;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;

  final DateTime mondayWeek1 = DateTime.utc(2025, 9, 1);
  final DateTime today = DateTime.utc(2025, 9, 8);

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: kLatestSchemaVersion,
        onConfigure: (Database d) =>
            d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database d, int v) =>
            runMigrations(d, fromVersion: 0, toVersion: v),
      ),
    );
    services = AppServices(db: db);
    semesters = SemesterUseCase(services);
    courses = CourseUseCase(services);
    model = CoursePaneModel(
        semesterUseCase: semesters,
        courseUseCase: courses,
        clock: () => today);
  });

  tearDown(() async => db.close());

  Future<T?> io<T>(WidgetTester tester, Future<T> Function() body) =>
      tester.runAsync<T>(body);

  /// 假后端「拉到东西」的样子：同步那一刻才把对端数据写进本地库。
  Future<void> pullDuringSync() async {
    final Semester s = await semesters.createSemester(
        name: '对端学期', firstWeekDate: mondayWeek1, totalWeeks: 4);
    // 节次写进**这个学期自己的**作息表（匿名老表那条读路径 2026-10-19 已改掉）。
    await semesters.saveDetailsForSemester(s.id, <TimeDetail>[
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
    await courses.create(
        name: '同步来的课',
        weekday: 1,
        startSection: 1,
        endSection: 2,
        weeks: const <int>[2],
        semesterId: s.id);
  }

  Future<(SyncCoordinator, SyncStatusModel)> wiredCoordinator(
      WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SyncConfigStore store = SyncConfigStore(
      prefs: await SharedPreferences.getInstance(),
      secure: InMemorySecureStore(),
    );
    await store.save(const SyncConfig(
      enabled: true,
      baseUrl: 'https://dav.example.com/dav/x/',
      username: 'u',
      password: 'p',
    ));
    final FakeRunner runner = FakeRunner(pullDuringSync);
    final FakeTimers timers = FakeTimers();
    final SyncCoordinator c = SyncCoordinator(
      configStore: store,
      runnerFactory: FakeFactory(runner),
      timers: timers,
    );
    return (c, SyncStatusModel(coordinator: c));
  }

  Future<void> pump(WidgetTester tester,
      {required SyncStatusModel syncModel, required SyncCoordinator c}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await io(tester, () => model.load());
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<CoursePaneModel>.value(value: model),
        ChangeNotifierProvider<SyncStatusModel>.value(value: syncModel),

      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: CoursePane()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('同步拉到对端课程后，周视图不重启也要立刻渲染出来', (tester) async {
    final (SyncCoordinator c, SyncStatusModel syncModel) =
        await wiredCoordinator(tester);
    await pump(tester, syncModel: syncModel, c: c);

    // 起点：本地还没有学期，面板给空态入口。
    expect(find.text('还没有学期，先建一个学期和作息表'), findsOneWidget);

    // 监听器在 syncNow 内部被触发，它发起的 load() 是真实 DB I/O，
    // 必须留在 runAsync 区里给它一次完成的机会（假异步区不会推进真 Future）。
    await io(tester, () async {
      await c.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();

    expect(find.text('还没有学期，先建一个学期和作息表'), findsNothing,
        reason: '同步已把学期写进库里，面板仍停在首帧那次 load 就是本次真机缺陷');
    final List<Course>? listed =
        await io(tester, () => services.courseDao.findActive());
    final List<Course> shown = listed ?? const <Course>[];
    expect(shown, hasLength(1), reason: '同步写库的课应能在本地查到');

    // 这门课排在第 2 周（today = 第 2 周周一），面板默认停在第 1 周，
    // 换周后才谈得上「渲染出来」。
    await io(tester, () => model.selectWeek(2));
    await tester.pumpAndSettle();
    expect(find.text('同步来的课'), findsOneWidget,
        reason: '对端同步来的课必须出现在周视图上（S6-4 验收项）');
  });
}

/// 运行时执行一段异步副作用（模拟一轮同步真的拉回了数据）。
class FakeRunner implements SyncRunner {
  FakeRunner(this._onRun);

  final Future<void> Function() _onRun;
  int runs = 0;

  @override
  Future<SyncReport> run() async {
    runs++;
    await _onRun();
    return SyncReport()
      ..uploaded = 3
      ..downloaded = 3;
  }

  @override
  int get requestsUsedInWindow => 0;

  @override
  Future<void> dispose() async {}
}

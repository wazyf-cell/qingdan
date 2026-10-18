import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'package:qingdan/data/migrations.dart';

import 'dao_test_helper.dart';

/// 滑动切周 + 周次网格选择器 + 一键校准（M6-A A5）。
///
/// ★ 碰数据库的动作一律包 `tester.runAsync`（FakeAsync 区里 sqflite 的真
/// Future 永不完成）；**按钮要在假时钟区点、动画靠 `pumpAndSettle` 推**，pop 续体
/// 里起的写链才会启动，然后**立刻转进 `runAsync` 轮询到链跑完**才出来——固定等
/// 400 ms 就出 `runAsync` 会把事务冻在 BEGIN 与 COMMIT 之间，连接被自己锁住，
/// `tearDown` 的 `db.close()` 永不返回（2026-10-18 实测：本文件因此挂死 3 分半，
/// 第 4 条失败连带让第 5 条根本没机会跑）。形状同 `course_delete_test.dart`。
/// 411dp 与 1280dp 各 pump 一次（总纲铁律 8）。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late AppServices services;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;

  // 固定「今天」= 2025-09-08（周一），开学日 = 2025-08-04（周一）→ 相隔 35 天，
  // 所以今天是第 **6** 周（第 5 周的周一是 09-01）。周轴期望值 9/15 与 9/22
  // 按「第 7 周的周一 = 09-15」这条轴写，与本常量自洽。
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
  });

  tearDown(() async => db.close());

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  Future<void> seed(WidgetTester tester,
      {required DateTime firstMonday, int totalWeeks = 16}) {
    return io(tester, () async {
      final Semester s = await semesters.createSemester(
          name: '2025-2026-1',
          firstWeekDate: firstMonday,
          totalWeeks: totalWeeks);
      // 节次写进**这个学期自己的**作息表（读路径 2026-10-19 起按学期）。
      final String? error =
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
      expect(error, isNull);
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

  // 断言只读标题文本：`PageController.page` 是内部状态，钉住它等于钉住实现方式。
  String weekLabel(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey<String>('week-label'))).data ??
      '';

  /// 用 [WidgetTester.timedDrag] 而不是 `drag`：`drag` 是「瞬移」，按事件时间戳算
  /// 出来的末速度大得离谱，快甩会一次翻两三页，断言就不稳了。800ms 走完 60% 屏宽
  /// → 末速度 ≈960px/s，惯量只多带 ~160px，落点必然停在相邻那一周。
  Future<void> slide(WidgetTester tester, {
    required double width,
    int direction = -1,
  }) =>
      tester.timedDrag(
        find.byType(PageView),
        Offset(direction * width * 0.6, 0),
        const Duration(milliseconds: 800),
      );

  testWidgets('桌面 1280：左右滑动切周，标题从第 6 周变第 7 周', (tester) async {
    await seed(tester, firstMonday: firstMonday);
    await pumpAt(tester, width: 1280);
    // 今天 09-08 落在第 6 周（开学 08-04 + 35 天），打开就定位到本周。
    expect(weekLabel(tester), '第 6 周 / 共 16 周');

    await slide(tester, width: 1280);
    await tester.pumpAndSettle();
    expect(weekLabel(tester), '第 7 周 / 共 16 周',
        reason: '滑动切周要改的是模型周次，标题必须跟着变');
    // 标题翻了、内容也得跟着翻（第 7 周周一是 9/15，不再是今天的 9/8）。
    expect(find.text('9/15'), findsOneWidget);
    expect(find.text('9/8'), findsNothing);

    // 反向滑回来（箭头与滑动共用同一条 selectWeek，双向都得对）。
    await slide(tester, width: 1280, direction: 1);
    await tester.pumpAndSettle();
    expect(weekLabel(tester), '第 6 周 / 共 16 周');
  });

  testWidgets('桌面 1280：第 1 周向右滑不动、最后一周向左滑不动（不给空周）',
      (tester) async {
    await seed(tester, firstMonday: firstMonday, totalWeeks: 6);
    await pumpAt(tester, width: 1280);

    await io(tester, () => model.selectWeek(1));
    await tester.pumpAndSettle();
    expect(weekLabel(tester), '第 1 周 / 共 6 周');
    await slide(tester, width: 1280, direction: 1);
    await tester.pumpAndSettle();
    expect(weekLabel(tester), '第 1 周 / 共 6 周', reason: '左边没有第 0 周');

    await io(tester, () => model.selectWeek(6));
    await tester.pumpAndSettle();
    await slide(tester, width: 1280);
    await tester.pumpAndSettle();
    expect(weekLabel(tester), '第 6 周 / 共 6 周', reason: '右边没有第 7 周');
  });

  testWidgets('点顶部「第 N 周」弹网格，点第 12 周就翻到第 12 周', (tester) async {
    await seed(tester, firstMonday: firstMonday, totalWeeks: 16);
    await pumpAt(tester, width: 1280);

    await tester.tap(find.byKey(const ValueKey<String>('week-label')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('week-pick-12')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('week-pick-12')));
    await tester.pumpAndSettle();
    expect(weekLabel(tester), '第 12 周 / 共 16 周');
    expect(find.byType(PageView), findsOneWidget,
        reason: '网格选周之后 PageView 要对齐同一周，不能各翻各的');
  });

  testWidgets('长按网格里的第 1 周 = 一键校准：改的是 first_week_monday（读库）',
      (tester) async {
    // 故意把开学日填错**一周**（= 今天所在周的周一 09-08 再往前 7 天）。
    // 周次号**不硬编码**：这条用例真正要测的是校准，不是周次算术，所以初始值
    // 由应用自己的计算导出，只钉住「seed 确实让显示偏离了本周」这个校准前提。
    await seed(tester, firstMonday: DateTime.utc(2025, 9, 1));
    await pumpAt(tester, width: 1280);
    expect(weekLabel(tester), '第 ${model.todayWeek} 周 / 共 16 周',
        reason: '顶栏显示的就是模型认定的本周，两者不许各说各话');
    expect(model.todayWeek, isNot(1),
        reason: '开学日填错一周是校准的前提；等于 1 的话这条用例什么也没测');

    await tester.tap(find.byKey(const ValueKey<String>('week-label')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey<String>('week-pick-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('calibrate-confirm')), findsOneWidget);

    // ① **在假时钟区**点确认：确认框的退场动画、`showDialog` 的 future 都靠假时钟
    //    推进，`_calibrate` 里 `await showDialog` 的续体要到动画走完才启动。
    await tester.tap(find.byKey(const ValueKey<String>('calibrate-confirm')));
    await tester.pump();
    await tester.pumpAndSettle();

    // ② 续体一启动就进 `calibrateThisWeekTo`：`saveSemester` 的事务（BEGIN + UPDATE
    //    + op-log + COMMIT）与 `load()` 的 4 次查询，**每一次往返都要真实事件循环**
    //    才回得来。早先在这里只固定等 400ms 就出 `runAsync`，等于把事务冻在 BEGIN
    //    与 COMMIT 之间带进假时钟区——日志里的 `Warning database has been locked
    //    for 0:00:10.000000` 就是这个形状，随后 `tearDown` 的 `db.close()` 等一个
    //    永不提交的 COMMIT，本条挂死连带拖住下一条（整文件 3 分半只走完 4 条）。
    //    所以必须留在真实异步区**轮询到链跑完**才出来；链没跑完就是红，不是绿。
    await io(tester, () async {
      for (int i = 0; i < 120; i++) {
        final Semester? s = await semesters.activeSemester();
        if (s?.firstWeekMonday == today && model.todayWeek == 1) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final Semester? settled = await semesters.activeSemester();
      expect(settled?.firstWeekMonday, today,
          reason: '3 秒内「校准落库 + 重载」没跑完，这条链在真实异步区里卡住了');
      expect(model.todayWeek, 1,
          reason: '模型也得重读到新开学日，否则顶栏还是旧周次');
    });

    // ③ 库里那一行必须真的是新值（事务已提交，不是只改了内存对象）。
    final Semester? reloaded = await io(tester, semesters.activeSemester);
    expect(reloaded?.firstWeekMonday, DateTime.utc(2025, 9, 8),
        reason: '校准 = 把开学第一周改成「今天所在周的周一」，库里必须真的变了');

    // pop 的续体（关弹层 → 顶栏回执）要再推进一帧才落到树上。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(model.todayWeek, 1, reason: '改完今天就是第 1 周');
    expect(weekLabel(tester), '第 1 周 / 共 16 周');
    expect(
        find.text('已把开学第一周改为 2025-09-08'),
        findsOneWidget,
        reason: '回执在课表页顶部，而不是藏在弹层下面的 SnackBar 里');

    // 把「3 秒后淡出 + 250ms 收起」两个定时器跑完再收尾，
    // 否则 flutter_test 会以「A Timer is still pending」判失败。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey<String>('course-toast')), findsNothing);
  });

  testWidgets('手机 411dp：滑动切周与网格选周同样生效，且布局不溢出', (tester) async {
    await seed(tester, firstMonday: firstMonday);
    await pumpAt(tester, width: 411);
    expect(weekLabel(tester), '第 6 周 / 共 16 周');

    await slide(tester, width: 411);
    await tester.pumpAndSettle();
    expect(weekLabel(tester), '第 7 周 / 共 16 周');
    expect(find.text('9/15'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('week-label')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('week-pick-12')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('week-pick-3')));
    await tester.pumpAndSettle();
    expect(weekLabel(tester), '第 3 周 / 共 16 周');
    expect(tester.takeException(), isNull, reason: '移动端不得有 RenderFlex 溢出');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/features/course/course_manage_page.dart';
import 'package:qingdan/features/course/semester_detail_page.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/settings/course_section.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// M6-C §C1 第 4 行：设置 · 课表节。
///
/// 断言三件事：① 「学期与作息」这一行真的把用户送进**已有的那个弹层**，而且
/// 形态按断点走（411 = 底部抽屉 / 1280 = 居中弹窗），不是本节自己复制的一份界面；
/// ② D 批 §7.3 / §7.4 之后这一节**一个禁用占位都不剩**：「时间表管理」点开模板库
/// 页、「课表管理」点开整页（本页自己的用例见 `course_manage_page_test.dart`，
/// 这里只钉「设置这一行确实把用户送到了那一页」），死行与「下一批开放」那种
/// 过期承诺都不许留（M5 定案：占位要么说清原因，要么别出现）；
/// ③ 导出行禁用时**必须写明原因**（没学期没课），而不是点了没反应。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb db;
  late SemesterUseCase semesters;
  late TimetableUseCase templates;
  late CourseUseCase courses;
  late CoursePaneModel paneModel;

  setUp(() async {
    db = await DaoTestDb.open();
    final AppServices services = AppServices(db: db.db);
    semesters = SemesterUseCase(services);
    // 「课表管理」整页里的 SemesterListView 读它（新建学期选模板，§7.2）。
    templates = TimetableUseCase(services);
    courses = CourseUseCase(services);
    paneModel =
        CoursePaneModel(semesterUseCase: semesters, courseUseCase: courses);
  });

  tearDown(() async => db.close());

  double heightOf(double width) => width < 720 ? 915 : 1400;

  Future<void> pump(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, heightOf(width));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<TimetableUseCase>.value(value: templates),
        Provider<CourseUseCase>.value(value: courses),
        ChangeNotifierProvider<CoursePaneModel>.value(
            value: paneModel), // 弹层与「课表管理」整页都要读它
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: const CourseSection(),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  /// 让界面里那条读写链在真实异步区跑完：sqflite_common_ffi 对同一个库**按发起
  /// 顺序排队**，所以自己连发 [steps] 趟查询并等回来，就保证排在它们前面那几步
  /// （含写事务的 COMMIT）也全落地了（`semester_switcher_test.dart` 的做法）。
  Future<void> settle(WidgetTester tester, {int steps = 12}) =>
      io(tester, () async {
        for (int i = 0; i < steps; i++) {
          await semesters.allSemesters();
        }
      });

  /// 点一个会查库的入口：tap 与等待都放在真实异步区里，否则 sqflite 的
  /// future 在 FakeAsync 区永不完成（`course_setup_flow_test.dart` 的经验）。
  Future<void> tapIo(WidgetTester tester, String key) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await settle(tester, steps: 6);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Finder tile(String key) => find.byKey(ValueKey<String>(key));

  testWidgets('四行全是真入口：三行有 onTap 且 enabled，导出行禁用但写明原因（411 与 1280 各一次）',
      (WidgetTester tester) async {
    for (final double w in <double>[411, 1280]) {
      await pump(tester, width: w);
      expect(tester.takeException(), isNull, reason: '宽度 $w 出现布局异常');

      // D 批 §7.3 / §7.4：三行都解禁成真入口，一行死行都不许留。
      for (final String k in <String>[
        kCourseOpenSetupKey,
        kCourseManageTimetableKey,
        kCourseManageScheduleKey,
      ]) {
        final ListTile t = tester.widget<ListTile>(tile(k));
        expect(t.onTap, isNotNull, reason: '$k 在 ${w.toInt()}dp 上是死行');
        expect(t.enabled, isTrue, reason: '$k 在 ${w.toInt()}dp 被禁用');
      }
      // 「下一批开放」那种过期承诺必须彻底消失（占位实现也一起删了）。
      expect(find.textContaining('下一批开放'), findsNothing);
      expect(find.textContaining('D 批'), findsNothing);

      // 导出行仍然禁用，但禁用得有原因（本用例的模型里没学期也没课）。
      final ListTile export = tester.widget<ListTile>(tile(kCourseExportKey));
      expect(export.enabled, isFalse);
      expect(export.onTap, isNotNull, reason: '靠 enabled 禁用，不是没接实现');
      expect(find.textContaining('还没有学期或还没有课'), findsOneWidget);
    }
  });

  testWidgets('点「课表管理」= 推上整页（不是弹层）：本页带学期列表与两条导入入口',
      (WidgetTester tester) async {
    for (final double w in <double>[411, 1280]) {
      await pump(tester, width: w);
      await io(tester, () async {
        await semesters.createSemester(
            name: '走查 ${w.toInt()}',
            firstWeekDate: DateTime.utc(2026, 8, 31));
        await paneModel.load();
      });
      await tapIo(tester, kCourseManageScheduleKey);

      // harness 的 home 没有 AppBar：出现 AppBar 只可能是推上来的那一页。
      expect(find.byType(AppBar), findsOneWidget,
          reason: '${w.toInt()}dp：没推到整页');
      expect(find.byType(AlertDialog), findsNothing, reason: '整页不是弹窗');
      expect(find.byType(BottomSheet), findsNothing, reason: '整页不是抽屉');
      // 标题 Scoped 到那一页：设置里那一行也叫「课表管理」，不限定就数不清。
      expect(
          find.descendant(
              of: find.byType(CourseManagePage), matching: find.text('课表管理')),
          findsOneWidget);
      // §7.4：复用同一个 SemesterListView + 两条导入入口的第二入口。
      expect(tile('manage-import'), findsOneWidget);
      expect(tile('manage-capture'), findsOneWidget);
      expect(tile('manage-templates'), findsOneWidget);
      expect(find.text('走查 ${w.toInt()}'), findsOneWidget);
      // 量尺寸不量原点：进场的页面转场会留下亚像素偏移（411dp 实测 left=0.1），
      // 钉 `Rect.fromLTRB(0,0,w,h)` 会把一个看不见的路由动画余量当成红线。
      final Rect page = tester.getRect(find.byType(CourseManagePage));
      expect(page.width, closeTo(w, 0.5), reason: '${w.toInt()}dp：宽度没铺满');
      expect(page.height, closeTo(heightOf(w), 0.5),
          reason: '${w.toInt()}dp：高度没铺满');
      expect(page.left.abs(), lessThan(1.0), reason: '${w.toInt()}dp：整页应贴左');
      expect(tester.getRect(tile('manage-templates')).right,
          lessThanOrEqualTo(w));

      await tester.tap(find.byType(BackButton));
      // 退场的路由要动画走完**之后再有一帧**才从 Overlay 摘掉；单帧 pump 到位
      // 会留下「Page 还在树上」的假象。不用 pumpAndSettle：学期列表首帧有读库回调。
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CourseManagePage), findsNothing);
      expect(tile(kCourseManageScheduleKey), findsOneWidget,
          reason: '${w.toInt()}dp：退回来要还是那一节');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('点「学期与作息」：窄屏且没有学期 → 进课表管理页去建',
      (WidgetTester tester) async {
    await pump(tester, width: 411);
    await tapIo(tester, kCourseOpenSetupKey);

    expect(find.byType(CourseManagePage), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('点「学期与作息」：窄屏有学期 → 整页详情（字段 + 作息入口）',
      (WidgetTester tester) async {
    await io(tester, () async {
      await semesters.createSemester(
          name: '2026-2027-1', firstWeekDate: DateTime.utc(2026, 8, 31));
      await paneModel.load();
    });
    await pump(tester, width: 411);
    await tapIo(tester, kCourseOpenSetupKey);

    expect(find.byType(SemesterDetailPage), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tile('semester-save'), findsOneWidget);
    expect(tile('semester-edit-timetable'), findsOneWidget);
  });

  testWidgets('点「学期与作息」：宽屏打开居中弹窗（isMobile 按断点传，不写死）',
      (WidgetTester tester) async {
    await pump(tester, width: 1280);
    await tapIo(tester, kCourseOpenSetupKey);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tile('setup-import'), findsOneWidget);
  });

  testWidgets('禁用行点下去什么也不发生（不给假反馈）',
      (WidgetTester tester) async {
    await pump(tester, width: 411);
    await tapIo(tester, kCourseExportKey);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有学期也有课时：导出行解禁，点得开导出弹层',
      (WidgetTester tester) async {
    await io(tester, () async {
      final String id = (await semesters.createSemester(
              name: '2026-2027-1', firstWeekDate: DateTime.utc(2026, 8, 31)))
          .id;
      await courses.create(
          name: '高等数学',
          weekday: 1,
          startSection: 1,
          endSection: 2,
          weeks: <int>[1, 2, 3],
          semesterId: id);
      await paneModel.load();
    });
    await pump(tester, width: 411);

    expect(tester.widget<ListTile>(tile(kCourseExportKey)).enabled, isTrue);
    await tapIo(tester, kCourseExportKey);
    expect(find.byType(BottomSheet), findsOneWidget,
        reason: '导出走的是 export_sheet.dart 那一份，不是本节自己复制的界面');
    expect(find.textContaining('.ics'), findsWidgets);
  });

  testWidgets('说明文字交代清楚：单门课去哪改、批量改还剩哪里、四行都有副标题',
      (WidgetTester tester) async {
    await pump(tester, width: 1280);
    expect(find.textContaining('改某一门课的时间、地点、老师是点周视图里的课程块'),
        findsOneWidget);
    expect(find.textContaining('导入向导的校正步'), findsOneWidget,
        reason: '§7.4 的实话：落库之后不再提供批量入口');
    expect(find.textContaining('学期名称、开学日期、总周数'), findsOneWidget);
    expect(find.textContaining('一屏管全部学期'), findsOneWidget,
        reason: '「课表管理」这行要写清它管什么，而不是留个名字');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/settings/course_section.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// M6-C §C1 第 4 行：设置 · 课表节。
///
/// 断言两件事：① 「学期与作息」这一行真的把用户送进**已有的那个弹层**，而且
/// 形态按断点走（411 = 底部抽屉 / 1280 = 居中弹窗），不是本节自己复制的一份界面；
/// ② D 批的三行是**看得懂的禁用行**（`enabled: false` + 「下一批开放」），
/// 而不是留着但点了没反应的死行。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb db;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel paneModel;

  setUp(() async {
    db = await DaoTestDb.open();
    final AppServices services = AppServices(db: db.db);
    semesters = SemesterUseCase(services);
    courses = CourseUseCase(services);
    paneModel =
        CoursePaneModel(semesterUseCase: semesters, courseUseCase: courses);
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, width < 720 ? 915 : 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<CourseUseCase>.value(value: courses),
        ChangeNotifierProvider<CoursePaneModel>.value(
            value: paneModel), // 弹层要读它
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

  /// 点一个会查库的入口：tap 与等待都放在真实异步区里，否则 sqflite 的
  /// future 在 FakeAsync 区永不完成（`course_setup_flow_test.dart` 的经验）。
  Future<void> tapIo(WidgetTester tester, String key) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Finder tile(String key) => find.byKey(ValueKey<String>(key));

  testWidgets('入口行可点，三行 D 批占位禁用且各写明「下一批开放」（411 与 1280 各一次）',
      (WidgetTester tester) async {
    for (final double w in <double>[411, 1280]) {
      await pump(tester, width: w);
      expect(tester.takeException(), isNull, reason: '宽度 $w 出现布局异常');

      expect(tile(kCourseOpenSetupKey), findsOneWidget);
      expect(tester.widget<ListTile>(tile(kCourseOpenSetupKey)).onTap, isNotNull);

      for (final String k in <String>[
        kCourseManageTimetableKey,
        kCourseManageScheduleKey,
        kCourseExportKey,
      ]) {
        final ListTile t = tester.widget<ListTile>(tile(k));
        expect(t.enabled, isFalse, reason: '$k 不是禁用行');
        expect(t.onTap, isNull, reason: '$k 接了 onTap 却没有实现，是死行');
      }
      expect(find.textContaining('下一批开放'), findsNWidgets(3));
    }
  });

  testWidgets('点「学期与作息」：窄屏打开底部抽屉，形态与课表面板一致',
      (WidgetTester tester) async {
    await pump(tester, width: 411);
    await tapIo(tester, kCourseOpenSetupKey);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    // 弹层里既有的两个入口（导入文件 / 教务抓取）说明用的是同一份实现。
    expect(tile('setup-import'), findsOneWidget);
    expect(tile('setup-capture'), findsOneWidget);
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

  testWidgets('说明文字交代清楚：课表数据在哪改、三行为什么还没有',
      (WidgetTester tester) async {
    await pump(tester, width: 1280);
    expect(find.textContaining('上面三行是下一批（D 批）的入口'), findsOneWidget);
    expect(find.textContaining('学期名称、开学日期、总周数'), findsOneWidget);
  });
}

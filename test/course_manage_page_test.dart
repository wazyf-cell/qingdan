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
import 'package:qingdan/features/course/import_wizard/import_wizard.dart';
import 'package:qingdan/features/course/semester_sheet.dart';
import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// 课表管理整页（M6-D §7.4）= 学期面板的整页版本 + 两条导入入口的第二入口。
///
/// 三条入口形态各不相同，要分开钉死：本页永远 push 整页；「导入课表文件」411 push
/// 路由 / 1280 居中 Dialog；「时间表管理」两端都是弹层。碰库动作一律在
/// `tester.runAsync` 里跑完；411 与 1280 各 pump 一遍（总纲铁律 8）。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  late SemesterUseCase semesters;
  late TimetableUseCase templates;
  late CourseUseCase courses;
  late ImportService importer;
  late CoursePaneModel model;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{}); // 模板库读 prefs
    env = await DaoTestDb.open();
    final AppServices services = AppServices(db: env.db);
    semesters = SemesterUseCase(services);
    templates = TimetableUseCase(services);
    courses = CourseUseCase(services);
    importer = ImportService(services.courseDao);
    // 固定「今天」= 2025-09-08（周一）：A 学期 08-04 开学 = 第 6 周。
    model = CoursePaneModel(
        semesterUseCase: semesters,
        courseUseCase: courses,
        clock: () => DateTime.utc(2025, 9, 8));
  });

  tearDown(() async => env.close());

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
    final List<Semester> all =
        (await io(tester, semesters.allSemesters))!;
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

  for (final (String label, double width) in
      <(String, double)>[('移动 411dp', 411), ('桌面 1280dp', 1280)]) {
    group(label, () {
      final double height = heightOf(width);

      testWidgets('P1 能进能退：三条入口行 + 两个学期行都在本页，勾只在当前学期',
          (WidgetTester tester) async {
        await seed(tester);
        await openManage(tester, width);
        await tapIo(tester, 'open-shell');

        expect(find.byType(CourseManagePage), findsOneWidget);
        // 量尺寸而不是量原点：进场的页面转场即使 pump 到位也会留下 **亚像素**原点
        // （411dp 实测 left=0.1、1280dp left=0.5）。写 `Rect.fromLTRB(0,0,w,h)`
        // 等于把一个看不见的路由动画余量钉成红线，白天绿、换个断言顺序就红。
        final Rect page = tester.getRect(find.byType(CourseManagePage));
        expect(page.width, closeTo(width, 0.5), reason: '$label：整页宽度没铺满');
        expect(page.height, closeTo(height, 0.5), reason: '$label：整页高度没铺满');
        expect(page.left.abs(), lessThan(1.0),
            reason: '$label：整页必须贴着视口左边，不是浮在中间的一块');

        final String idA = await idOf(tester, 'A 学期');
        final String idB = await idOf(tester, 'B 学期');
        expect(key('semester-row-$idA'), findsOneWidget);
        expect(key('semester-row-$idB'), findsOneWidget);
        expect(key('semester-check-$idA'), findsOneWidget);
        expect(key('semester-check-$idB'), findsNothing,
            reason: '$label：勾只有一个，而且挂在当前学期那行');
        expect(key('semester-create'), findsOneWidget);

        final Rect row1 = tester.getRect(key('manage-import'));
        final Rect row2 = tester.getRect(key('manage-capture'));
        final Rect row3 = tester.getRect(key('manage-templates'));
        final Rect sem = tester.getRect(key('semester-row-$idA'));
        expect(row1.width, greaterThan(width * 0.8), reason: '$label：入口行没铺满');
        expect(row2.width, closeTo(row1.width, 0.5));
        expect(row2.top, greaterThan(row1.bottom - 1));
        expect(row3.top, greaterThan(row2.bottom - 1));
        expect(sem.top, greaterThan(row3.bottom - 1),
            reason: '$label：学期列表排在三条入口之后（§7.4）');
        expect(row3.right, lessThanOrEqualTo(width));
        expect(tester.widget<ListTile>(key('manage-capture')).onTap, isNotNull,
            reason: '$label：教务抓取这条入口不许是死行');
        expect(tester.takeException(), isNull, reason: '$label 出现布局异常');

        await tester.tap(find.byType(BackButton));
        // 退场的路由要**动画走完之后再有一帧**才真的从 Overlay 上摘掉：只
        // `pump()` + 一次 `pump(400ms)` 会停在同一帧里，Page 还挂在树上，看着
        // 像「退不回去」。分多帧推进，别用 pumpAndSettle（本页首帧有读库回调，
        // 它会一直等到超时）。
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(CourseManagePage), findsNothing);
        expect(key('open-shell'), findsOneWidget, reason: '$label：退不回去');
      });

      testWidgets('P2 「导入课表文件」= 同一个五步向导开在本页之上（形态按断点分）',
          (WidgetTester tester) async {
        await seed(tester);
        await openManage(tester, width);
        await tapIo(tester, 'open-shell');
        await tapIo(tester, 'manage-import');

        expect(find.byType(ImportWizardPage), findsOneWidget);
        expect(key('pick-file'), findsOneWidget, reason: '$label：向导步 1 没出现');
        expect(key('wizard-next'), findsOneWidget);
        if (width < 720) {
          expect(find.byType(Dialog), findsNothing, reason: '窄屏该 push 路由');
          final Rect w1 = tester.getRect(find.byType(ImportWizardPage));
          expect(w1.width, closeTo(width, 0.5));
          expect(w1.height, closeTo(height, 0.5));
          expect(w1.left.abs(), lessThan(1.0));
          expect(find.text('导入课表'), findsOneWidget);
        } else {
          expect(find.byType(Dialog), findsOneWidget, reason: '宽屏该居中弹窗');
          // `Dialog` 自己的 layout box 就是整屏（它是定位层，卡片是里面的 child），
          // 拿它的宽度当「弹窗宽度」必然得到 1280——量子那颗定宽 860 的卡片。
          final Rect card = tester.getRect(find
              .descendant(
                  of: find.byType(ImportWizardPage),
                  matching: find.byType(SizedBox))
              .first);
          expect(card.width, closeTo(860, 1), reason: '$label：向导卡片定宽 860');
          expect(card.height, closeTo(600, 1));
          expect(card.center.dx, closeTo(width / 2, 1));
        }
        expect(tester.takeException(), isNull);

        // 关掉向导要回到本页，而不是把整页一起带走。
        await popTop(tester);
        expect(find.byType(ImportWizardPage), findsNothing);
        expect(find.byType(CourseManagePage), findsOneWidget);
        expect(key('manage-import'), findsOneWidget);
      });

      testWidgets('P3 「时间表管理」= 打开同一份模板库（两端都是弹层）',
          (WidgetTester tester) async {
        await seed(tester);
        await openManage(tester, width);
        await tapIo(tester, 'open-shell');
        await tapIo(tester, 'manage-templates');

        expect(key('timetable-library'), findsOneWidget,
            reason: '$label：模板库没开出来');
        expect(find.text('大学默认'), findsOneWidget,
            reason: '$label：内置模板要在列（§7.3）');
        expect(key('tpl-create'), findsOneWidget);
        expect(tester.getRect(key('timetable-library')).width,
            lessThanOrEqualTo(width));
        if (width < 720) {
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
        }
        expect(tester.takeException(), isNull, reason: '$label 出现布局异常');

        await popTop(tester);
        expect(key('timetable-library'), findsNothing);
        expect(find.byType(CourseManagePage), findsOneWidget,
            reason: '$label：关掉模板库要还在本页');
      });

      testWidgets('P4 整页形态点一行学期：切换成功且回执 semester-said 留在本页',
          (WidgetTester tester) async {
        await seed(tester);
        await openManage(tester, width);
        await tapIo(tester, 'open-shell');
        final String idB = await idOf(tester, 'B 学期');
        expect(key('semester-said'), findsNothing, reason: '没操作过不该有回执');

        await tester.tap(key('semester-row-$idB'));
        await tester.pump();
        await settle(tester);
        await tester.pumpAndSettle();

        expect(model.semester?.id, idB, reason: '$label：写链没跑完');
        expect(find.byType(CourseManagePage), findsOneWidget,
            reason: '$label：整页不该关，回执要显示在本页');
        expect(key('semester-said'), findsOneWidget);
        expect(tester.widget<Text>(key('semester-said')).data,
            contains('已切换到「B 学期」'));
        expect(key('semester-check-$idB'), findsOneWidget, reason: '勾跟着换过去');
        final List<Map<String, Object?>> actives = (await io(tester,
            () => env.db.query('semesters', where: 'is_active = 1')))!;
        expect(actives.map((Map<String, Object?> r) => r['id']), <Object?>[idB],
            reason: '库里必须真的换了过去，不是只改了内存对象');
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('对照 §7.1：弹层形态把回执交给外层 pop，列表自己不留 semester-said',
      (WidgetTester tester) async {
    String? said;
    await seed(tester);
    await pumpShell(tester, 1280, open: (BuildContext ctx) async {
      said = await showSemesterSheet(ctx,
          model: model,
          semesters: semesters,
          templates: templates,
          isMobile: false);
    });
    await tapIo(tester, 'open-shell');
    final String idB = await idOf(tester, 'B 学期');
    expect(key('semester-row-$idB'), findsOneWidget);

    await tester.tap(key('semester-row-$idB'));
    await tester.pump();
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SemesterListView), findsNothing, reason: '弹层切完就关');
    expect(key('semester-said'), findsNothing, reason: '回执归外层，不留在列表里');
    expect(said, '已切换到「B 学期」',
        reason: '§7.1：面板把这句话作为 pop 值交回调用方（课表页行内回执）');
    expect(tester.takeException(), isNull);
  });
}

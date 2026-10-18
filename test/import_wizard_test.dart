// 导入向导端到端（F29/F30/F31 的验收主战场）。
//
// **两种形态各跑一遍**（S4b 的教训：只 pump 桌面壳，手机上四处布局全炸）。
// 全程点界面，不直接调用例层；文件用仓库里的真实 xlsx 样本。

import 'dart:convert';
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
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/import_wizard/import_wizard.dart';
import 'package:qingdan/features/course/import_wizard/wizard_file_picker.dart';
import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

const String _samplePath = '相关来源或素材/课表模板.xlsx';

void main() {
  ensureSqfliteFfi();

  late Database db;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late ImportService importer;
  late CoursePaneModel pane;
  late Uint8List xlsxBytes;

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
    importer = ImportService(services.courseDao);
    pane = CoursePaneModel(semesterUseCase: semesters, courseUseCase: courses);
    // 学期与 12 节作息先备好：步 3 只负责展示与改，不是本用例的验证点。
    await semesters.createSemester(
        name: '2025-2026-1',
        firstWeekDate: DateTime(2025, 9, 1),
        totalWeeks: 16);
    await semesters.saveDefaultTimetable(generateTimeDetails(
        timetableId: '',
        firstStartMinutes: 480,
        lessonMinutes: 45,
        breakMinutes: 10,
        sectionCount: 12));
    await pane.load();
    xlsxBytes = File(_samplePath).readAsBytesSync();
  });

  tearDown(() async => db.close());

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

  testWidgets('桌面端到端：真实 xlsx → 映射 → 校正 → 合并导入 3 条落库',
      (tester) async {
    await openWizard(tester,
        width: 1280, loadFile: loader(xlsxBytes));

    // 步 1：编码结论行必须显式（§3.1:162）
    await tapIo(tester, 'pick-file');
    expect(find.textContaining('已按'), findsOneWidget);
    expect(find.textContaining('7 列、3 行'), findsOneWidget);
    await driveToCorrection(tester);

    // 默认筛选 = 只看有问题的（§4.3 规则 5）：✓ 行（文件第 2 行高数）不该出现，
    // 重叠的两条（第 3、4 行）出现。
    expect(find.byKey(const ValueKey<String>('row-2')), findsNothing,
        reason: '✓ 正常行默认不显示');
    expect(find.byKey(const ValueKey<String>('row-3')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('gate-banner')), findsOneWidget,
        reason: '确认已经走到步 4');

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey<String>('filter-all')));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('row-2')), findsOneWidget);

    // 步 5：首次导入隐藏模式选择（§3.1:166），直接合并
    await next(tester);
    expect(find.byKey(const ValueKey<String>('mode-hidden')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('mode-overwrite')), findsNothing);
    await next(tester); // 开始导入
    expect(find.byKey(const ValueKey<String>('import-summary')), findsOneWidget);
    expect(find.textContaining('新增 3'), findsOneWidget);

    final List<Course> saved = await readCourses(tester);
    expect(saved, hasLength(3));
    expect(saved.map((Course c) => c.name).toSet(),
        <String>{'高等数学', '线性代数', '大学英语'});
    // 高数：1-5、7-11单、12-16双 → 绝对奇偶周号（§3.3.1）
    final Course gao =
        saved.firstWhere((Course c) => c.name == '高等数学');
    expect(gao.weeks, containsAll(<int>[9, 11, 12, 14, 16]));
    expect(gao.origin, CourseOrigin.import);
  });

  testWidgets('移动端 411dp 同一条路：卡片列表，无表头，导入同样落库',
      (tester) async {
    await openWizard(tester,
        width: 411, loadFile: loader(xlsxBytes));
    expect(find.byKey(const ValueKey<String>('wizard-back')), findsNothing,
        reason: '步 1 不给上一步');
    await tapIo(tester, 'pick-file');
    await driveToCorrection(tester);

    // 移动形态：卡片列表（没有桌面表头），行仍可点（点开底部抽屉编辑器）
    expect(find.text('状态 / 课程'), findsNothing);
    expect(find.byKey(const ValueKey<String>('row-3')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('gate-banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('row-3')));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget,
        reason: '移动端点行 → 底部抽屉承载同一个编辑面板');
    await tester.tap(find.byKey(const ValueKey<String>('field-location')));
    await tester.enterText(
        find.byKey(const ValueKey<String>('field-location')), '理工楼110');
    await tester.tap(find.byKey(const ValueKey<String>('btn-save')));
    await tester.pumpAndSettle();

    await next(tester);
    await next(tester);
    expect(find.byKey(const ValueKey<String>('import-summary')), findsOneWidget);
    expect(await readCourses(tester), hasLength(3));
  });

  testWidgets('闸门：✗ 行未处理时下一步禁用；忽略后放行且不落库', (tester) async {
    final Uint8List csv = Uint8List.fromList(utf8.encode(
        '课程名称,星期,开始节数,结束节数,老师,地点,周数\n'
        '高等数学,1,1,2,小明,逸夫201,1-5\n'
        '大学体育,2,3,4,红哥,操场,1-5、约、7-11单\n'));
    await openWizard(tester, width: 1280, loadFile: loader(csv, name: 'a.csv'));
    await tapIo(tester, 'pick-file');
    await next(tester);
    await next(tester);
    await next(tester);

    expect(find.textContaining('还有 1 条错误未处理'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey<String>('wizard-next')))
            .onPressed,
        isNull,
        reason: '闸门没开就不给推进');

    await tapIo(tester, 'fix-3');
    await tester.pumpAndSettle();
    expect(find.text('忽略此条'), findsOneWidget, reason: '菜单没打开');
    await tapTextIo(tester, '忽略此条');

    await next(tester);
    await next(tester);
    final List<Course> saved = await readCourses(tester);
    expect(saved.map((Course c) => c.name), <String>['高等数学']);
  });

  testWidgets('回跳到映射步先问「校正作废」，确认后重算', (tester) async {
    await openWizard(tester,
        width: 1280, loadFile: loader(xlsxBytes));
    await tapIo(tester, 'pick-file');
    await driveToCorrection(tester);
    // 先忽略一行，制造「已做校正」
    await tapIo(tester, 'fix-3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('忽略此条'));
    await tester.pump();

    await tapIo(tester, 'step-1');
    expect(find.text('返回会丢失已做的校正'), findsOneWidget);
    await tapIo(tester, 'back-confirm');
    // 回到映射步，校正列表被清空（重进行 4 时才重算）
    expect(find.byKey(const ValueKey<String>('map-0')), findsOneWidget);
  });
}

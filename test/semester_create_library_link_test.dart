import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/default_timetable.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/semester_create_sheet.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// 新建学期表单（§7.2）底部那行「管理时间表…」→ 模板库（§7.3）。
///
/// 钉三件审计抓到过的实事：① 这颗按钮**不是死的**（原先 `onPressed: null` +
/// Tooltip「下一批开放」，而那一页早就存在）；② 打开模板库**不许 pop 掉这张
/// 表单**（用户已填的内容不能丢，两层都挂在 root navigator 上）；③ 回到表单后
/// 模板候选要**重扫**（库里删掉的那条不能再当选中项，否则保存会拿一个已删的
/// templateId）。
///
/// 411 与 1280 各 pump 一遍（这个界面按宽度分发形态：移动 = 底部抽屉，桌面 =
/// 居中弹窗）。碰库的点击一律 `runAsync`（假时钟区里 sqflite 的 future 永不完成）。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late AppServices services;
  late SemesterUseCase semesters;
  late TimetableUseCase templates;
  late CoursePaneModel model;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
    templates = TimetableUseCase(services);
    model = CoursePaneModel(
        semesterUseCase: semesters,
        courseUseCase: CourseUseCase(services),
        clock: () => DateTime.utc(2025, 9, 8));
  });

  tearDown(() async => db.close());

  Finder key(String k) => find.byKey(ValueKey<String>(k));
  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  /// 点一下并等真实异步链跑完（含路由退场那几帧）。
  Future<void> tapIo(WidgetTester tester, String k) async {
    await tester.runAsync(() async {
      await tester.tap(key(k));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 装配 + 打开「新建学期」表单，并等模板候选读回来。
  Future<void> openForm(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, width < 720 ? 900 : 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await io(tester, () async {
      await semesters.createSemester(
          name: '已有学期', firstWeekDate: DateTime.utc(2025, 8, 4));
      return model.load();
    });
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<TimetableUseCase>.value(value: templates),
        ChangeNotifierProvider<CoursePaneModel>.value(value: model),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(builder: (BuildContext ctx) => Center(
                child: TextButton(
                  key: const ValueKey<String>('open-create'),
                  onPressed: () => showSemesterCreateSheet(ctx,
                      model: model,
                      semesters: semesters,
                      templates: templates,
                      isMobile: width < 720),
                  child: const Text('新建学期'),
                ),
              )),
        ),
      ),
    ));
    await tester.pump();
    await tapIo(tester, 'open-create');
    expect(key('create-save'), findsOneWidget, reason: '新建学期表单没打开');
  }

  for (final (String label, double width) in
      <(String, double)>[('移动 411dp', 411), ('桌面 1280dp', 1280)]) {
    testWidgets('$label：「管理时间表…」是真链接，开了模板库也不 pop 这张表单',
        (WidgetTester tester) async {
      await openForm(tester, width);

      final TextButton link = tester.widget<TextButton>(
          key('create-manage-timetable'));
      expect(link.onPressed, isNotNull,
          reason: '$label：这颗按钮必须是活的（审计抓到的就是 onPressed == null）');

      await tester.enterText(key('create-name'), '别把我的表单弄丢');
      await tester.pump();

      await tapIo(tester, 'create-manage-timetable');

      expect(key('timetable-library'), findsOneWidget,
          reason: '$label：点了没跳到 §7.3 时间表管理页');
      expect(key('create-save'), findsOneWidget,
          reason: '$label：模板库开在表单**之上**，表单不能被 pop 掉');
      expect(find.text('别把我的表单弄丢'), findsOneWidget,
          reason: '$label：已经填进去的学期名称要还在');
      expect(tester.takeException(), isNull, reason: '$label：不得有布局异常');
    });

    testWidgets('$label：库里删掉模板后回到表单，候选重扫、选中项不指已删的模板',
        (WidgetTester tester) async {
      // 做一份自定义模板并把 prefs 默认指到它 → 表单下拉显示的就是它。
      final TimeTable custom = (await io(tester,
          () => templates.createTemplate(
              name: '晚间作息', copyFromId: kBuiltInTimetableId)))!;
      SharedPreferences.setMockInitialValues(
          <String, Object>{'course.defaultTemplateId': custom.id});
      await openForm(tester, width);
      expect(find.text('晚间作息（12 节）'), findsOneWidget,
          reason: '$label：选中项应为 prefs 里那份模板');

      await tapIo(tester, 'create-manage-timetable');
      expect(key('timetable-library'), findsOneWidget);
      await tapIo(tester, 'tpl-del-${custom.id}');
      await tapIo(tester, 'tpl-del-confirm');
      await tester.pump(const Duration(milliseconds: 400));

      // 关掉模板库：退场动画 + 回来后那次重扫都要读库，全程留在真实异步区。
      // 手机端 v1.0.10 起是整页，直接点 AppBar 的返回；宽屏仍是弹窗。
      await tester.runAsync(() async {
        if (width < 720) {
          await tester.tap(find.byType(BackButton));
        } else {
          Navigator.of(tester.element(key('timetable-library'))).pop();
        }
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump();
      });
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(key('timetable-library'), findsNothing, reason: '$label：模板库没关掉');
      expect(find.text('晚间作息（12 节）'), findsNothing,
          reason: '$label：已删模板还挂在选中项上，保存就会拿一个不存在的 templateId');
      expect(find.text('大学默认（默认）'), findsOneWidget,
          reason: '$label：重扫后要回落到候选第一项（内置模板）');
      expect(key('create-save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

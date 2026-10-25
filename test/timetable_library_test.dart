import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/data/semester_dao.dart' show SemesterDaoTermOps;
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/timetable_library_page.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// M6-D §7.3 时间表管理页（模板库）。
///
/// **411 移动壳与 1280 桌面壳各 pump 一遍**（总纲铁律 8）。碰库的点击一律
/// 走 `tapIo`：tap 与等待放进真实异步区（`tester.runAsync`），FakeAsync 的
/// 帧推进帮不了 sqflite 的 future（`course_setup_flow_test.dart` 的教训）。
void main() {
  ensureSqfliteFfi();

  late DaoTestDb env;
  late AppServices services;
  late TimetableUseCase templates;
  late SemesterUseCase semesters;

  setUp(() async {
    env = await DaoTestDb.open();
    services = AppServices(db: env.db);
    templates = TimetableUseCase(services);
    semesters = SemesterUseCase(services);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() async => env.close());

  const String builtinId = 'builtin-college';

  Finder key(String k) => find.byKey(ValueKey<String>(k));

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  Future<void> tapIo(WidgetTester tester, String k) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey<String>(k)));
      // 第一帧在真实异步区里画：provider 的 create（`..load()`）发生在 build，
      // 帧若在 FakeAsync 区画，load 的 DB future 永远等不到完成（本仓库的老坑）。
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> tapPlain(WidgetTester tester, String k) async {
    await tester.tap(key(k));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpShell(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, width < 720 ? 900 : 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SemesterUseCase>.value(value: semesters),
        Provider<TimetableUseCase>.value(value: templates),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(builder: (BuildContext ctx) => Center(
              child: TextButton(
                  key: const ValueKey<String>('open-lib'),
                  onPressed: () =>
                      showTimetableLibrary(ctx, isMobile: width < 720),
                  child: const Text('打开时间表管理'))))),
        ),
      ),
    );
    await tester.pump();
  }

  for (final (String label, double width) in
      <(String, double)>[('移动 411dp', 411), ('桌面 1280dp', 1280)]) {
    group(label, () {
      /// 打开模板库并等首轮 load（查库）完成。
      Future<void> openLib(WidgetTester tester) async {
        await pumpShell(tester, width);
        await tapIo(tester, 'open-lib');
        expect(key('timetable-library'), findsOneWidget,
            reason: '$label：模板库弹层没开出来');
      }

      testWidgets('L1 列表渲染：内置模板 + 「默认」标签 + 摘要 + 删除禁用带 tooltip',
          (WidgetTester tester) async {
        await openLib(tester);
        expect(find.text('大学默认'), findsOneWidget);
        expect(find.text('08:00–22:30 · 12 节'), findsOneWidget,
            reason: '§7.3 首末节时间摘要');
        expect(find.text('默认'), findsOneWidget);
        final IconButton del =
            tester.widget<IconButton>(key('tpl-del-$builtinId'));
        expect(del.onPressed, isNull, reason: '内置模板的删除必须禁用');
        expect(find.byTooltip('内置模板不可删除'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$label 出现布局异常');
      });

      testWidgets('L2 使用：默认选中当前学期；应用后节次时间=模板且**复用原行 id**',
          (WidgetTester tester) async {
        final TimeTable short = (await io(tester, () => templates.createTemplate(
            name: '短作息',
            generated: <TimeDetail>[
              TimeDetail(
                  id: '', timetableId: '', section: 1, startMinutes: 500, endMinutes: 545),
              TimeDetail(
                  id: '', timetableId: '', section: 2, startMinutes: 560, endMinutes: 605),
            ])))!;
        final Semester sem = (await io(tester, () => semesters.createSemester(
            name: '测试学期',
            firstWeekDate: DateTime.utc(2026, 8, 31),
            templateId: short.id)))!;
        final List<TimeDetail> before = (await io(tester, () async =>
            env.semesterDao
                .findDetails((await env.semesterDao.findTimetableForSemester(sem.id))!.id)))!;
        expect(before, hasLength(2));
        await openLib(tester);

        await tapPlain(tester, 'tpl-use-$builtinId');
        final DropdownButtonFormField<String> dd = tester
            .widget<DropdownButtonFormField<String>>(key('tpl-apply-semester'));
        expect(dd.initialValue, sem.id, reason: '学期选择默认当前学期（§7.3）');

        await tapIo(tester, 'tpl-apply-confirm');
        expect(find.textContaining('已把「大学默认」的 12 节时间应用到「测试学期」'),
            findsOneWidget,
            reason: '回执必须出现在面板内（lib-said），不许静默');
        final List<TimeDetail> after = (await io(tester, () async =>
            env.semesterDao
                .findDetails((await env.semesterDao.findTimetableForSemester(sem.id))!.id)))!;
        expect(after, hasLength(12));
        expect(after[0].startMinutes, 480);
        expect(after[0].endMinutes, 525);
        expect(after[11].startMinutes, 21 * 60 + 45);
        expect(after[11].endMinutes, 22 * 60 + 30);
        expect(after[0].id, before[0].id,
            reason: 'replaceDetails 按节次复用原 id：否则同步侧把改时间看成一删一增');
        expect(after[1].id, before[1].id);
      });

      testWidgets('L3 快速生成路径：预置 45/10/12 落到可编辑表格，保存入库；预设下拉已删',
          (WidgetTester tester) async {
        await openLib(tester);
        await tapPlain(tester, 'tpl-create');
        await tapPlain(tester, 'tpl-new-gen');
        expect(key('timetable-library'), findsOneWidget);
        expect(key('tt-preset'), findsNothing,
            reason: '§三 末段：预设三档已删成只剩自由参数');
        expect(key('time-1-start'), findsOneWidget,
            reason: '三条新建路都必须落到逐节可编辑的表格');
        await tester.enterText(key('tpl-name'), '生成作息');
        await tester.pump();
        await tapIo(tester, 'tt-save');
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('生成作息'), findsOneWidget);
        final List<TimeTable> tpls = (await io(tester, templates.templates))!;
        final TimeTable created =
            tpls.firstWhere((TimeTable t) => t.name == '生成作息');
        final List<TimeDetail> ds =
            (await io(tester, () => templates.templateDetails(created.id)))!;
        expect(ds, hasLength(12));
        expect(ds[0].startMinutes, 480);
        expect(ds[1].startMinutes, 535, reason: '默认参数 45 分钟 / 课间 10');
      });

      testWidgets('L4 空白建：空草稿时保存禁用，面板内生成后才可保存',
          (WidgetTester tester) async {
        await openLib(tester);
        await tapPlain(tester, 'tpl-create');
        await tapPlain(tester, 'tpl-new-blank');
        expect(key('time-1-start'), findsNothing);
        expect(tester.widget<FilledButton>(key('tt-save')).onPressed, isNull,
            reason: '空草稿没有可保存的东西');
        await tapPlain(tester, 'tt-generate');
        await tapPlain(tester, 'tt-save');
        expect(tester.widget<FilledButton>(key('tt-save')).onPressed, isNotNull);
      });

      testWidgets('L5 复制现有两份互不影响；内置模板保存被拒且错误可见',
          (WidgetTester tester) async {
        await openLib(tester);
        await tapPlain(tester, 'tpl-create');
        await tapPlain(tester, 'tpl-new-copy-$builtinId');
        expect(tester.widget<TextField>(key('tpl-name')).controller!.text,
            '大学默认 副本');
        await tester.enterText(key('time-1-start'), '07:00');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tapIo(tester, 'tt-save');
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('大学默认 副本'), findsOneWidget);
        final List<TimeTable> tpls = (await io(tester, templates.templates))!;
        final TimeTable copy =
            tpls.firstWhere((TimeTable t) => t.name == '大学默认 副本');
        final List<TimeDetail> copyDs =
            (await io(tester, () => templates.templateDetails(copy.id)))!;
        final List<TimeDetail> builtinDs =
            (await io(tester, () => templates.templateDetails(builtinId)))!;
        expect(copyDs[0].startMinutes, 420);
        expect(builtinDs[0].startMinutes, 480, reason: '复制后两份互不影响（§6.2）');
        expect(copyDs, hasLength(12));

        // 内置模板不许改节次：点进编辑直接保存 → 用例层守卫的错误串要显示出来。
        await tapPlain(tester, 'tpl-row-$builtinId');
        expect(tester.widget<TextField>(key('tpl-name')).enabled, isFalse,
            reason: '内置模板不许改名');
        await tapIo(tester, 'tt-save');
        expect(find.byKey(const ValueKey<String>('tpl-edit-said')),
            findsOneWidget);
        expect(tester.widget<Text>(key('tpl-edit-said')).data,
            contains('内置模板不可修改'),
            reason: '用例层守卫的错误串必须显示在编辑面板内，不许静默 return');
        expect(find.byKey(ValueKey<String>('tpl-editor-$builtinId')), findsOneWidget,
            reason: '被拒时编辑页不关闭');
        final List<TimeDetail> still =
            (await io(tester, () => templates.templateDetails(builtinId)))!;
        expect(still[0].startMinutes, 480, reason: '被拒的保存一行都不写');
      });

      testWidgets('L6 设为默认模板（prefs，设备本地）与删除自定义模板',
          (WidgetTester tester) async {
        final TimeTable tmp = (await io(tester, () => templates.createTemplate(
            name: '临时',
            generated: <TimeDetail>[
              TimeDetail(
                  id: '', timetableId: '', section: 1, startMinutes: 480, endMinutes: 525),
            ])))!;
        await openLib(tester);
        expect(find.text('当前默认'), findsNothing);

        await tapPlain(tester, 'tpl-row-${tmp.id}');
        await tapIo(tester, 'tpl-default-${tmp.id}');
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('当前默认'), findsOneWidget,
            reason: '默认那行要有可见标记（§7.3）');
        final SharedPreferences p =
            (await io(tester, SharedPreferences.getInstance))!;
        expect(p.getString('course.defaultTemplateId'), tmp.id,
            reason: '写 prefs、不进库不同步');

        await tapIo(tester, 'tpl-del-${tmp.id}');
        await tapIo(tester, 'tpl-del-confirm');
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('临时'), findsNothing);
        expect(await io(tester, () => env.semesterDao.findTimetableById(tmp.id)),
            isNull);
        expect((await io(tester, () async =>
                env.db.query('time_details',
                    where: 'timetable_id = ?', whereArgs: <Object?>[tmp.id])))!,
            isEmpty,
            reason: '删模板连同节次');
      });
    });
  }
}

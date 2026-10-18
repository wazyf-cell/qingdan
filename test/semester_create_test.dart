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
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// 新建学期（M6-D §7.2）：名称必填、总周数 stepper、作息模板下拉（内置排第一并
/// 标「默认」、默认选中 prefs `course.defaultTemplateId`）、「创建后设为当前学期」
/// 开关，以及**模板的 12 节真的复制进新学期**（查库，不是只看 UI）。
///
/// ★ 碰库的动作一律包 `tester.runAsync`；按钮在假时钟区点、动画靠 `pumpAndSettle`
/// 推，然后立刻回 `runAsync` 轮询到写链跑完（见 `course_week_navigation_test.dart`
/// 头部注释）。411dp 与 1280dp 各 pump 一次（总纲铁律 8）。
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

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

  /// 同 `semester_switcher_test.dart`：同一库的操作按发起顺序排队，本用例连发
  /// N 条查询等回来，就保证界面那条链（含写事务 COMMIT）也走完了。
  Future<void> settle(WidgetTester tester, {int steps = 12}) =>
      io(tester, () async {
        for (int i = 0; i < steps; i++) {
          await semesters.allSemesters();
        }
      });

  Future<void> pumpAt(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await io(tester, () async {
      await semesters.createSemester(
          name: '已有学期', firstWeekDate: DateTime.utc(2025, 8, 4));
      return model.load();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          Provider<SemesterUseCase>.value(value: semesters),
          Provider<TimetableUseCase>.value(value: templates),
          Provider<CourseUseCase>.value(value: CourseUseCase(services)),
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

  Finder byKey(String k) => find.byKey(ValueKey<String>(k));

  /// 走到「新建学期」表单里（面板 → 底部「＋ 新建学期」），并等模板候选读回来。
  Future<void> openCreateForm(WidgetTester tester) async {
    await tester.tap(byKey('semester-switcher'));
    await tester.pumpAndSettle();
    await settle(tester, steps: 4);
    await tester.pumpAndSettle();
    await tester.tap(byKey('semester-create'));
    await tester.pumpAndSettle();
    await settle(tester, steps: 6); // templates() + 每个模板的 templateDetails
    await tester.pumpAndSettle();
  }

  /// 新学期自己那张作息表里的节次行（级联顺序 semester → timetable → time_detail）。
  Future<List<Map<String, Object?>>> detailsOf(
      WidgetTester tester, String semesterId) async {
    final List<Map<String, Object?>>? rows = await io(
        tester,
        () => db.rawQuery(
          'SELECT id, section, start_minutes, end_minutes FROM time_details '
          'WHERE timetable_id IN (SELECT id FROM timetables WHERE semester_id = ?) '
          'ORDER BY section ASC',
            <Object?>[semesterId]));
    return rows ?? const <Map<String, Object?>>[];
  }

  testWidgets('桌面 1280：模板 12 节真的复制进新学期，回执照 §7.2 的措辞',
      (tester) async {
    await pumpAt(tester, width: 1280);
    await openCreateForm(tester);
    // 内置模板排第一并标「默认」。
    expect(find.text('大学默认（默认）'), findsOneWidget);

    await tester.enterText(byKey('create-name'), '2026-2027-2');
    await tester.pump();
    // stepper 从默认 16 抬到 18。
    await tester.tap(byKey('create-weeks-plus'));
    await tester.tap(byKey('create-weeks-plus'));
    await tester.pump();
    expect(tester.widget<Text>(byKey('create-weeks-value')).data, '18');

    await tester.tap(byKey('create-save'));
    await tester.pump();
    await settle(tester);
    await tester.pumpAndSettle();
    expect(
        find.text('已创建「2026-2027-2」，作息来自「大学默认」（12 节）'),
        findsOneWidget,
        reason: '回执在弹层里（不是 SnackBar，模态弹层下面看不见）');

    final List<Semester> all = (await io(tester, semesters.allSemesters))!;
    final Semester created =
        all.firstWhere((Semester s) => s.name == '2026-2027-2');
    expect(created.totalWeeks, 18);
    expect(created.isActive, isTrue, reason: '「创建后设为当前学期」默认开');
    expect(model.semester?.id, created.id);

    // 查库：新学期自己那张作息表里必须真的躺着 12 行，内容与内置一致。
    final List<Map<String, Object?>> rows = await detailsOf(tester, created.id);
    expect(rows.length, kBuiltInTimeDetails.length);
    expect(rows.first['section'], 1);
    expect(rows.first['start_minutes'], 480);
    expect(rows.last['section'], kBuiltInTimeDetails.length);
    expect((await io(tester, () => db.query('op_log',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>['time_detail', rows.first['id']])))!
        .isNotEmpty,
        isTrue,
        reason: '复制出来的节次要能被同步带走（同事务记意图）');
  });

  testWidgets('学期名为空时不给保存（必填）', (tester) async {
    await pumpAt(tester, width: 1280);
    await openCreateForm(tester);
    expect(find.text('必填'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(byKey('create-save')).onPressed, isNull,
        reason: '名字没填就不能点保存');

    await tester.enterText(byKey('create-name'), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(byKey('create-save')).onPressed, isNull,
        reason: '只有空格也算没填');

    await tester.enterText(byKey('create-name'), '有名字了');
    await tester.pump();
    expect(tester.widget<FilledButton>(byKey('create-save')).onPressed, isNotNull);
  });

  testWidgets('prefs 里的默认模板会被选中；关掉开关时当前学期不变', (tester) async {
    await pumpAt(tester, width: 1280);
    // 先做一份自定义模板，再把 prefs 指向它（prefs 是设备本地偏好，不进同步）。
    final String customId = (await io(tester, () async {
      final TimeTable t = await templates.createTemplate(
          name: '晚间作息', copyFromId: kBuiltInTimetableId);
      SharedPreferences.setMockInitialValues(
          <String, Object>{'course.defaultTemplateId': t.id});
      return t.id;
    }))!;

    await openCreateForm(tester);
    expect(find.text('晚间作息（12 节）'), findsOneWidget,
        reason: '默认选中 prefs course.defaultTemplateId（$customId）');

    await tester.enterText(byKey('create-name'), '关掉自动切换的学期');
    await tester.pump();
    await tester.tap(byKey('create-set-active')); // 默认开 → 关掉
    await tester.pump();
    await tester.tap(byKey('create-save'));
    await tester.pump();
    await settle(tester);
    await tester.pumpAndSettle();

    final List<Semester> all = (await io(tester, semesters.allSemesters))!;
    final Semester fresh =
        all.firstWhere((Semester s) => s.name == '关掉自动切换的学期');
    expect(fresh.isActive, isFalse, reason: '开关关了就不该抢当前学期');
    expect(model.semester?.name, '已有学期', reason: '周视图仍读原来那个学期');
    expect((await detailsOf(tester, fresh.id)).length, 12,
        reason: '没设为当前也要把模板的节次复制进去');
  });

  testWidgets('手机 411dp：新建流程同样走得通，且不溢出', (tester) async {
    await pumpAt(tester, width: 411);
    await openCreateForm(tester);
    expect(byKey('create-save'), findsOneWidget);

    await tester.enterText(byKey('create-name'), '手机建的学期');
    await tester.pump();
    await tester.tap(byKey('create-save'));
    await tester.pump();
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('已创建「手机建的学期」，作息来自「大学默认」（12 节）'),
        findsOneWidget);
    expect(tester.takeException(), isNull, reason: '移动端不得有 RenderFlex 溢出');
    expect((await detailsOf(tester, model.semester!.id)).length, 12);
  });
}

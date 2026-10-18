import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/features/course/course_block.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'dao_test_helper.dart';

/// F28 端到端：**用界面**建学期 → 生成并保存作息 → 手工录入一门课 → 周视图出现课程块。
///
/// 这是 F28 验收原文（「可手工新建一个学期与一套作息时间表并录入 1 门课，
/// 周视图正确显示」）的直接覆盖：全程点按钮，不直接调用例层。
void main() {
  ensureSqfliteFfi();

  late Database db;
  late SemesterUseCase semesters;
  late CourseUseCase courses;
  late CoursePaneModel model;

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
    model = CoursePaneModel(semesterUseCase: semesters, courseUseCase: courses);
  });

  tearDown(() async => db.close());

  /// 点一个会触发查库的控件：tap 与等待都放在真实异步区里，
  /// 否则 sqflite 的 future 在 FakeAsync 区永不完成（本文件第一版挂死在这里）。
  Future<void> tapIo(WidgetTester tester, String key) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
  }

  Future<void> pumpPane(WidgetTester tester, {double width = 1280}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
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

  /// 用**例层**把数据写进库（provider 装配与本文件其余用例同一套）。
  /// 查库必须包在 runAsync 里，且 runAsync 内不排任何 timer。
  Future<void> seedData(WidgetTester tester, {bool withCourse = true}) async {
    await tester.runAsync(() async {
      final semester = await semesters.createSemester(
          name: '2026-2027-1', firstWeekDate: DateTime.utc(2026, 8, 31));
      if (withCourse) {
        await courses.create(
            name: '高等数学',
            weekday: 1,
            startSection: 1,
            endSection: 2,
            weeks: <int>[1, 2],
            semesterId: semester.id);
      }
      await model.load();
    });
  }

  /// 「学期与作息」弹层里那一行导出近路（§9.2「高频操作要有近路」）。
  Finder exportRow() => find.byKey(const ValueKey<String>('setup-export'));

  /// 数据不齐时那一行必须是**看得懂的禁用**：`enabled:false` + 摘掉 onTap +
  /// 副文案写清原因 + 不许溢出屏幕。
  void expectDisabledRow(WidgetTester tester, String reason, double width) {
    expect(exportRow(), findsOneWidget, reason: '$width 上没有导出近路');
    final ListTile tile = tester.widget<ListTile>(exportRow());
    expect(tile.enabled, isFalse, reason: '$width 上数据不齐却给了个能点的行');
    expect(tile.onTap, isNull, reason: '$width 上禁用了还留着 onTap = 死按钮');
    expect(find.textContaining(reason), findsOneWidget,
        reason: '$width 上没写清现在为什么不能导');
    expect(tester.getRect(exportRow()).right, lessThanOrEqualTo(width),
        reason: '$width 上这一行溢出屏幕');
    expect(tester.takeException(), isNull, reason: '$width 出现布局异常');
  }

  Future<void> closeTopSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 20)); // 点遮罩
    await tester.pumpAndSettle();
  }

  testWidgets('F28 端到端：建学期 → 保存作息 → 加课 → 周视图渲染课程块',
      (tester) async {
    await pumpPane(tester);

    // ① 空态与入口
    expect(find.text('还没有学期，先建一个学期和作息表'), findsOneWidget);
    await tapIo(tester, 'empty-create-semester');
    await tester.pumpAndSettle();

    // ② 建学期（名称已按当前日期建议好，日期默认今天 → 归一到本周一）
    expect(find.byKey(const ValueKey<String>('semester-save')), findsOneWidget);
    await tapIo(tester, 'semester-save');
    await tester.pumpAndSettle();
    expect(model.hasSemester, isTrue);

    // ③ 生成作息预览并保存
    await tapIo(tester, 'tt-generate');
    await tester.pumpAndSettle();
    // 只断言首行在视口内：列表被限高 240dp，第 12 行是懒加载没渲染，
    // 条数由保存后的 model.details 兜底断言。
    expect(find.byKey(const ValueKey<String>('tt-row-1')), findsOneWidget);
    await tapIo(tester, 'tt-save');
    await tester.pumpAndSettle();
    expect(model.details, hasLength(12));

    // ④ 完成，回到周视图
    await tapIo(tester, 'setup-done');
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 周'), findsWidgets);
    expect(find.text('08:00'), findsWidgets, reason: '节次轴显示每节开始时间');

    // ⑤ 手工加一门课
    await tapIo(tester, 'btn-add-course');
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey<String>('field-name')), '高等数学');
    await tester.pump();
    await tapIo(tester, 'week-1');
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey<String>('field-location')), '逸夫楼201');
    await tester.pump();
    await tapIo(tester, 'btn-save');
    // 保存链路里有真实 DB 异步，用真延时 + 单帧推进代替 pumpAndSettle
    //（pumpAndSettle 会一直等一个跨 FakeAsync 区边界的 future，卡到测试超时）。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // ⑥ 课程块出现在周视图，且带地点
    expect(find.byType(CourseBlock), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('逸夫楼201'), findsOneWidget);
  });

  testWidgets('学期没建完前不给添加课程入口（不留死按钮）', (tester) async {
    await pumpPane(tester);
    expect(find.byKey(const ValueKey<String>('btn-add-course')), findsNothing);
    expect(find.byKey(const ValueKey<String>('btn-setup')), findsNothing);
  });

  testWidgets('作息校验不过时不保存：重叠的两节被拦在面板里', (tester) async {
    await pumpPane(tester);
    await tapIo(tester, 'empty-create-semester');
    await tester.pumpAndSettle();
    await tapIo(tester, 'semester-save');
    await tester.pumpAndSettle();
    await tapIo(tester, 'tt-generate');
    await tester.pumpAndSettle();

    // 把第 2 节的开始时间改到第 1 节结束之前 → 保存必须被拦下。
    final Finder cell =
        find.byKey(const ValueKey<String>('time-2-start'));
    await tester.enterText(cell, '07:00');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tapIo(tester, 'tt-save');
    await tester.pumpAndSettle();

    expect(model.details, isEmpty, reason: '校验失败一行都不写');
    expect(find.textContaining('重叠'), findsOneWidget);
  });

  testWidgets('导出近路 · 桌面 1280：有学期有课时可点，点开的是 export_sheet 那一份',
      (tester) async {
    await seedData(tester);
    await pumpPane(tester);
    await tapIo(tester, 'btn-setup');
    await tester.pumpAndSettle();

    expect(tester.widget<ListTile>(exportRow()).enabled, isTrue);
    expect(tester.widget<ListTile>(exportRow()).onTap, isNotNull);

    await tapIo(tester, 'setup-export');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('export-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('export-count')), findsOneWidget);

    // 先关掉层再收尾：退场动画里 dispose 控制器会红屏 `_dependents.isEmpty`。
    await tapIo(tester, 'export-close');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('export-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导出近路 · 窄屏 411：整行在屏内不溢出，照样点得开', (tester) async {
    await seedData(tester);
    await pumpPane(tester, width: 411);
    await tapIo(tester, 'btn-setup');
    await tester.pumpAndSettle();

    expect(tester.widget<ListTile>(exportRow()).enabled, isTrue);
    final Rect row = tester.getRect(exportRow());
    expect(row.left, greaterThanOrEqualTo(0));
    expect(row.right, lessThanOrEqualTo(411), reason: '411dp 上这一行溢出屏幕');
    expect(tester.takeException(), isNull, reason: '411dp 出现布局异常');

    await tapIo(tester, 'setup-export');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('export-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '411dp 上导出弹层自身溢出');
  });

  testWidgets('导出近路 · 还没有学期：禁用并写明原因（411 与 1280 各一次）',
      (tester) async {
    for (final double width in <double>[411, 1280]) {
      // 空态那颗「建学期」进的就是同一个弹层，所以这里也能看见那一行。
      await pumpPane(tester, width: width);
      await tapIo(tester, 'empty-create-semester');
      await tester.pumpAndSettle();
      expectDisabledRow(tester, '导出无从取数据', width);

      await tapIo(tester, 'setup-export'); // 禁用行点下去什么也不该开
      expect(find.byKey(const ValueKey<String>('export-sheet')), findsNothing);
      await closeTopSheet(tester);
    }
  });

  testWidgets('导出近路 · 有学期但还没课：原因写的是「空文件」（411 与 1280 各一次）',
      (tester) async {
    await seedData(tester, withCourse: false);
    for (final double width in <double>[411, 1280]) {
      await pumpPane(tester, width: width);
      await tapIo(tester, 'btn-setup');
      await tester.pumpAndSettle();
      expectDisabledRow(tester, '导出会是空文件', width);
      await closeTopSheet(tester);
    }
  });
}

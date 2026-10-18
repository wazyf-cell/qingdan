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
}

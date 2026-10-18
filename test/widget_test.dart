import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/app.dart';
import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/task_list_use_case.dart';
import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late AppServices services;
  late TaskListUseCase listUseCase;
  late TaskUseCase taskUseCase;
  late SidebarModel sidebar;
  late TaskPaneModel paneModel;

  setUp(() async {
    // 真实异步（sqflite_ffi）必须在 FakeAsync 区（testWidgets 体内）之外完成，
    // 否则 future 永不完成、测试挂死。
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
    listUseCase = TaskListUseCase(services);
    taskUseCase = TaskUseCase(services);
    sidebar = SidebarModel(listUseCase: listUseCase);
    await sidebar.load();
    paneModel = TaskPaneModel(useCase: taskUseCase, sidebar: sidebar);
    await paneModel.load();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('应用壳冒烟：渲染三栏（侧栏 + 列表 + 详情）', (WidgetTester tester) async {
    // 默认测试表面 800×600 落在两栏档；设为 1280×800（≥1040）验证三栏形态。
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<TaskListUseCase>.value(value: listUseCase),
          Provider<TaskUseCase>.value(value: taskUseCase),
          ChangeNotifierProvider<SidebarModel>.value(value: sidebar),
          ChangeNotifierProvider<TaskPaneModel>.value(value: paneModel),
        ],
        child: const QingdanApp(),
      ),
    );
    await tester.pump();

    // 侧栏渲染智能清单与回收站入口；列表区渲染当前视图标题（默认「今天」）。
    expect(find.text('今天'), findsWidgets);
    expect(find.text('回收站'), findsWidgets);
  });
}

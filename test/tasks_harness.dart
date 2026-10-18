import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/app.dart';
import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/task_list_use_case.dart';
import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/sync/sync_coordinator.dart';

import 'dao_test_helper.dart';
import 'sync_fakes.dart';

/// 窄屏清单页 / 快捷抽屉共用的 widget 测试环境（真库 + 全套 provider，
/// 装配形状与 `main.dart` 一致）。
///
/// ★ 两条铁律（`mobile_tasks_page_test.dart` 第一版各挂过一次）：
/// 1. 碰库的动作必须在 `tester.runAsync`（本类的 [io] / [tapIo]）里做：FakeAsync
///    区不推进真实事件循环，`sidebar.load()` 放进小区就是整条测试挂死；留在小区里
///    的查库续体会在 `tearDown` 关库之后才抛 `database_closed`。
/// 2. 弹层/对话框按钮的 `onSelected` 跑在路由 pop 的 await 续体里，同样必须真实
///    异步区点并等（400ms 是给菜单退场动画留的，260ms 时回收站那条点了没反应）。
class TasksHarness {
  TasksHarness();

  late Database db;
  late TaskListUseCase listUseCase;
  late TaskUseCase taskUseCase;
  late SidebarModel sidebar;
  late TaskPaneModel paneModel;
  late ChaoxingModel chaoxing;
  late SettingsModel settings;
  late SyncStatusModel syncStatus;

  /// 「毕设」测试清单 id（「交开题」挂在它上面，删除用例会真删它）。
  late String gradId;

  static void boot() => ensureSqfliteFfi();

  Future<void> start() async {
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
    listUseCase = TaskListUseCase(services);
    taskUseCase = TaskUseCase(services);
    // 数据全在这里（真实异步区）造好，再 load()：顺序反了 chip 与角标计数就是旧的。
    final TaskList grad = await listUseCase.create(name: '毕设', sortOrder: 1);
    gradId = grad.id;
    await taskUseCase.create(title: '买牛奶', dueDate: DateTime.now());
    await taskUseCase.create(title: '交开题', listId: gradId);
    sidebar = SidebarModel(listUseCase: listUseCase);
    await sidebar.load();
    paneModel = TaskPaneModel(useCase: taskUseCase, sidebar: sidebar);
    await paneModel.load();
    chaoxing = ChaoxingModel(secure: InMemorySecureStore());
    settings = SettingsModel();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    syncStatus = SyncStatusModel(
      coordinator: SyncCoordinator(
        configStore: SyncConfigStore(
            prefs: await SharedPreferences.getInstance()),
        runnerFactory: FakeFactory(CountingRunner()),
        timers: FakeTimers(),
      ),
      deviceId: 'tasks-harness',
    );
  }

  Future<void> stop() => db.close();

  Future<T?> io<T>(WidgetTester tester, Future<T> Function() body) =>
      tester.runAsync<T>(body);

  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<TaskListUseCase>.value(value: listUseCase),
          Provider<TaskUseCase>.value(value: taskUseCase),
          ChangeNotifierProvider<SidebarModel>.value(value: sidebar),
          ChangeNotifierProvider<TaskPaneModel>.value(value: paneModel),
          ChangeNotifierProvider<ChaoxingModel>.value(value: chaoxing),
          ChangeNotifierProvider<SettingsModel>.value(value: settings),
          ChangeNotifierProvider<SyncStatusModel>.value(value: syncStatus),
        ],
        child: const QingdanApp(),
      ),
    );
    await tester.pump();
  }

  /// 点一下并等真实异步落地（切视图、写库、弹层回调都靠它）。
  Future<void> tapIo(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    await io(tester, () async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
  }

  Finder key(String id) => find.byKey(ValueKey<String>(id));

  String textOf(WidgetTester tester, String id) =>
      tester.widget<Text>(key(id)).data ?? '';

  ChoiceChip chipOf(WidgetTester tester, String viewId) => tester
      .widget<ChoiceChip>(find.ancestor(
          of: key('chip:$viewId'), matching: find.byType(ChoiceChip)));

  /// 打开「清单列表」半屏面板。
  /// M6-A2 起顶栏改成三个图标按钮，入口 key 从文本上的 `listSwitcher` 换成
  /// `btn-lists`；面板本体（`list_sheet.dart`）与用例逻辑没变。
  Future<void> openSheet(WidgetTester tester) => tapIo(tester, key('btn-lists'));
}

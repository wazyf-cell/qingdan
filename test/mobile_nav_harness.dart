// 窄屏壳形态测试的共用夹具（自 `mobile_nav_test.dart` 拆出；非 `_test` 文件，
// flutter test 不直接执行）。
//
// 拆分后的两份文件：
//  - `mobile_nav_shell_test.dart` —— 窄屏：底部 4 页签 / 页签与视图互相同步 /
//    「＋」快捷添加抽屉 / 点行进全屏详情 / 回收站工具行
//  - `mobile_nav_breakpoint_badge_test.dart` —— 两栏图标栏、三栏形态、底部角标配色
//
// 夹具与时序常数字字照搬。与 `tasks_harness.dart` 不共用：那份的种子多一个
// 「毕设」清单和「交开题」任务，会让本页的角标计数与「买牛奶」断言变形。
library;

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
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/sync/sync_coordinator.dart';

import 'sync_fakes.dart';

// 页标题用 key 定位：任务行的到期日也渲染成「今天」，按文案找会撞车。
final Finder paneTitle = find.byKey(const ValueKey<String>('paneTitle'));
final Finder topBarTitle = find.byKey(const ValueKey<String>('topBarTitle'));

String titleOf(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).data ?? '';

class MobileNavHarness {
  MobileNavHarness();

  late Database db;
  late TaskListUseCase listUseCase;
  late TaskUseCase taskUseCase;
  late SidebarModel sidebar;
  late TaskPaneModel paneModel;
  late ChaoxingModel chaoxing;
  late SettingsModel settings;
  late SyncStatusModel syncStatus;

  /// 原 `setUp` 的 body，顺序一字未动。
  static Future<MobileNavHarness> open() async {
    final MobileNavHarness h = MobileNavHarness();
    // 真实异步（sqflite_ffi）必须在 FakeAsync 区之外完成，否则测试挂死。
    h.db = await databaseFactory.openDatabase(
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
    final AppServices services = AppServices(db: h.db);
    h.listUseCase = TaskListUseCase(services);
    h.taskUseCase = TaskUseCase(services);
    h.sidebar = SidebarModel(listUseCase: h.listUseCase);
    // 种一条「今天」到期的任务（listId 为 NULL 即收集箱）：
    // 窄屏点行进详情的用例需要一条真实的行，角标用例需要它已经算进 todayCount，
    // 所以必须在 load() **之前**建，否则侧栏计数是 0。
    await h.taskUseCase.create(title: '买牛奶', dueDate: DateTime.now());
    await h.sidebar.load();
    h.paneModel =
        TaskPaneModel(useCase: h.taskUseCase, sidebar: h.sidebar);
    await h.paneModel.load();
    // 清单页「今天」视图顶部的到期提示条读 ChaoxingModel（真机由 main.dart 注入）。
    h.chaoxing = ChaoxingModel(secure: InMemorySecureStore());
    h.settings = SettingsModel();
    // 顶栏右侧的同步状态槽读 SyncStatusModel（真机由 main.dart 注入）。
    // 本文件不测同步行为，给一个「同步未配置」的协调器就够。
    // 壳类用例要的是「已经看过首启引导」的稳态：引导框由
    // `first_run_guide_test.dart` 专门测，留在这里会盖住每一个点击。
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsModel.kGuideSeenKey: true,
    });
    // 必须 load()：`guideSeen` 只在 load 里从 prefs 读，光造对象仍是 false，
    // 于是首启引导会在每一个壳用例里弹出来盖住点击。
    await h.settings.load();
    h.syncStatus = SyncStatusModel(
      coordinator: SyncCoordinator(
        configStore: SyncConfigStore(
            prefs: await SharedPreferences.getInstance()),
        runnerFactory: FakeFactory(CountingRunner()),
        timers: FakeTimers(),
      ),
      deviceId: 'nav-test',
    );
    return h;
  }

  Future<void> close() async {
    await db.close();
  }

  Future<void> pumpAtWidth(WidgetTester tester, double width,
      {String? viewId}) async {
    // 视图在首次 pump 前设定：viewId 是同步 getter，可避开 FakeAsync 区内
    // DB future 不完成导致的「不重建」，让断言落在布局而非异步时序上。
    if (viewId != null) sidebar.selectedId = viewId;
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
          // 底部角标读它（定案第 10 条）：默认 showBadges = true，不调 load。
          ChangeNotifierProvider<SettingsModel>.value(value: settings),
          ChangeNotifierProvider<SyncStatusModel>.value(value: syncStatus),
        ],
        child: const QingdanApp(),
      ),
    );
    await tester.pump();
  }
}

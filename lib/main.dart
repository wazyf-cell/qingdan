import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:window_manager/window_manager.dart';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/task_list_use_case.dart';
import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/app.dart';
import 'package:qingdan/data/database.dart';
import 'package:qingdan/data/device_id.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/sync/sync_coordinator.dart';
import 'package:qingdan/sync/sync_runner.dart';

import 'package:qingdan/theme/theme_mode_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 主题持久化：启动时恢复上次选择（失败仅回退跟随系统，不阻塞启动）。
  final ThemeModeModel themeModel = ThemeModeModel(ThemeMode.system);
  try {
    await themeModel.loadPersisted();
  } catch (e) {
    debugPrint('主题持久化读取失败，回退跟随系统：$e');
  }

  // 界面偏好（默认页签 / 角标开关，M5 定案第 2、10 条）：同样是「读不到就用默认值」。
  final SettingsModel settingsModel = SettingsModel();
  try {
    await settingsModel.load();
  } catch (e) {
    debugPrint('界面偏好读取失败，用默认值：$e');
  }


  // Windows 桌面窗口：初始 1280×800（≥1040 可见三栏形态），最小 720×480。
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const WindowOptions options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(720, 480),
      title: 'qingdan',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 数据库初始化失败不静默：错误原文传给根组件渲染失败页。
  String? dbInitError;
  TaskListUseCase? listUseCase;
  TaskUseCase? taskUseCase;
  SidebarModel? sidebarModel;
  TaskPaneModel? paneModel;
  CoursePaneModel? courseModel;
  SemesterUseCase? semesterUseCase;
  CourseUseCase? courseUseCase;
  ImportService? importService;
  SyncCoordinator? syncCoordinator;
  SyncStatusModel? syncStatusModel;
  SyncConfigStore? syncConfigStore;
  ChaoxingModel? chaoxingModel;
  try {
    final db = await openAppDatabase();

    // 同步协调器先建：其本地写回调要注入 AppServices（op-log 是全项目本地
    // 写的唯一汇聚点，见 M3 方案设计 §2.1）。
    //
    // 配置存储必须提成变量：协调器读写它、设置界面也要经 provider 读它，
    // 两边必须是**同一个实例**（否则设置里保存的配置协调器看不到）。
    final SyncConfigStore configStore = SyncConfigStore();
    final SyncCoordinator coordinator = SyncCoordinator(
      configStore: configStore,
      runnerFactory: WebDavSyncRunnerFactory(db: db),
    );
    syncCoordinator = coordinator;
    syncConfigStore = configStore;

    final AppServices services = AppServices(
      db: db,
      onLocalWrite: coordinator.notifyLocalChange,
    );
    listUseCase = TaskListUseCase(services);
    taskUseCase = TaskUseCase(services);
    sidebarModel = SidebarModel(listUseCase: listUseCase);
    // 侧栏数据加载失败同样呈现（load 内部已记录 error 后 rethrow）。
    await sidebarModel.load();
    // 默认页签要在建 TaskPaneModel 之前摆好：它的构造函数会挂上视图监听，
    // 之后每次切视图都自动重载。
    sidebarModel.applyDefaultTab(settingsModel.defaultTab);
    paneModel = TaskPaneModel(useCase: taskUseCase, sidebar: sidebarModel);
    await paneModel.load();

    // 课表域（M4a）：用例 + 周视图状态模型。不在启动时 load()——
    // 首次打开课表面板时才拉数据（CoursePane.initState 触发）。
    semesterUseCase = SemesterUseCase(services);
    courseUseCase = CourseUseCase(services);
    courseModel = CoursePaneModel(
        semesterUseCase: semesterUseCase, courseUseCase: courseUseCase);
    // 导入服务在装配根里建：它要拿 CourseDao，而 UI 层不许碰 DAO。
    importService = ImportService(services.courseDao);

    // 设备标识：详情卡展示用；顺带确保其在库中就位（同步引擎也会用它）。
    final String deviceId = await DeviceId.ensureDeviceId(db);
    syncStatusModel =
        SyncStatusModel(coordinator: coordinator, deviceId: deviceId);
    coordinator.start();

    // 学习通（外部只读待办）：cookie 走系统凭据库，与同步层同一个 SecureStore
    // 实现。启动只恢复「有没有登录过」，不自动拉取——拉取发生在打开面板时。
    chaoxingModel = ChaoxingModel(secure: SecureStorageStore());
    await chaoxingModel.restore();

    // Windows 关窗钩子（M3 §2.1）：先同步一次（10s 超时兜底）再真正退出。
    if (Platform.isWindows) {
      _installWindowsCloseHook(coordinator);
    }
  } catch (e, st) {
    dbInitError = '$e\n$st';
  }

  runApp(
    MultiProvider(
      providers: <SingleChildWidget>[
        if (listUseCase != null)
          Provider<TaskListUseCase>.value(value: listUseCase),
        if (taskUseCase != null)
          Provider<TaskUseCase>.value(value: taskUseCase),
        if (semesterUseCase != null)
          Provider<SemesterUseCase>.value(value: semesterUseCase),
        if (courseUseCase != null)
          Provider<CourseUseCase>.value(value: courseUseCase),
        if (importService != null)
          Provider<ImportService>.value(value: importService),
        if (chaoxingModel != null)
          ChangeNotifierProvider<ChaoxingModel>.value(value: chaoxingModel),
        // 设置页的「通用」节与底部角标都读它；漏注册会让点开设置直接抛
        // ProviderNotFoundException（SyncConfigStore 就是这么栽过一次）。
        ChangeNotifierProvider<SettingsModel>.value(value: settingsModel),
        if (courseModel != null)
          ChangeNotifierProvider<CoursePaneModel>.value(value: courseModel),
        if (sidebarModel != null) ...<SingleChildWidget>[
          ChangeNotifierProvider<SidebarModel>.value(value: sidebarModel),
          if (paneModel != null)
            ChangeNotifierProvider<TaskPaneModel>.value(value: paneModel),
          if (syncStatusModel != null)
            ChangeNotifierProvider<SyncStatusModel>.value(value: syncStatusModel),
        ],
        if (syncCoordinator != null)
          Provider<SyncCoordinator>.value(value: syncCoordinator),
        // 设置界面的「同步」节经 provider 读它（sync_section.dart 的
        // context.read<SyncConfigStore>()）。漏注册会让点开设置直接抛
        // ProviderNotFoundException —— 单测里是手工注入 provider 的，
        // 所以这类装配缺失在测试里看不出来。
        if (syncConfigStore != null)
          Provider<SyncConfigStore>.value(value: syncConfigStore),
      ],
      child: QingdanApp(dbInitError: dbInitError, themeModel: themeModel),
    ),
  );
}

/// Windows 关窗 = 退出：拦截关闭 → 触发一次同步（封顶 10s）→ destroy。
///
/// 监听器实例存进顶层变量（而非临时对象）——window_manager 的 addListener
/// 若收到会被 GC 的临时对象，回调会静默失效（该库的已知坑）。
_WindowCloseSyncHook? _windowCloseHook;

void _installWindowsCloseHook(SyncCoordinator coordinator) {
  windowManager.setPreventClose(true);
  _windowCloseHook = _WindowCloseSyncHook(coordinator);
  windowManager.addListener(_windowCloseHook!);
}

/// 关窗同步钩子（见 [_installWindowsCloseHook]）。
class _WindowCloseSyncHook with WindowListener {
  _WindowCloseSyncHook(this._coordinator);

  final SyncCoordinator _coordinator;
  bool _closing = false;

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await _coordinator.syncNow().timeout(const Duration(seconds: 10));
    } catch (_) {
      // 超时或失败都不阻塞退出：数据留在本地 op-log，下次启动兜底再传。
    }
    await windowManager.destroy();
  }
}

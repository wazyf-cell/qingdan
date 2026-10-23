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
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/application/trash_purge_scheduler.dart';
import 'package:qingdan/app.dart';
import 'package:qingdan/app_lifecycle.dart';
import 'package:qingdan/data/database.dart';
import 'package:qingdan/data/device_id.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/shell/nav_router.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/features/widgets/widget_snapshot_service.dart';
import 'package:qingdan/notify/chaoxing_snapshot.dart';
import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/notify/reminder_coordinator.dart';
import 'package:qingdan/platform/nav_intents.dart';
import 'package:qingdan/windows_close_hook.dart';
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

  // ── 通知（M6-C2）：只在 Android 生效（§0.1）。这三件都必须**照常启动**：
  // Windows 上 initialize() 走不通、prefs 读不到、插件通道缺失，统统只打一行日志。
  final NotificationService notificationService = NotificationService();
  // 路由器要点通知时才用得到侧栏与任务面板模型，而那两者在建库成功后才有；
  // 回调捕获的是这个局部变量，运行时（点通知）早已装配完毕。
  NotificationRouter? notificationRouter;
  // 长按快捷方式的路由器：与通知路由器一样，回调捕获局部变量，运行时早已装配。
  NavRouter? navRouter;
  try {
    await notificationService.initialize(
        onResponse: (response) => notificationRouter?.handle(response.payload));
  } catch (e) {
    debugPrint('通知初始化失败，提醒功能本次会话不可用：${e.runtimeType}');
  }
  final NotifySettingsStore notifySettings = NotifySettingsStore();
  try {
    await notifySettings.load();
  } catch (e) {
    debugPrint('通知设置读取失败，用默认值：${e.runtimeType}');
  }
  final ChaoxingSnapshotStore chaoxingSnapshot = ChaoxingSnapshotStore();


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
  // 作息模板库用例：导入向导步 3 的「换成某个模板」下拉要读模板列表
  // （SyncConfigStore 漏注册栽过跟头，装配了就必须在 provider 树里）。
  TimetableUseCase? timetableUseCase;
  ImportService? importService;
  SyncCoordinator? syncCoordinator;
  SyncStatusModel? syncStatusModel;
  SyncConfigStore? syncConfigStore;
  ChaoxingModel? chaoxingModel;
  TrashPurgeScheduler? trashPurgeScheduler;
  ReminderCoordinator? reminderCoordinator;
  WidgetSnapshotService? widgetSnapshots;
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

    // 课表域（M4a）：用例 + 周视图状态模型。
    // **启动时就 load**（2026-10-19 改）：以前等首次打开课表面板才拉数据，于是
    // 「默认页签=清单」的冷启动下，设置 → 课表 → 导出课表文件 会禁用并写着
    // 「还没有学期或还没有课」——而库里其实有学期和 30 门课。禁用行的理由必须是
    // 真的（M5 定案：要么说清原因，要么别出现），拿「还没装配」当理由就是假理由。
    semesterUseCase = SemesterUseCase(services);
    // 作息模板库（M6-D §6.2/§7.2）：新建学期要选模板，漏注册会让那一节静默不可用
    // （SyncConfigStore 就是这么栽过的）。
    courseUseCase = CourseUseCase(services);
    timetableUseCase = TimetableUseCase(services);
    courseModel = CoursePaneModel(
        semesterUseCase: semesterUseCase, courseUseCase: courseUseCase);
    await courseModel.load();
    // 导入服务在装配根里建：它要拿 CourseDao，而 UI 层不许碰 DAO。
    importService = ImportService(services.courseDao);

    // 设备标识：详情卡展示用；顺带确保其在库中就位（同步引擎也会用它）。
    final String deviceId = await DeviceId.ensureDeviceId(db);
    syncStatusModel =
        SyncStatusModel(coordinator: coordinator, deviceId: deviceId);
    coordinator.start();

    // 回收站自动清空（M6-A4）：启动时检查一次 + 应用存活期每 30 分钟一次。
    // **无后台真定时**（Android 会被杀，需求已确认接受）；首轮内部有 try/catch，
    // 不 await 也不阻塞 runApp。独立于 SyncCoordinator：同步关掉回收站照样清。
    trashPurgeScheduler = TrashPurgeScheduler(
      useCase: taskUseCase,
      settings: settingsModel,
    );
    trashPurgeScheduler.start();

    // 学习通（外部只读待办）：cookie 走系统凭据库，与同步层同一个 SecureStore
    // 实现。启动只恢复「有没有登录过」，不自动拉取——拉取发生在打开面板时。
    final ChaoxingModel chaoxing = ChaoxingModel(secure: SecureStorageStore());
    await chaoxing.restore();
    chaoxingModel = chaoxing;

    // 桌面小组件（v1.0.6）：把三份快照写进 SharedPreferences 供原生 RemoteViews 读。
    // 数据源任一变化就重写（600ms 防抖）；放在装配根而不是壳里，三栏/窄屏共用。
    widgetSnapshots = WidgetSnapshotService(
      taskUseCase: taskUseCase,
      semesterUseCase: semesterUseCase,
      courseUseCase: courseUseCase,
      chaoxing: chaoxing,
    )..attach(<Listenable>[paneModel, sidebarModel, courseModel, chaoxing]);

    // 提醒装配（M6-C2 §6）：C4 §2 的写入时机 = refresh 成功后；筛选函数在
    // `reminder_coordinator.dart`，落盘走 `ChaoxingSnapshotStore`（prefs，不进库）。
    chaoxing.onReminderSnapshot = (tasks, hidden, now) async {
      await chaoxingSnapshot
          .writeSnapshot(chaoxingSnapshotOf(tasks, hidden, now));
    };
    // 变更源：任务面板（创建/改/完成/删除/进回收站都会 notify）+ 侧栏（回收站
    // 「恢复」只走 TrashPane→SidebarModel.load，不经任务面板，漏了它恢复出来的
    // 任务要等下次切视图才会重新排提醒）+ 学习通（refresh 结束会 notify）。
    // 通知设置本身的 notify 由协调器自己订阅。
    reminderCoordinator = ReminderCoordinator(
      service: notificationService,
      settings: notifySettings,
      snapshot: chaoxingSnapshot,
      taskSource: taskUseCase.findAllActive,
      sources: <Listenable>[paneModel, sidebarModel, chaoxing],
    );
    notificationRouter = NotificationRouter(sidebar: sidebarModel, pane: paneModel);
    navRouter = NavRouter(
      sidebar: sidebarModel,
      pane: paneModel,
      navigatorKey: appNavigatorKey,
    );

    // Windows 关窗钩子（M3 §2.1）：先同步一次（10s 超时兜底）再真正退出。
    if (Platform.isWindows) {
      installWindowsCloseHook(coordinator, trashPurgeScheduler);
    }
  } catch (e, st) {
    dbInitError = '$e\n$st';
  }

  // 触发点「从后台回到前台」→ 重排提醒（项目第一个 WidgetsBindingObserver）。
  // 协调器缺席（建库失败）时也要挂：它只发一次空回调，不排任何提醒。
  final ReminderCoordinator? reminder = reminderCoordinator;
  // 回到前台顺带重写小组件快照：跨过零点后「今天」换了，这正是它变旧的时刻。
  final WidgetSnapshotService? widgetRefresh = widgetSnapshots;
  final AppLifecycleObserver lifecycle = AppLifecycleObserver(onResume: () {
    reminder?.notifyChanged();
    widgetRefresh?.refresh();
  });
  lifecycle.attach();
  reminder?.start(); // 内含「应用启动」那次首排（500ms 防抖）

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
        if (timetableUseCase != null)
          Provider<TimetableUseCase>.value(value: timetableUseCase),
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
        // 通知设置与通知引擎必须注册：设置页的「通知」节靠这两个 Provider 渲染
        // （SyncConfigStore 当年就是漏注册让设置里那一节静默不可用的）。
        // 装配缺失时 NotifySection 自己降级成一行提示，不炸整棵设置树。
        ChangeNotifierProvider<NotifySettingsStore>.value(value: notifySettings),
        Provider<NotificationService>.value(value: notificationService),
        if (reminder != null)
          Provider<ReminderCoordinator>.value(value: reminder),
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

  // 启动就把三份快照写一遍：否则新装的用户加完卡片要先改一条任务才看得到内容。
  widgetSnapshots?.refresh();

  // 快捷方式路由：热启动走 handler，冷启动那条等首帧后主动问原生要（原生暂存着）。
  final NavRouter? nav = navRouter;
  NavIntents.setHandler((String route) => nav?.handle(route));
  if (nav != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final String? route = await NavIntents.initialRoute();
      nav.handle(route);
    });
  }
}

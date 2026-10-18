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
import 'package:qingdan/features/shell/placeholder_panes.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/sync/sync_coordinator.dart';
import 'package:qingdan/theme/app_colors.dart';

import 'sync_fakes.dart';

/// 窄屏（<720dp）形态回归测试。
///
/// 缺陷来源：单栏形态只有 `drawer:` 而没有 `AppBar`，Flutter 不会自动生成
/// 汉堡按钮，主导航（智能清单/各清单/回收站/设置）只能靠边缘滑动进入，
/// Android 真机走查实测用户在手机上完全找不到入口（见 §2.6 顶栏规范）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late TaskListUseCase listUseCase;
  late TaskUseCase taskUseCase;
  late SidebarModel sidebar;
  late TaskPaneModel paneModel;
  late ChaoxingModel chaoxing;
  late SettingsModel settings;
  late SyncStatusModel syncStatus;

  setUp(() async {
    // 真实异步（sqflite_ffi）必须在 FakeAsync 区之外完成，否则测试挂死。
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
    sidebar = SidebarModel(listUseCase: listUseCase);
    // 种一条「今天」到期的任务（listId 为 NULL 即收集箱）：
    // 窄屏点行进详情的用例需要一条真实的行，角标用例需要它已经算进 todayCount，
    // 所以必须在 load() **之前**建，否则侧栏计数是 0。
    await taskUseCase.create(title: '买牛奶', dueDate: DateTime.now());
    await sidebar.load();
    paneModel = TaskPaneModel(useCase: taskUseCase, sidebar: sidebar);
    await paneModel.load();
    // 清单页「今天」视图顶部的到期提示条读 ChaoxingModel（真机由 main.dart 注入）。
    chaoxing = ChaoxingModel(secure: InMemorySecureStore());
    settings = SettingsModel();
    // 顶栏右侧的同步状态槽读 SyncStatusModel（真机由 main.dart 注入）。
    // 本文件不测同步行为，给一个「同步未配置」的协调器就够。
    // 壳类用例要的是「已经看过首启引导」的稳态：引导框由
    // `first_run_guide_test.dart` 专门测，留在这里会盖住每一个点击。
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsModel.kGuideSeenKey: true,
    });
    // 必须 load()：`guideSeen` 只在 load 里从 prefs 读，光造对象仍是 false，
    // 于是首启引导会在每一个壳用例里弹出来盖住点击。
    await settings.load();
    syncStatus = SyncStatusModel(
      coordinator: SyncCoordinator(
        configStore: SyncConfigStore(
            prefs: await SharedPreferences.getInstance()),
        runnerFactory: FakeFactory(CountingRunner()),
        timers: FakeTimers(),
      ),
      deviceId: 'nav-test',
    );
  });

  tearDown(() async {
    await db.close();
  });

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

  // 页标题用 key 定位：任务行的到期日也渲染成「今天」，按文案找会撞车。
  final Finder paneTitle = find.byKey(const ValueKey<String>('paneTitle'));
  final Finder topBarTitle = find.byKey(const ValueKey<String>('topBarTitle'));
  String titleOf(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).data ?? '';

  testWidgets('窄屏主导航是底部 4 页签：标签常驻可见，不再有抽屉', (WidgetTester tester) async {
    await pumpAtWidth(tester, 390);

    // M5 定案第 1、5 条：窄屏取消抽屉，主导航换成底部 4 页签。
    // 原断言「顶栏有汉堡按钮 → 点开抽屉看到回收站/设置」随形态作废；
    // 汉堡按钮当年是为了救「手机上找不到主导航」而加的，现在底部栏本身就是导航，
    // 再留汉堡就是两套主导航并存。
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final String label in <String>['清单', '学习通', '课表', '设置']) {
      // 只数底部栏里的那一份：M5-S2 起清单页自带「清单 ▾」切换按钮，
      // 按全树文案找会撞成两个。
      expect(
          find.descendant(
              of: find.byType(NavigationBar), matching: find.text(label)),
          findsOneWidget,
          reason: '页签「$label」不可见');
    }
    // §2.6：页标题归 56dp 顶栏（移动 17sp），仍显示当前视图名。
    expect(topBarTitle, findsOneWidget);
    expect(titleOf(tester, topBarTitle), '今天');
  });

  test('页签与视图互相同步：selectedId 仍是唯一真相', () {
    // 这条取代原「抽屉内选完清单后抽屉自动收起」——抽屉没了，
    // 要守住的是「两个状态不打架」这个不变量。
    // 用独立的模型：共享的 `sidebar` 挂着 TaskPaneModel 监听，
    // 切页签会触发查库，而 FakeAsync 区结束后库已被 tearDown 关掉。
    final SidebarModel m = SidebarModel(listUseCase: listUseCase);
    expect(m.tab, ShellTab.tasks);

    m.selectTab(ShellTab.course);
    expect(m.selectedId, kCourseWeek);
    m.selectTab(ShellTab.chaoxing);
    expect(m.selectedId, kChaoxing);

    // 回到「清单」页签要恢复离开前的视图，不该弹回「今天」。
    m.selectTab(ShellTab.tasks);
    expect(m.selectedId, kSmartToday);

    // 设置不是任务视图：切过去不动 selectedId，切回来还是原视图。
    m.select(kSmartAll);
    m.selectTab(ShellTab.settings);
    expect(m.selectedId, kSmartAll);
    m.selectTab(ShellTab.tasks);
    expect(m.selectedId, kSmartAll);

    // 反向：侧栏/快捷键改选中项时，页签跟着投影。
    m.select(kTrash);
    expect(m.tab, ShellTab.tasks);
    m.select(kChaoxing);
    expect(m.tab, ShellTab.chaoxing);
  });

  testWidgets('窄屏不重复渲染标题；右下角「＋」开快捷添加抽屉', (WidgetTester tester) async {
    await pumpAtWidth(tester, 390);

    // 标题只在顶栏出现一次：列表区标题行不得再渲染一遍 20sp 同名标题。
    expect(paneTitle, findsNothing);
    // §2.6 移动线框的右上角箭头与内嵌详情重复 → 不该在。
    expect(find.byIcon(Icons.chevron_left), findsNothing);

    // 2026-10-18 第二轮定案：「＋」开的是**能挑日期 / 优先级 / 清单的抽屉**，
    // 顶部输入框仍是「一行文本 + 自然语言日期」的快建，两者入口不同。
    final Finder fab = find.byKey(const ValueKey<String>('add-task'));
    expect(fab, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('compose-title')), findsNothing);

    await tester.tap(fab);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('compose-title')), findsOneWidget);
    for (final String key in <String>[
      'compose-list',
      'compose-priority',
      'compose-start',
      'compose-due',
      'compose-save',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget,
          reason: '抽屉里缺 $key');
    }
    // 「添加」在未填标题时必须是死的，否则点了就是建一条空标题的任务。
    expect(tester.widget<FilledButton>(
            find.byKey(const ValueKey<String>('compose-save')))
        .onPressed,
        isNull);
  });

  testWidgets('窄屏点任务行推全屏详情页（需求规格书 :172 两级页面）',
      (WidgetTester tester) async {
    await pumpAtWidth(tester, 390);

    await tester.tap(find.text('买牛奶'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(DetailPaneHost), findsOneWidget);
  });

  testWidgets('两栏形态图标栏：点击切视图、选中态跟随、设置入口存在',
      (WidgetTester tester) async {
    await pumpAtWidth(tester, 800);

    // 此前图标栏三处不可用：onTap 空实现、selected 硬编码在「今天」、无设置入口。
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    final AppColors colors =
        AppColors.of(tester.element(find.byIcon(Icons.layers_outlined)));
    Color iconColor(IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon)).color!;
    expect(iconColor(Icons.wb_sunny_outlined), colors.accent);
    expect(iconColor(Icons.layers_outlined), isNot(colors.accent));

    await tester.tap(find.byIcon(Icons.layers_outlined));
    await tester.pump();

    expect(sidebar.selectedId, kSmartAll);
    expect(iconColor(Icons.layers_outlined), colors.accent);
    expect(iconColor(Icons.wb_sunny_outlined), isNot(colors.accent));
  });

  testWidgets('三栏形态（≥1040dp）不受影响：无抽屉按钮，标题仍在列表区',
      (WidgetTester tester) async {
    await pumpAtWidth(tester, 1280);

    expect(find.byIcon(Icons.menu), findsNothing);
    expect(topBarTitle, findsNothing);
    expect(paneTitle, findsOneWidget);
    expect(titleOf(tester, paneTitle), '今天');
  });

  testWidgets('窄屏回收站工具行不重复页标题，操作项保留', (WidgetTester tester) async {
    await pumpAtWidth(tester, 390, viewId: kTrash);

    expect(paneTitle, findsNothing);
    expect(topBarTitle, findsOneWidget);
    expect(titleOf(tester, topBarTitle), '回收站');
    expect(find.text('清空回收站'), findsOneWidget);
    // 回收站没有快速添加框，「＋」不该跟着过来（2026-10-18 定案第 2 问）。
    expect(find.byKey(const ValueKey<String>('add-task')), findsNothing);
  });

  testWidgets('底部角标：清单=今天未完成，学习通 24 小时内有到期 → 红底',
      (WidgetTester tester) async {
    List<Badge> badges(WidgetTester tester) => tester
        .widgetList<Badge>(find.descendant(
            of: find.byType(NavigationBar), matching: find.byType(Badge)))
        .toList();
    await pumpAtWidth(tester, 390);

    // 种的那条「买牛奶」今天到期 → 只有清单页签挂一个角标，数字 1。
    expect(badges(tester), hasLength(1));
    expect(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text('1')),
        findsOneWidget);

    final DateTime now = DateTime.now();
    chaoxing.fetchedAt = now;
    chaoxing.tasks = <ChaoxingTask>[
      ChaoxingTask(
          id: 'a1',
          courseId: 'c1',
          courseName: '数据结构',
          title: '第一章作业',
          kind: '作业',
          ongoing: true,
          serverStatus: '未提交',
          dueAt: now.add(const Duration(hours: 6))),
    ];
    // 直接塞字段不会通知；tick() 才是「模型动了一下」的真话（生产里由 refresh 发）。
    chaoxing.tick();
    await tester.pump();

    // 目的地顺序 == ShellTab 声明顺序：[0] 清单、[1] 学习通。
    expect(badges(tester), hasLength(2));
    expect(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text('1')),
        findsNWidgets(2));
    final AppColors shellColors =
        AppColors.of(tester.element(find.byType(NavigationBar)));
    // 两枚角标必须**不同色**：`Badge` 的默认底色就是 error 红，不显式给色的话
    // 「普通计数」和「24 小时内到期」看着一样，红就白给了。
    expect(badges(tester).first.backgroundColor, shellColors.accent);
    expect(badges(tester)[1].backgroundColor, shellColors.overdue,
        reason: '24 小时内有到期必须是红底');

    // 开关关掉：一个角标都不留（定案第 10 条「设置里可关」）。
    await settings.setShowBadges(false);
    await tester.pump();
    expect(badges(tester), isEmpty);
  });
}

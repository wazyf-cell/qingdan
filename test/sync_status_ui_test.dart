import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:provider/provider.dart";
import "package:provider/single_child_widget.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:qingdan/features/shell/sidebar/sync_slot.dart";
import "package:qingdan/features/shell/sidebar/sync_status_model.dart";
import "package:qingdan/features/settings/sync_section.dart";
import "package:qingdan/sync/secure_store.dart";
import "package:qingdan/sync/sync_backend.dart";
import "package:qingdan/sync/sync_config_store.dart";
import "package:qingdan/sync/sync_coordinator.dart";
import "package:qingdan/sync/sync_status.dart";
import "package:qingdan/theme/app_theme.dart";

import "sync_fakes.dart";

/// S5 验收：侧栏 28dp 状态槽六态文案 + 详情卡 + 手动同步入口 + 设置同步节
/// （全部离线假件，不发真实网络）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SyncConfigStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = SyncConfigStore(
      prefs: await SharedPreferences.getInstance(),
      secure: InMemorySecureStore(),
    );
  });

  Future<void> configure() => store.save(const SyncConfig(
        enabled: true,
        baseUrl: "https://dav.example.com/dav/x/",
        username: "u",
        password: "p",
      ));

  /// 用一个 runner 造协调器 + 状态模型。
  Future<(SyncCoordinator, SyncStatusModel)> pair(
    CountingRunner runner, {
    String? deviceId,
  }) async {
    final SyncCoordinator c = SyncCoordinator(
      configStore: store,
      runnerFactory: FakeFactory(runner),
      timers: FakeTimers(),
    );
    return (c, SyncStatusModel(coordinator: c, deviceId: deviceId));
  }

  Future<void> pumpWidgetWith(
      WidgetTester tester, SyncStatusModel model, Widget child) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SyncStatusModel>.value(
        value: model,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets("未配置：显示「同步未配置」", (WidgetTester tester) async {
    final (SyncCoordinator _, SyncStatusModel m) =
        await pair(CountingRunner());
    await tester.runAsync(() async {});
    await pumpWidgetWith(tester, m, const SyncSlot());
    await tester.pump();
    expect(find.text("同步未配置"), findsOneWidget);
    m.dispose();
  });

  testWidgets("空闲：显示「上次同步 HH:mm」", (WidgetTester tester) async {
    await configure();
    final CountingRunner runner = CountingRunner();
    final (SyncCoordinator c, SyncStatusModel m) = await pair(runner);
    await tester.runAsync(() => c.syncNow());
    expect(c.status.kind, SyncStatusKind.idle);
    await pumpWidgetWith(tester, m, const SyncSlot());
    await tester.pump();
    expect(find.textContaining("上次同步"), findsOneWidget);
    m.dispose();
  });

  testWidgets("失败：显示「同步失败 · 点击查看」", (WidgetTester tester) async {
    await configure();
    final CountingRunner runner = CountingRunner(onRun: () {
      throw const SocketFailure();
    });
    final (SyncCoordinator c, SyncStatusModel m) = await pair(runner);
    await tester.runAsync(() => c.syncNow());
    expect(c.status.kind, SyncStatusKind.failed);
    await pumpWidgetWith(tester, m, const SyncSlot());
    await tester.pump();
    expect(find.text("同步失败 · 点击查看"), findsOneWidget);
    m.dispose();
  });

  testWidgets("凭据失效：显示「需要重新配置」", (WidgetTester tester) async {
    await configure();
    final CountingRunner runner = CountingRunner(onRun: () {
      throw const SyncConfigException(
        baseUrl: "https://dav.example.com/dav/x/",
        statusCode: 401,
        hint: "账号或应用密码错误",
      );
    });
    final (SyncCoordinator c, SyncStatusModel m) = await pair(runner);
    await tester.runAsync(() => c.syncNow());
    expect(c.status.kind, SyncStatusKind.credentialsInvalid);
    await pumpWidgetWith(tester, m, const SyncSlot());
    await tester.pump();
    expect(find.text("需要重新配置"), findsOneWidget);
    m.dispose();
  });

  testWidgets("点击槽位打开详情卡（请求数 + 本机设备 + 两个按钮）",
      (WidgetTester tester) async {
    final (SyncCoordinator _, SyncStatusModel m) =
        await pair(CountingRunner(), deviceId: "abcd1234efgh");
    await pumpWidgetWith(tester, m, const SyncSlot());
    await tester.tap(find.byType(SyncSlot));
    await tester.pumpAndSettle();
    expect(find.text("同步详情"), findsOneWidget);
    expect(find.textContaining("本窗口请求"), findsOneWidget);
    expect(find.textContaining("abcd1234"), findsWidgets);
    expect(find.text("立即同步"), findsOneWidget);
    // 「打开设置」2026-10-19 去掉了：设置入口本来就在导航里（手机底部「设置」页签、
    // 桌面侧栏底部），状态卡里再开一个既挤又重复。
    expect(find.text("打开设置"), findsNothing);
    m.dispose();
  });

  /// 窄屏回归（用户报的：「立即同步」那个按钮超出了弹层窗口）。
  ///
  /// 卡片写死 360 宽，而 `Dialog` 还会按屏宽再夹一道 —— 411dp 屏上可用宽度不够
  /// 三个按钮并排，`Row` 装不下就是 Overflow 红条 + 按钮画到卡片外面。
  /// 这条测试钉两件事：**没有溢出异常**，以及**按钮右缘不越出卡片右缘**。
  /// （原来那批用例跑在 800×600 的默认测试面上，永远撞不到这个宽度。）
  testWidgets("窄屏 411dp：详情卡按钮不越出卡片、不溢出",
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await configure();
    final (SyncCoordinator _, SyncStatusModel m) = await pair(CountingRunner());
    await pumpWidgetWith(tester, m, const SyncSlot());
    await tester.tap(find.byType(SyncSlot));
    await tester.pumpAndSettle();

    // 量的是**里面那张固定尺寸的卡片**，不是 Dialog —— Dialog 的布局盒是整屏。
    final Rect card = tester.getRect(find
        .descendant(of: find.byType(Dialog), matching: find.byType(Container))
        .first);
    final Rect button = tester.getRect(find.text("立即同步"));
    expect(button.right, lessThanOrEqualTo(card.right + 0.5),
        reason: '按钮越出卡片右缘：${button.right} > ${card.right}');
    expect(button.bottom, lessThanOrEqualTo(card.bottom + 0.5),
        reason: '按钮越出卡片下缘');
    expect(tester.takeException(), isNull, reason: '出现 RenderFlex 溢出');
    m.dispose();
  });

  testWidgets("详情卡「立即同步」触发一轮", (WidgetTester tester) async {
    await configure();
    final CountingRunner runner = CountingRunner();
    final (SyncCoordinator _, SyncStatusModel m) = await pair(runner);
    await pumpWidgetWith(tester, m, const SyncSlot());
    await tester.tap(find.byType(SyncSlot));
    await tester.pumpAndSettle();
    await tester.tap(find.text("立即同步"));
    await tester.pumpAndSettle();
    expect(runner.runs, 1);
    m.dispose();
  });

  testWidgets("设置同步节：字段齐全且回显已保存地址",
      (WidgetTester tester) async {
    await configure();
    await tester.pumpWidget(
      Provider<SyncConfigStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SyncSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("启用同步"), findsOneWidget);
    expect(find.text("服务器地址"), findsOneWidget);
    expect(find.text("账号"), findsOneWidget);
    expect(find.text("应用密码"), findsOneWidget);
    expect(find.text("测试连接"), findsOneWidget);
    expect(find.text("解除配置"), findsOneWidget);
    expect(find.text("https://dav.example.com/dav/x/"), findsOneWidget);
  });

  // ── 装配完整性回归 ────────────────────────────────────────────────
  //
  // 上面那条用例是**手工注入** Provider<SyncConfigStore> 的，所以无论
  // main.dart 有没有注册它都会通过 —— 它测的是 SyncSection 自身，不是
  // 「生产装配是否完整」。真实缺口正是这样漏掉的：SyncSection 在
  // initState 里就 context.read<SyncConfigStore>()，而 main.dart 一度
  // 就地 new 了 store 却忘了放进 provider 列表，导致点开「设置 → 同步」
  // 直接抛 ProviderNotFoundException。
  //
  // 下面两条是**成对**的，缺一不可。
  //
  // ★ 为什么第一条必须断言「不出现红字」而不只是「渲染出字段」：
  //   一开始我只断言 find.text("启用同步") 存在，然后做破坏性实验
  //   （删掉 Provider<SyncConfigStore> 那行）—— **它照样通过**。
  //   因为 sync_section.dart:57 的 context.read 外面包着 try/catch
  //   （:66-72），provider 缺失时不会崩，界面照样渲染出全部字段，
  //   只是多一行红字。所以「字段在」对装配是否完整**零信息量**；
  //   唯一的判别信号是那行红字的有无。
  testWidgets("装配完整性：provider 树注册了 SyncConfigStore 时同步节无报错",
      (WidgetTester tester) async {
    final SyncCoordinator c = SyncCoordinator(
      configStore: store,
      runnerFactory: FakeFactory(CountingRunner()),
    );

    // 按 main.dart 的形状搭树：协调器 + 配置存储都在。
    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          Provider<SyncCoordinator>.value(value: c),
          Provider<SyncConfigStore>.value(value: store),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SyncSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 字段在（基本渲染）。
    expect(find.text("启用同步"), findsOneWidget);
    // ★ 真正的判别断言：配置读到了，所以**不该**出现读取失败红字。
    expect(find.textContaining("读取配置失败"), findsNothing);
    c.dispose();
  });

  // ★ 反证（成对，不可删）：不注册 Store 时，_load() 里的
  //   context.read<SyncConfigStore>() 会抛 ProviderNotFoundException，
  //   但它在 try 里 —— 于是**不会崩**，而是被转成红字错误行
  //   「读取配置失败：…」，界面照常渲染但同步节完全不可用。
  //   这条把这个真实行为钉住：既不美化（说成崩溃）也不淡化
  //   （因为是靠 try 兜住的，一旦有人删掉那个 try 就变成真崩溃）。
  //   它同时是上面那条的**有效性证明**：证明了「读取配置失败」这个
  //   判别信号真的会出现。
  testWidgets("反证：未注册 SyncConfigStore 时，同步节渲染出配置读取失败而非崩溃",
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SyncSection()),
      ),
    );
    await tester.pumpAndSettle();

    // 没有未捕获异常（被 _load 的 try 兜住了）。
    expect(tester.takeException(), isNull);
    // 但界面明确报错：出现「读取配置失败」前缀的红字。
    expect(find.textContaining("读取配置失败"), findsOneWidget);
    // 并且确实是 provider 缺失导致，而不是别的原因。
    expect(find.textContaining("Provider"), findsOneWidget);
  });
}

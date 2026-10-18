import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:qingdan/sync/rate_limiter_backend.dart";
import "package:qingdan/sync/secure_store.dart";
import "package:qingdan/sync/sync_backend.dart";
import "package:qingdan/sync/sync_config_store.dart";
import "package:qingdan/sync/sync_coordinator.dart";
import "package:qingdan/sync/sync_status.dart";

import "sync_fakes.dart";

/// S4 验收：防抖合并 / 单飞补一轮 / 退避序列 / 401 不重试 / 手动与自动同闸门。
/// 全部走假时钟 + 假 runner，不发真实网络。
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

  SyncCoordinator build(FakeTimers timers, CountingRunner runner) =>
      SyncCoordinator(
        configStore: store,
        runnerFactory: FakeFactory(runner),
        timers: timers,
      );

  test("防抖合并：2s 内多次 notifyLocalChange 只触发一轮", () async {
    final FakeTimers timers = FakeTimers();
    final CountingRunner runner = CountingRunner();
    await configure();
    final SyncCoordinator c = build(timers, runner);

    c.notifyLocalChange();
    await timers.advance(const Duration(seconds: 1));
    c.notifyLocalChange();
    await timers.advance(const Duration(seconds: 1));
    c.notifyLocalChange();
    await timers.advance(const Duration(seconds: 3));

    expect(runner.runs, 1);
  });

  test("单飞：运行中新请求只置 pending，完成后补跑且只补一轮", () async {
    final FakeTimers timers = FakeTimers();
    final DeferredRunner runner = DeferredRunner();
    await configure();
    final SyncCoordinator c = SyncCoordinator(
      configStore: store,
      runnerFactory: FakeFactory(runner),
      timers: timers,
    );

    c.notifyLocalChange();
    await timers.advance(kSyncDebounce);
    expect(runner.started, 1);

    c.notifyLocalChange();
    await timers.advance(kSyncDebounce);
    expect(runner.started, 1);

    runner.complete(0);
    await flushMicrotasks();
    expect(runner.started, 2);

    runner.complete(1);
    await flushMicrotasks();
    expect(runner.started, 2);
  });

  test("退避序列：1 → 2 → 4 → 8 → 15 分钟，封顶 15", () async {
    final FakeTimers timers = FakeTimers();
    final List<DateTime> runAt = <DateTime>[];
    final CountingRunner runner = CountingRunner(onRun: () {
      runAt.add(timers.now());
      throw const SocketFailure();
    });
    await configure();
    final SyncCoordinator c = build(timers, runner);

    final DateTime t0 = timers.now();
    await c.syncNow();
    expect(runAt.length, 1);

    for (final Duration step in <Duration>[
      const Duration(minutes: 1),
      const Duration(minutes: 2),
      const Duration(minutes: 4),
      const Duration(minutes: 8),
      const Duration(minutes: 15),
      const Duration(minutes: 15),
    ]) {
      await timers.advance(step);
    }

    expect(runAt.length, 7);
    expect(runAt[1].difference(t0).inMinutes, 1);
    expect(runAt[2].difference(t0).inMinutes, 3);
    expect(runAt[3].difference(t0).inMinutes, 7);
    expect(runAt[4].difference(t0).inMinutes, 15);
    expect(runAt[5].difference(t0).inMinutes, 30);
    expect(runAt[6].difference(t0).inMinutes, 45);
    expect(c.status.kind, SyncStatusKind.failed);
  });

  test("成功后清零退避：下一次失败重新从 1 分钟开始", () async {
    final FakeTimers timers = FakeTimers();
    final List<DateTime> runAt = <DateTime>[];
    bool fail = true;
    final CountingRunner runner = CountingRunner(onRun: () {
      runAt.add(timers.now());
      if (fail) throw const SocketFailure();
    });
    await configure();
    final SyncCoordinator c = build(timers, runner);

    await c.syncNow();
    await timers.advance(const Duration(minutes: 1));
    expect(runAt.length, 2);

    fail = false;
    await timers.advance(const Duration(minutes: 2));
    expect(c.status.kind, SyncStatusKind.idle);

    fail = true;
    await c.syncNow();
    final int afterFail = runAt.length;
    await timers.advance(const Duration(minutes: 1));
    expect(runAt.length, afterFail + 1);
  });

  test("401 凭据失效：不自动重试，转 credentialsInvalid", () async {
    final FakeTimers timers = FakeTimers();
    final CountingRunner runner = CountingRunner(onRun: () {
      throw const SyncConfigException(
        baseUrl: "https://dav.example.com/dav/x/",
        statusCode: 401,
        hint: "账号或应用密码错误",
      );
    });
    await configure();
    final SyncCoordinator c = build(timers, runner);

    await c.syncNow();
    expect(c.status.kind, SyncStatusKind.credentialsInvalid);
    await timers.advance(const Duration(hours: 2));
    expect(runner.runs, 1);
    expect(c.status.kind, SyncStatusKind.credentialsInvalid);
  });

  test("限流：转 rateLimited，retryAt 为本刻 +30 分钟", () async {
    final FakeTimers timers = FakeTimers();
    final CountingRunner runner = CountingRunner(onRun: () {
      throw RateLimitExceededException(
        used: 600,
        maxRequests: 600,
        requiredCost: 1,
        maxWait: const Duration(minutes: 5),
      );
    });
    await configure();
    final SyncCoordinator c = build(timers, runner);

    await c.syncNow();
    expect(c.status.kind, SyncStatusKind.rateLimited);
    expect(
      c.status.retryAt!.difference(timers.now()).inMinutes,
      kSyncRateLimitRetry.inMinutes,
    );
    await timers.advance(const Duration(minutes: 30));
    expect(runner.runs, 2);
  });

  test("手动 syncNow 跳过 60s 最小间隔；自动触发受节流", () async {
    final FakeTimers timers = FakeTimers();
    final CountingRunner runner = CountingRunner();
    await configure();
    final SyncCoordinator c = build(timers, runner);

    await c.syncNow();
    expect(runner.runs, 1);

    c.notifyLocalChange();
    await timers.advance(kSyncDebounce);
    expect(runner.runs, 1);

    await c.syncNow();
    expect(runner.runs, 2);
  });

  test("未配置：syncNow 转 unconfigured 且不跑 runner", () async {
    final FakeTimers timers = FakeTimers();
    final CountingRunner runner = CountingRunner();
    final SyncCoordinator c = build(timers, runner);
    await c.syncNow();
    expect(runner.runs, 0);
    expect(c.status.kind, SyncStatusKind.unconfigured);
  });

  test("401 会撤销已排队的退避重试（先网络失败、后凭据失效）", () async {
    final FakeTimers timers = FakeTimers();
    bool creds = false;
    final CountingRunner runner = CountingRunner(onRun: () {
      if (creds) {
        throw const SyncConfigException(
          baseUrl: "https://dav.example.com/dav/x/",
          statusCode: 403,
          hint: "凭据无效",
        );
      }
      throw const SocketFailure();
    });
    await configure();
    final SyncCoordinator c = build(timers, runner);

    await c.syncNow(); // 网络失败 → 已排 1 分钟退避
    expect(runner.runs, 1);
    creds = true;
    await c.syncNow(); // 手动再跑 → 403
    expect(c.status.kind, SyncStatusKind.credentialsInvalid);
    final int after403 = runner.runs;

    await timers.advance(const Duration(hours: 1)); // 旧退避 timer 不该触发
    expect(runner.runs, after403);
  });

  test("start()：启动首同步延迟 3s，兜底轮询 30 分钟一次", () async {
    final FakeTimers timers = FakeTimers();
    final CountingRunner runner = CountingRunner();
    await configure();
    final SyncCoordinator c = build(timers, runner);
    final List<SyncStatus> seen = <SyncStatus>[];
    c.statusStream.listen(seen.add);

    c.start();
    await timers.advance(const Duration(seconds: 2));
    expect(runner.runs, 0);
    await timers.advance(const Duration(seconds: 1));
    expect(runner.runs, 1);
    await timers.advance(const Duration(minutes: 30));
    expect(runner.runs, 2);
    expect(seen.any((s) => s.kind == SyncStatusKind.running), isTrue);
  });

  test("statusStream 广播：running → idle 且带报告", () async {
    final FakeTimers timers = FakeTimers();
    final CountingRunner runner = CountingRunner();
    await configure();
    final SyncCoordinator c = build(timers, runner);
    final List<SyncStatusKind> kinds = <SyncStatusKind>[];
    c.statusStream.listen((s) => kinds.add(s.kind));

    await c.syncNow();
    await flushMicrotasks();
    expect(kinds, <SyncStatusKind>[
      SyncStatusKind.running,
      SyncStatusKind.idle,
    ]);
    expect(c.status.lastReport, isNotNull);
    expect(c.status.lastSuccessAt, isNotNull);
  });
}

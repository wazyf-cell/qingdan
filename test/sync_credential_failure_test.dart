/// 凭据库读不回密码时的状态分流（2026-10-11 Android 真机实测的伪装缺陷）。
///
/// 单独立文件的原因：这条测的是「已配置但密码读不回」与「从没配过」的**区分**，
/// 与 `sync_coordinator_test.dart` 测的触发时序（防抖/退避/单飞）不是同一职责，
/// 且那个文件已在 300 行红线边上。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/sync/sync_coordinator.dart';
import 'package:qingdan/sync/sync_status.dart';

import 'sync_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('凭据库读不回密码：转「需要重新配置」而不是「未配置」，且不发请求', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final InMemorySecureStore secure = InMemorySecureStore();
    final SyncConfigStore store = SyncConfigStore(
      prefs: await SharedPreferences.getInstance(),
      secure: secure,
    );
    await store.save(const SyncConfig(
      enabled: true,
      baseUrl: 'https://dav.example.com/dav/x/',
      username: 'u',
      password: 'p',
    ));
    await secure.delete(SyncConfigStore.kPasswordKey); // 模拟新进程读不回

    final FakeTimers timers = FakeTimers();
    final CountingRunner runner = CountingRunner();
    final SyncCoordinator c = SyncCoordinator(
      configStore: store,
      runnerFactory: FakeFactory(runner),
      timers: timers,
    );
    await c.syncNow();

    expect(runner.runs, 0, reason: '拿不到密码就不该发网络请求');
    expect(c.status.kind, SyncStatusKind.credentialsInvalid,
        reason: '混进 unconfigured 会让人去翻配置表，而实际要做的是重输密码');
    expect(c.status.lastError.toString(), contains('应用密码'));
  });
}

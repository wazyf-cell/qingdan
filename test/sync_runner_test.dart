import "package:flutter_test/flutter_test.dart";

import "package:qingdan/sync/sync_config_store.dart";
import "package:qingdan/sync/sync_runner.dart";

import "dao_test_helper.dart";

/// WebDavSyncRunnerFactory：按配置代次缓存（勘误4，防 HttpClient 泄漏）。
void main() {
  setUpAll(ensureSqfliteFfi);

  test("同配置复用同一 runner；配置变化才重建", () async {
    final DaoTestDb env = await DaoTestDb.open();
    final WebDavSyncRunnerFactory factory =
        WebDavSyncRunnerFactory(db: env.db);

    const SyncConfig a = SyncConfig(
      enabled: true,
      baseUrl: "https://dav.example.com/dav/x/",
      username: "u",
      password: "p",
    );
    final SyncRunner first = factory.create(a);
    final SyncRunner again = factory.create(a);
    expect(identical(first, again), isTrue);

    final SyncRunner changed =
        factory.create(a.copyWith(baseUrl: "https://dav.example.com/dav/y/"));
    expect(identical(first, changed), isFalse);
    expect(identical(factory.create(a.copyWith(
      baseUrl: "https://dav.example.com/dav/y/")), changed), isTrue);

    expect(factory.requestsUsedInWindow, 0);
    await factory.dispose();
    await env.close();
  });
}

import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:qingdan/sync/secure_store.dart";
import "package:qingdan/sync/sync_config_store.dart";

/// S2 验收：保存→读取往返、clear() 清空、密码走 secure storage 而非 prefs。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late InMemorySecureStore secure;
  late SyncConfigStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    secure = InMemorySecureStore();
    store = SyncConfigStore(prefs: prefs, secure: secure);
  });

  test("默认配置：未启用、空凭据、后端为 webdav", () async {
    final SyncConfig config = await store.load();
    expect(config.enabled, isFalse);
    expect(config.backendType, kBackendWebDav);
    expect(config.baseUrl, isEmpty);
    expect(config.username, isEmpty);
    expect(config.password, isEmpty);
    expect(config.isConfigured, isFalse);
  });

  test("保存→读取往返：五项都回来", () async {
    const SyncConfig saved = SyncConfig(
      enabled: true,
      baseUrl: "https://dav.jianguoyun.com/dav/qingdan/",
      username: "me@example.com",
      password: "app-pass-123",
    );
    await store.save(saved);

    final SyncConfig loaded = await store.load();
    expect(loaded.enabled, isTrue);
    expect(loaded.backendType, kBackendWebDav);
    expect(loaded.baseUrl, saved.baseUrl);
    expect(loaded.username, saved.username);
    expect(loaded.password, saved.password);
    expect(loaded.isConfigured, isTrue);
  });

  test("凭据库读不回密码：credentialMissing 为真，且不与「从没配过」混淆", () async {
    // 真机形状（2026-10-11 Android）：prefs 三项齐全，新进程里 flutter_secure_storage
    // 返回 null（不是抛错）。吞成空串后界面只能说「同步未配置」，指错方向。
    await store.save(const SyncConfig(
      enabled: true,
      baseUrl: "https://dav.jianguoyun.com/dav/qingdan/",
      username: "me@example.com",
      password: "app-pass-123",
    ));
    await secure.delete(SyncConfigStore.kPasswordKey);

    final SyncConfig loaded = await store.load();
    expect(loaded.isConfigured, isFalse);
    expect(loaded.credentialMissing, isTrue,
        reason: "地址账号都在、只差密码 → 必须报「凭据读取失败」而不是「未配置」");
  });

  test("真的从没配过：credentialMissing 为假（别把空表也报成凭据故障）", () async {
    final SyncConfig loaded = await store.load();
    expect(loaded.credentialMissing, isFalse);
  });

  test("同步开关关着时密码读不回也不催重配：credentialMissing 为假", () async {
    await store.save(const SyncConfig(
      enabled: false,
      baseUrl: "https://dav.jianguoyun.com/dav/qingdan/",
      username: "me@example.com",
      password: "app-pass-123",
    ));
    await secure.delete(SyncConfigStore.kPasswordKey);
    expect((await store.load()).credentialMissing, isFalse,
        reason: "用户已停用同步，此时提示重输密码是噪音");
  });

  test("密码只进 secure storage：prefs 里搜不到密码明文", () async {
    await store.save(const SyncConfig(
      enabled: true,
      baseUrl: "https://dav.example.com/dav/x/",
      username: "u",
      password: "super-secret",
    ));

    // secure storage 里有；prefs 里没有（密码键根本不存在）。
    expect(secure.entries[SyncConfigStore.kPasswordKey], "super-secret");
    expect(prefs.containsKey(SyncConfigStore.kPasswordKey), isFalse);
    // 整个 prefs 快照里不含密码明文（防止被顺手写进别的键）。
    final String dump = prefs.getKeys().map((k) => "${prefs.get(k)}").join("|");
    expect(dump.contains("super-secret"), isFalse);
  });

  test("密码为空时删除凭据库条目（Windows 凭据库不支持空值）", () async {
    await store.save(const SyncConfig(
      enabled: true,
      baseUrl: "https://dav.example.com/dav/x/",
      username: "u",
      password: "secret",
    ));
    expect(secure.entries.containsKey(SyncConfigStore.kPasswordKey), isTrue);

    await store.save(const SyncConfig(
      enabled: true,
      baseUrl: "https://dav.example.com/dav/x/",
      username: "u",
    ));
    expect(secure.entries.containsKey(SyncConfigStore.kPasswordKey), isFalse);
    expect((await store.load()).password, isEmpty);
  });

  test("clear()：清凭据 + 停用 + 清空地址账号", () async {
    await store.save(const SyncConfig(
      enabled: true,
      baseUrl: "https://dav.example.com/dav/x/",
      username: "u",
      password: "secret",
    ));
    await store.clear();

    final SyncConfig cleared = await store.load();
    expect(cleared.enabled, isFalse);
    expect(cleared.baseUrl, isEmpty);
    expect(cleared.username, isEmpty);
    expect(cleared.password, isEmpty);
    expect(secure.entries, isEmpty);
    expect(cleared.isConfigured, isFalse);
  });

  test("isConfigured 对半配置（缺密码 / 关开关）为 false", () {
    expect(
      const SyncConfig(
        enabled: true,
        baseUrl: "https://dav.example.com/dav/x/",
        username: "u",
      ).isConfigured,
      isFalse,
    );
    expect(
      const SyncConfig(
        enabled: false,
        baseUrl: "https://dav.example.com/dav/x/",
        username: "u",
        password: "p",
      ).isConfigured,
      isFalse,
    );
  });
}

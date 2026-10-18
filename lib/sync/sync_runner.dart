// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 一轮同步的执行入口与其生产装配链（M3 §4 + 勘误 1/3/4）。
///
/// 抽 [SyncRunner] 接口的原因：协调器（触发/防抖/退避/状态机）要能在
/// 纯 Dart 单测里验证，不能真的发 HTTP。生产实现是 WebDAV 装配链，测试
/// 注入假 runner。协调器因此完全不 import webdav_* 与 sqflite 之外的东西。
library;

import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'rate_limiter_backend.dart';
import 'sync_backend.dart';
import 'sync_config_store.dart';
import 'sync_engine.dart';
import 'sync_report.dart';
import 'webdav_backend.dart';
import 'webdav_transport.dart';

/// 一轮同步的执行入口。
abstract class SyncRunner {
  /// 执行一轮同步并返回报告。
  Future<SyncReport> run();

  /// 本窗口已用请求数（详情卡「23 / 600」）。
  int get requestsUsedInWindow;

  /// 释放底层连接池（配置变更/退出时）。
  Future<void> dispose();
}

/// 按配置创建（并缓存）[SyncRunner]。
abstract class SyncRunnerFactory {
  /// 取当前配置对应的 runner；同配置多次调用必须返回同一实例。
  SyncRunner create(SyncConfig config);

  /// 本窗口已用请求数（详情卡「23 / 600」）；未装配时 0。
  int get requestsUsedInWindow => 0;

  Future<void> dispose();
}

/// 生产装配：WebDAV 计数传输层 + 限流装饰器，按配置代次缓存。
class WebDavSyncRunnerFactory implements SyncRunnerFactory {
  WebDavSyncRunnerFactory({required Database db}) : _db = db;

  final Database _db;
  _WebDavRunner? _runner;
  String? _signature;

  @override
  SyncRunner create(SyncConfig config) {
    final String signature =
        '${config.baseUrl}\u0000${config.username}\u0000${config.password}';
    final _WebDavRunner? cached = _runner;
    if (cached != null && _signature == signature) {
      return cached;
    }
    // 勘误4：传输链按配置代次缓存，只有配置变了才重建；重建前必须关掉旧
    // 的 HttpClient，否则每次改配置都泄漏一个连接池。
    cached?.dispose();
    final _WebDavRunner fresh = _WebDavRunner(_db, config);
    _runner = fresh;
    _signature = signature;
    return fresh;
  }

  @override
  Future<void> dispose() async {
    await _runner?.dispose();
    _runner = null;
    _signature = null;
  }

  @override
  int get requestsUsedInWindow => _runner?.requestsUsedInWindow ?? 0;
}

/// 一条 WebDAV 装配链 + 每轮新建的引擎。
class _WebDavRunner implements SyncRunner {
  _WebDavRunner(this._db, SyncConfig config) {
    final RequestBudget budget = RequestBudget();
    _budget = budget;
    _http = HttpClientWebDavTransport();
    _backend = RateLimiterBackend(
      WebDavBackend(
        baseUrl: Uri.parse(config.baseUrl),
        username: config.username,
        password: config.password,
        transport: CountingWebDavTransport(_http, budget),
      ),
      budget,
      // 勘误1（会静默出错）：装饰层与计数传输层共用同一个 budget，若保持
      // estimateCosts 默认 true，一个 put（3 个真实请求）会被记 3+3=6 次，
      // 有效预算静默减半、同步莫名频繁触发限流等待。改用精确记账：只有
      // CountingWebDavTransport 按真实请求数记，装饰层只做闸门与最小间隔。
      estimateCosts: false,
    );
  }

  final Database _db;
  late final RequestBudget _budget;
  late final HttpClientWebDavTransport _http;
  late final SyncBackend _backend;

  @override
  Future<SyncReport> run() {
    // 勘误3：每轮新建引擎。SyncReport 在构造期被绑进 CountingSyncBackend
    // 且不跨 sync() 复位，复用实例会让第二轮报告累加第一轮。
    return SyncEngine(backend: _backend, db: _db).sync();
  }

  @override
  int get requestsUsedInWindow => _budget.usedInWindow;

  @override
  Future<void> dispose() async => _http.close();
}

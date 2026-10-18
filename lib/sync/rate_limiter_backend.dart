/// 限流装饰器：包装任意 [SyncBackend]，SyncEngine 零改动透明使用。
///
/// 本文件是装饰器（[CountingWebDavTransport] + [RateLimiterBackend]）。
/// 请求预算账本 [RequestBudget] 与异常 [RateLimitExceededException] 在
/// `request_budget.dart`；「两道闸门」（窗口 + 最小间隔）的设计理由与
/// 实测依据的完整文档注释也在那里，本文件不再重复。
library;

import 'request_budget.dart';
import 'sync_backend.dart';
import 'webdav_transport.dart';

export 'request_budget.dart';

/// 精确计数传输层：包一层 [WebDavTransport]，每个真实 HTTP 请求在发出前
/// 记 1。发出前记而非成功后记——412/404 的重试请求同样占服务端配额。
///
/// 记账走 [RequestBudget.release]（而非 recordN）以**同时推进最小间隔的
/// 时钟**：一次 `put` 内部的 PROPFIND/PUT/PROPFIND 三个请求都在这里排队，
/// 它们之间也必须满足 [RequestBudget.minInterval]——这正是装饰层的
/// [_gate] 拦不到的地方（装饰层在一次 backend 调用外，调用内的多个 HTTP
/// 请求对它不可见）。
///
/// 注意 [RequestBudget.acquire] 的重试循环：`send` 里写的是
/// `await acquire(...)` 再 `release(...)`，等待发生在记账之前，窗口账本
/// 记录的是**真实发出时刻**而非「决定要发」的时刻，不会因等待而失真。
class CountingWebDavTransport implements WebDavTransport {
  CountingWebDavTransport(this._inner, this._budget);

  final WebDavTransport _inner;
  final RequestBudget _budget;

  @override
  Future<WebDavHttpResponse> send(WebDavHttpRequest request) async {
    await _budget.acquire(1, _budget.window);
    _budget.release(1);
    return _inner.send(request);
  }
}

/// 限流装饰器：包装任意 [SyncBackend]，SyncEngine 零改动透明使用。
class RateLimiterBackend implements SyncBackend {
  RateLimiterBackend(
    SyncBackend inner,
    RequestBudget budget, {
    this.estimateCosts = true,
    this.maxWait = const Duration(minutes: 5),
    Map<String, int>? methodCosts,
  })  : _inner = inner,
        _budget = budget,
        _methodCosts = methodCosts ??
            // 估算表按 WebDAV 后端的最坏情况给：put 需 PROPFIND 取新 etag，
            // 冲突时还会再多请求，保守记 3。其他后端可用 methodCosts 覆盖。
            const <String, int>{
              'list': 1,
              'get': 1,
              'put': 3,
              'delete': 1,
            };

  final SyncBackend _inner;
  final RequestBudget _budget;

  /// true（默认）：按方法成本估算表记账；false：只做闸门，记账交给
  /// 同一 [RequestBudget] 上的计数传输层按真实 HTTP 请求数计。
  final bool estimateCosts;
  final Map<String, int> _methodCosts;

  /// 超预算时的等待上限；超过则抛 [RateLimitExceededException]。
  ///
  /// 默认 5 分钟：远小于 30 分钟兜底间隔，宁可本轮失败下轮重试，
  /// 也不长时间占住后台任务。
  final Duration maxWait;

  /// 本窗口已用请求数（转发 budget 查询，供 UI/状态展示）。
  int get requestsUsedInWindow => _budget.usedInWindow;

  /// 闸门：放行前确保窗口里有足够名额**且**距上次请求已过最小间隔。
  ///
  /// - 估算模式：按成本表记账（等待后由本层记，传输层不再记）。
  /// - 精确模式：只按「下个调用至少发 1 个请求」做闸门，真实请求数由
  ///   计数传输层在执行中记账；因此闸门可能出现 ≤ 单次调用请求数的
  ///   小幅超额（600 配额下可忽略），如实注明。
  Future<void> _gate(String method) async {
    final cost = estimateCosts ? (_methodCosts[method] ?? 1) : 1;
    await _budget.acquire(cost, maxWait);
    if (estimateCosts) {
      _budget.release(cost);
    }
  }

  @override
  Future<List<RemoteObject>> list(String namespace) async {
    await _gate('list');
    return _inner.list(namespace);
  }

  @override
  Future<({List<int> bytes, String? etag})> get(String path) async {
    await _gate('get');
    return _inner.get(path);
  }

  @override
  Future<String?> put(String path, List<int> bytes, {String? ifMatchEtag}) {
    return _gate('put').then(
      (_) => _inner.put(path, bytes, ifMatchEtag: ifMatchEtag),
    );
  }

  @override
  Future<void> delete(String path, {String? ifMatchEtag}) {
    return _gate('delete')
        .then((_) => _inner.delete(path, ifMatchEtag: ifMatchEtag));
  }

  @override
  Future<void> ensureReady() => _inner.ensureReady();

  @override
  Future<BackendCapabilities> capabilities() =>
      // 不做闸门：能力声明是本地静态信息，不发 HTTP 请求（两个既有实现
      // 均如此），计入配额只会白白挤占真实请求的名额。
      _inner.capabilities();
}

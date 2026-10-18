/// 限流装饰器：坚果云免费版 **600 请求 / 30 分钟**（滑动窗口）的守门员。
///
/// ★ 计数器挂在哪一层（本文件最关键的设计决策）：**两层配合**。
///
/// - **精确计数挂在传输层**（[CountingWebDavTransport]，每个真实 HTTP 请求
///   记 1）：一次 WebDAV `put` 实际发不止 1 个 HTTP 请求（PUT + PROPFIND 取
///   新 etag，冲突时再多一次 PROPFIND，目录缺失时还有 MKCOL），
///   「backend 方法调用数」与「真实 HTTP 请求数」不是 1:1。坚果云按 HTTP
///   请求计数（PROPFIND/PUT/GET 全算），只按方法调用计数会低估 2–3 倍。
/// - **闸门与状态暴露挂在 SyncBackend 装饰层**（[RateLimiterBackend]）：
///   SyncEngine 只认 SyncBackend 接口，限流器以装饰器形态介入，引擎零改动。
/// - 两种模式（**同一 budget 只能选一种记账来源，否则重复计数**）：
///   - `estimateCosts: true`（默认）：装饰层按方法成本估算表记账
///     （put=3/list=1/get=1/delete=1），适配任何没有精确计数的后端；
///   - `estimateCosts: false`（推荐配 WebDAV）：装饰层只做闸门，记账交给
///     挂同一 [RequestBudget] 的 [CountingWebDavTransport]，按真实请求数计。
///
/// ★ 两道闸门（缺一不可，2026-09-30 实测后补上第二道）：
///
/// 1. **窗口总量**（[RequestBudget.maxRequests] / [RequestBudget.window]）：
///    600 请求 / 30 分钟滑动窗口，防的是「半天内累计超量」。
/// 2. **最小请求间隔**（[RequestBudget.minInterval]，默认 2 秒）：防的是
///    **瞬时速率**。这是 2026-09-30 真机实测补的——测量脚本以 700ms/请求
///    （约 85 请求/分钟）连续 PUT，在约 300 个请求处即触发**账号级**
///    `503 BlockedTemporarily`（连只读 PROPFIND 也 503，持续 >10 分钟）。
///    官方「600 请求/30 分钟」严重低估了真实限制，**滑动窗口计数会掩盖
///    瞬时速率**：连续写 50 个实体（约 150 请求）时窗口账本显示
///    「150/600，远未超预算」，于是背靠背发出全部请求——正好踩线被封。
///    **只做窗口不设间隔，等于没防住实测里真正触发的那个限制。**
///
/// 两道闸门都实现在 [RequestBudget.acquire] 里，因此**估算模式与精确模式
/// 都自动获得间隔控制**（两条路径都经过 acquire），不会出现一种模式防住了、
/// 另一种没防。
///
/// 超预算行为：**等待，但有上限**（默认 5 分钟，见 [RateLimiterBackend]）。
/// 同步是事件驱动 + 低频兜底的后台任务，用户没在盯着，短暂等待无感知；
/// 但无限等待会卡死调用方，超过上限抛 [RateLimitExceededException]，让
/// 同步引擎按本次失败处理、留到下一轮兜底再试——这与「低频兜底」策略
/// 天然契合，不会丢数据（op-log 仍在）。
library;

/// 请求预算账本：默认 600 请求 / 30 分钟，且任意两次请求间隔 ≥ [minInterval]。
///
/// 时间源与等待函数都可注入：测试用假时钟 + 假 delay 即可离线验证窗口
/// 滚动与最小间隔，不必真等 30 分钟或 2 秒。
class RequestBudget {
  RequestBudget({
    this.maxRequests = 600,
    this.window = const Duration(minutes: 30),
    this.minInterval = const Duration(seconds: 2),
    DateTime Function()? now,
    Future<void> Function(Duration duration)? delay,
  })  : _now = now ?? DateTime.now,
        _delay = delay ?? ((d) => Future<void>.delayed(d));

  /// 窗口内允许的最大请求数（坚果云免费版：600）。
  final int maxRequests;

  /// 滑动窗口长度（坚果云：30 分钟）。
  final Duration window;

  /// 任意两次请求之间的最小间隔（默认 2 秒 ≈ 30 请求/分钟）。
  ///
  /// 取值依据：实测 85 请求/分钟（700ms）会触发账号级 503，官方 30 分钟
  /// 总量口径（20 请求/分钟）又过于宽松；2 秒/请求是文档定案的安全值。
  /// 设 [Duration.zero] 可关闭（仅供对照实验，生产不得关闭）。
  final Duration minInterval;

  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  /// 窗口内每次请求的时刻。
  final List<DateTime> _marks = <DateTime>[];

  /// 上一次放行请求的时刻；null 表示本实例尚未放过请求。
  DateTime? _lastReleased;

  /// 当前时刻（可注入）。
  DateTime get currentTime => _now();

  /// 本窗口已用请求数（为将来 UI 显示同步状态留的查询口）。
  int get usedInWindow {
    _prune();
    return _marks.length;
  }

  /// 是否已达预算上限。
  bool get isOverBudget => usedInWindow >= maxRequests;

  /// 记录 1 个请求（精确模式由计数传输层在请求发出前调用；发出前记：
  /// 失败的请求同样占服务端配额）。
  void record() => _marks.add(_now());

  /// 在指定时刻 [at] 记 1 个请求（测试直接构造历史窗口用）。
  void recordAt(DateTime at) => _marks.add(at);

  /// 一次记 [n] 个（估算模式按方法成本记账）。
  void recordN(int n) {
    final t = _now();
    for (var i = 0; i < n; i++) {
      _marks.add(t);
    }
  }

  /// 剔除已滑出窗口的记录（时刻差 ≥ window 即过期）。
  void _prune() {
    final t = _now();
    _marks.retainWhere((mark) => t.difference(mark) < window);
  }

  /// 若现在要消耗 [cost] 个名额，需等待的时长；0 表示可立即放行。
  Duration waitDuration(int cost) {
    _prune();
    final free = maxRequests - _marks.length;
    if (cost <= free) {
      return Duration.zero;
    }
    // 需要等正好这么多个最旧记录滑出窗口后名额才够。
    final needExpire = _marks.length - free;
    final expireAt = _marks[needExpire - 1].add(window);
    final wait = expireAt.difference(_now());
    return wait > Duration.zero ? wait : Duration.zero;
  }

  /// 为满足 [minInterval]，距上次放行还需等待多久；0 表示可以立即发。
  Duration intervalWait() {
    final DateTime? last = _lastReleased;
    if (last == null) {
      return Duration.zero;
    }
    final DateTime earliest = last.add(minInterval);
    final Duration wait = earliest.difference(_now());
    return wait > Duration.zero ? wait : Duration.zero;
  }

  /// 两道闸门都满足时需要等待的时长：先等最小间隔，再等窗口名额。
  ///
  /// 取两者中更靠后的那个时刻——它们约束的是同一个「可以发了吗」的问题，
  /// 串联等待等价于取较大值，但必须**累加**而非取 max，因为等完间隔后
  /// 时刻已推进，窗口名额可能因此腾出（或仍不够）。
  Duration combinedWait(int cost) {
    final Duration gate = waitDuration(cost);
    final DateTime afterGate = _now().add(gate);
    final DateTime? last = _lastReleased;
    if (last == null) {
      return gate;
    }
    final DateTime earliestByInterval = last.add(minInterval);
    return earliestByInterval.isAfter(afterGate)
        ? earliestByInterval.difference(_now())
        : gate;
  }

  /// 放行一个请求：记入窗口账本并更新「上次放行时刻」。
  ///
  /// 精确模式由计数传输层在请求发出前调用（发出前记：失败的请求同样占
  /// 服务端配额）；估算模式由装饰层调用。
  void release(int cost) {
    recordN(cost);
    _lastReleased = _now();
  }

  /// 等待直到能容纳 [cost] 个名额**且**满足最小间隔；超过 [maxWait] 仍不行
  /// 则抛 [RateLimitExceededException]（不无限阻塞调用方）。
  Future<void> acquire(int cost, Duration maxWait) async {
    if (cost > maxRequests) {
      throw RateLimitExceededException(
        used: usedInWindow,
        maxRequests: maxRequests,
        requiredCost: cost,
        maxWait: maxWait,
      );
    }
    final deadline = _now().add(maxWait);
    while (true) {
      final wait = combinedWait(cost);
      if (wait == Duration.zero) {
        return;
      }
      if (_now().add(wait).isAfter(deadline)) {
        throw RateLimitExceededException(
          used: usedInWindow,
          maxRequests: maxRequests,
          requiredCost: cost,
          maxWait: maxWait,
        );
      }
      await _delay(wait);
    }
  }
}

/// 等待超过上限仍拿不到名额时抛出；调用方（同步引擎）按本次同步失败
/// 处理即可，op-log 未消费，下一轮兜底会重试。
class RateLimitExceededException implements Exception {
  const RateLimitExceededException({
    required this.used,
    required this.maxRequests,
    required this.requiredCost,
    required this.maxWait,
  });

  /// 抛出时窗口内已用请求数。
  final int used;

  /// 预算上限。
  final int maxRequests;

  /// 本次调用需要的名额数。
  final int requiredCost;

  /// 允许等待的上限。
  final Duration maxWait;

  @override
  String toString() =>
      'RateLimitExceededException(窗口已用 $used/$maxRequests，本次需 '
      '$requiredCost 个名额，等待上限 ${maxWait.inMinutes} 分钟内无法腾出)';
}

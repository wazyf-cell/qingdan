/// 同步报告与请求计数包装（SyncEngine 的可观测性辅助层，方案设计 §5.5）。
///
/// 拆出本文件的原因：sync_engine.dart 只放流程编排；报告结构与「每次
/// backend 调用都计数」的机制集中在这里便于审查。
library;

import 'sync_backend.dart';

/// 一次 [SyncEngine.sync] 的执行报告。
///
/// `requests` 统计的是**所有** backend 调用次数（list/get/put/delete）。
/// 坚果云免费版 600 请求/30 分钟是硬约束，每次条件写约 3 请求，所以
/// 「本次同步用了几个请求」必须是一等公民数据，不能事后估。
class SyncReport {
  /// 上传的实体文件数（不含墓碑与 manifest）。
  int uploaded = 0;

  /// 从云端应用到本地的对象数（新实体 + takeRemote + 墓碑）。
  int downloaded = 0;

  /// 三路合并产生新状态（merged 分支）的实体数。
  int merged = 0;

  /// 真冲突字段总数（靠 modifiedTime LWW 决胜的那些字段）。
  int conflicts = 0;

  /// 本次同步消耗的 backend 请求总数。
  int requests = 0;

  /// 同步耗时（毫秒）。
  int durationMs = 0;

  /// 过程中捕获的全部异常（含 412 重试耗尽）。空列表 = 本次同步干净。
  final List<Object> errors = <Object>[];

  /// 是否发生了任何数据变更（决定要不要写 manifest，省一次请求）。
  bool get hasChanges => uploaded > 0 || downloaded > 0 || merged > 0;

  Map<String, Object?> toMap() => <String, Object?>{
        'uploaded': uploaded,
        'downloaded': downloaded,
        'merged': merged,
        'conflicts': conflicts,
        'requests': requests,
        'durationMs': durationMs,
        'errors': errors.map((Object e) => e.toString()).toList(),
      };

  @override
  String toString() => 'SyncReport${toMap()}';
}

/// 给任意 [SyncBackend] 套一层计数器。
///
/// 引擎只经由它访问远端，保证「每次 backend 调用都计数」不靠人肉纪律——
/// 漏数一个 get，请求数就失去预算意义。`capabilities()` 是声明性查询、
/// 不产生网络往返语义，不计数。
class CountingSyncBackend implements SyncBackend {
  CountingSyncBackend(this._inner, this.report);

  final SyncBackend _inner;
  final SyncReport report;

  int get count => report.requests;

  @override
  Future<List<RemoteObject>> list(String namespace) async {
    report.requests++;
    return _inner.list(namespace);
  }

  @override
  Future<({List<int> bytes, String? etag})> get(String path) async {
    report.requests++;
    return _inner.get(path);
  }

  @override
  Future<String?> put(String path, List<int> bytes, {String? ifMatchEtag}) async {
    report.requests++;
    return _inner.put(path, bytes, ifMatchEtag: ifMatchEtag);
  }

  @override
  Future<void> delete(String path, {String? ifMatchEtag}) async {
    report.requests++;
    return _inner.delete(path, ifMatchEtag: ifMatchEtag);
  }

  @override
  Future<void> ensureReady() => _inner.ensureReady();

  @override
  Future<BackendCapabilities> capabilities() => _inner.capabilities();
}

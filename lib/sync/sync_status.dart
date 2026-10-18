/// 同步状态快照（M3 §5.1 六态）——协调器与状态 UI 的共同语言。
///
/// 单独成文件的原因：状态 UI（sync_status_model / 侧栏槽）只应依赖这份
/// 纯数据，不得 import 协调器去摸它的 db / backend；协调器也不该 import UI。
library;

import 'sync_report.dart';

/// 六态（§5.1 表格逐条对应）。
enum SyncStatusKind {
  /// 无凭据 / 开关关闭：槽位显示「同步未配置」。
  unconfigured,

  /// 空闲（=上次成功）：显示「上次同步 HH:mm」。
  idle,

  /// 一轮进行中：显示「同步中…」。
  running,

  /// 最近一轮失败（退避中）：显示「同步失败 · 点击查看」。
  failed,

  /// 401/403 凭据失效：显示「需要重新配置」，不自动重试。
  credentialsInvalid,

  /// 触及请求预算：显示「限流 · HH:mm 恢复」。
  rateLimited,
}

/// 不可变状态快照。每次变化由协调器经 statusStream 推给 UI。
class SyncStatus {
  const SyncStatus({
    required this.kind,
    this.lastSuccessAt,
    this.lastReport,
    this.lastError,
    this.retryAt,
  });

  /// 当前态。
  final SyncStatusKind kind;

  /// 上次成功同步的完成时刻（本地时间）；从未成功为 null。
  final DateTime? lastSuccessAt;

  /// 最近一轮的同步报告（成功/失败都留，供详情卡展示 ↑N ↓N 合并N）。
  final SyncReport? lastReport;

  /// 最近拦截到的失败原因（原始异常对象，详情卡展示原文）。
  final Object? lastError;

  /// 限流/退避后的下一次重试时刻（本地时间）；无计划为 null。
  final DateTime? retryAt;

  /// 是否有「需要注意」的异常（失败 / 凭据失效 / 限流）。
  bool get hasProblem =>
      kind == SyncStatusKind.failed ||
      kind == SyncStatusKind.credentialsInvalid ||
      kind == SyncStatusKind.rateLimited;

  SyncStatus copyWith({
    SyncStatusKind? kind,
    DateTime? lastSuccessAt,
    SyncReport? lastReport,
    Object? lastError,
    DateTime? retryAt,
  }) =>
      SyncStatus(
        kind: kind ?? this.kind,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
        lastReport: lastReport ?? this.lastReport,
        lastError: lastError ?? this.lastError,
        retryAt: retryAt ?? this.retryAt,
      );
}

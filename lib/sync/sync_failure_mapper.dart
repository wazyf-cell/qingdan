/// 同步结果 → 状态迁移的纯映射（M3 §1.5）。
///
/// 单独成文件的原因：协调器的主职责是「何时跑 + 单飞」，而「一轮跑完之后
/// 该变成哪个态、要不要退避」是纯查表逻辑，把它放在协调器里会让那个文件
/// 超出行数红线（AGENTS.md：单文件 ≤300 行）。
///
/// 这里**只做映射，不做调度**：退避计数器的自增、timer 的排队/撤销仍归
/// 协调器——那些是带状态和副作用的操作。本文件导出 [SyncFailureOutcome]，
/// 由协调器按 [retryAfter] 的真假决定走哪条调度路径。
library;

import 'request_budget.dart' show RateLimitExceededException;
import 'sync_backend.dart' show SyncConfigException;
import 'sync_report.dart';
import 'sync_status.dart';

/// 失败退避序列：1 → 2 → 4 → 8 → 15 分钟，封顶 15，成功即清零（§1.5）。
const List<Duration> kSyncBackoff = <Duration>[
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 4),
  Duration(minutes: 8),
  Duration(minutes: 15),
];

/// 限流后的重试等待：一个预算窗口（§1.5）。
const Duration kSyncRateLimitRetry = Duration(minutes: 30);

/// 把异常翻译成「目标状态 + 重试意图」。调度动作本身由协调器执行。
class SyncFailureOutcome {
  const SyncFailureOutcome({required this.snapshot, this.retryAfter});

  /// 要发布的状态快照。
  final SyncStatus snapshot;

  /// 非空 = 排一次重试；null = 不自动重试（凭据失效与未配置同属此列）。
  ///
  /// 语义是「退避序列的下一档」，而不是具体时长——真正的档位由协调器按
  /// 它自己的退避计数决定，映射层不该知道那个计数器。限流例外：它带的是
  /// 一个确定时长，且**不进退避序列**（否则限流会把网络失败的退避档位
  /// 往上顶，恢复后第一轮就等 15 分钟）。
  final Duration? retryAfter;
}

/// 未配置/开关关闭时的状态：保留上次成功时刻与上次报告供 UI 展示。
SyncStatus unconfiguredStatus(SyncStatus current) => SyncStatus(
      kind: SyncStatusKind.unconfigured,
      lastSuccessAt: current.lastSuccessAt,
      lastReport: current.lastReport,
    );

/// 地址与账号都在、密码却从凭据库读不回来：走「需要重新配置」而不是
/// 「未配置」，且带上原因——用户要做的动作是重输一次密码，不是重新填表。
SyncStatus credentialReadFailedStatus(SyncStatus current) => SyncStatus(
      kind: SyncStatusKind.credentialsInvalid,
      lastSuccessAt: current.lastSuccessAt,
      lastReport: current.lastReport,
      lastError: '同步已启用，但系统凭据库里读不到应用密码'
          '（Android 上多为 Keystore 冷启动解不开自己写入的条目）。'
          '请到 设置 → 同步 重新输入一次应用密码并保存。',
    );

/// 一轮成功：回 idle，带本轮报告并刷新成功时刻。
SyncStatus successStatus(SyncReport report, DateTime now) => SyncStatus(
      kind: SyncStatusKind.idle,
      lastSuccessAt: now,
      lastReport: report,
    );

/// 一轮结束但有错误条目：回 failed，带本轮报告与首条错误，走退避。
SyncFailureOutcome failedRunOutcome(SyncStatus current, SyncReport report) =>
    SyncFailureOutcome(
      snapshot: SyncStatus(
        kind: SyncStatusKind.failed,
        lastSuccessAt: current.lastSuccessAt,
        lastReport: report,
        lastError: report.errors.first,
      ),
      retryAfter: Duration.zero,
    );

/// 捕获到的异常 → 状态与重试意图。分支顺序即优先级，不可重排。
///
/// [retryAfter] 为 [Duration.zero] 表示「按协调器的退避序列排」；为 null
/// 表示不重试；为其他值表示「等这么久再试，不动退避序列」。
SyncFailureOutcome mapSyncFailure(SyncStatus current, Object error, DateTime now) {
  if (error is RateLimitExceededException) {
    return SyncFailureOutcome(
      snapshot: SyncStatus(
        kind: SyncStatusKind.rateLimited,
        lastSuccessAt: current.lastSuccessAt,
        lastError: error,
        retryAt: now.add(kSyncRateLimitRetry),
      ),
      retryAfter: kSyncRateLimitRetry,
    );
  }
  if (error is SyncConfigException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      // 凭据失效不自动重试，转「需要重新配置」（§1.5）。协调器还必须连同
      // **已排队的退避 timer** 一起撤销：否则先网络失败（已排 1 分钟重试）、
      // 用户随即手动同步拿到 401，那个旧 timer 到期仍会跑一轮，违背
      // 「401 不重试」。
      return SyncFailureOutcome(
        snapshot: SyncStatus(
          kind: SyncStatusKind.credentialsInvalid,
          lastSuccessAt: current.lastSuccessAt,
          lastError: error,
        ),
      );
    }
    return SyncFailureOutcome(
      snapshot: SyncStatus(
        kind: SyncStatusKind.failed,
        lastSuccessAt: current.lastSuccessAt,
        lastError: error,
      ),
      retryAfter: Duration.zero,
    );
  }
  return SyncFailureOutcome(
    snapshot: SyncStatus(
      kind: SyncStatusKind.failed,
      lastSuccessAt: current.lastSuccessAt,
      lastError: error,
    ),
    retryAfter: Duration.zero,
  );
}

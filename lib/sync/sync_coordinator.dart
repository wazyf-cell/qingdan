// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 同步协调器：触发 / 防抖 / 单飞 / 兜底轮询 / 退避 / 状态机（M3 §1、§2.1、§5.1）。
///
/// 边界（AGENTS.md 铁律）：协调器不碰 UI 状态，只做三件事——按策略决定
/// 何时跑、跑一轮（经 [SyncRunner]）、把状态经 [statusStream] 广播出去。
/// UI 侧由 SyncStatusModel 订阅，数据库写入由引擎负责。
///
/// 触发源（§1）：
/// - 本地写：OpLogWriter.append 经回调 → [notifyLocalChange]（**只置内存
///   计时，不做任何 IO**；事务回滚会产生一次虚假脏标记，代价是多跑一轮
///   近乎空转的同步，这是有意接受的取舍）；
/// - 启动：延迟 3 s 一次（等 UI 首帧稳定，兼 F44「启动自动同步」）；
/// - 兜底：`Timer.periodic` 固定 30 分钟（定案区间上限端）；
/// - 手动：[syncNow] 立即执行，跳过 60 s 最小间隔，但仍走单飞闸门。
///
/// 「一轮跑完变成哪个态」的查表逻辑在 sync_failure_mapper.dart；本文件只
/// 负责带状态的调度部分（退避计数自增、timer 排队与撤销）。
library;

import 'dart:async';

import 'sync_config_store.dart';
import 'sync_failure_mapper.dart';
import 'sync_report.dart';
import 'sync_runner.dart';
import 'sync_status.dart';
import 'sync_timers.dart';

export 'sync_failure_mapper.dart' show kSyncBackoff, kSyncRateLimitRetry;
export 'sync_timers.dart' show Cancelable, RealSyncTimers, SyncTimers;

/// 防抖窗口（trailing）：首个改动启动计时，窗口内新改动重置计时（§1.2）。
const Duration kSyncDebounce = Duration(milliseconds: 2000);

/// 最小重同步间隔：距上次同步完成不足此值则挂起到间隔点（§1.2）。
const Duration kSyncMinInterval = Duration(seconds: 60);

/// 启动后首次自动同步的延迟（§1.2）。
const Duration kSyncStartupDelay = Duration(seconds: 3);

/// 兜底轮询间隔（§1.3：常量 30 分钟，不做可调）。
const Duration kSyncFallbackInterval = Duration(minutes: 30);

/// 同步协调器。main 装配一次，全生命周期存活。
class SyncCoordinator {
  SyncCoordinator({
    required SyncConfigStore configStore,
    required SyncRunnerFactory runnerFactory,
    SyncTimers? timers,
  })  : _configStore = configStore,
        _factory = runnerFactory,
        _timers = timers ?? const RealSyncTimers();

  final SyncConfigStore _configStore;
  final SyncRunnerFactory _factory;
  final SyncTimers _timers;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  SyncStatus _status = const SyncStatus(kind: SyncStatusKind.unconfigured);
  // 上次成功时刻不再单存字段：它就是 _status.lastSuccessAt，映射层从一个
  // 真相源读取，避免两个副本漂移。
  DateTime? _lastCompletedAt;
  int _backoffAttempt = 0;
  bool _disposed = false;
  bool _started = false;

  Cancelable? _debounceTimer;
  Cancelable? _autoTimer;
  Cancelable? _startupTimer;
  Cancelable? _periodicTimer;
  Cancelable? _retryTimer;

  /// 单飞：非空表示有一轮在执行；此时新请求只置 [_pendingDirty]。
  Future<void>? _inFlight;
  bool _pendingDirty = false;

  /// 状态广播流（UI 订阅；广播型，可多订阅者）。
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// 当前状态快照。
  SyncStatus get status => _status;

  /// 本窗口已用请求数（详情卡展示，取自当前装配链的 RequestBudget）。
  int get requestsUsedInWindow => _factory.requestsUsedInWindow;

  /// 启动定时触发源（启动首同步 + 兜底轮询）。幂等。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _startupTimer = _timers.after(kSyncStartupDelay, _ensure);
    _periodicTimer = _timers.periodic(kSyncFallbackInterval, _ensure);
  }

  /// 本地写回调：重置防抖计时（不做 IO，见文件头注释）。
  void notifyLocalChange() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = _timers.after(kSyncDebounce, () {
      _debounceTimer = null;
      _scheduleAuto();
    });
  }

  /// 手动同步：立即执行，跳过 60 s 最小间隔，但仍走单飞闸门。
  Future<void> syncNow() => _ensure();

  /// 释放全部定时器与传输链。之后任何触发都变为 no-op。
  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    _autoTimer?.cancel();
    _startupTimer?.cancel();
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    await _factory.dispose();
    await _statusController.close();
  }

  // ---------- 触发路径 ----------

  /// 自动触发（防抖后 / 兜底 / 启动）：受 60 s 最小间隔节流。
  void _scheduleAuto() {
    _autoTimer?.cancel();
    final Duration remaining = _minIntervalRemaining();
    if (remaining <= Duration.zero) {
      _autoTimer = null;
      _ensure();
    } else {
      _autoTimer = _timers.after(remaining, () {
        _autoTimer = null;
        _ensure();
      });
    }
  }

  Duration _minIntervalRemaining() {
    final DateTime? last = _lastCompletedAt;
    if (last == null) return Duration.zero;
    final Duration remaining =
        kSyncMinInterval - _timers.now().difference(last);
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  /// 单飞闸门：已在跑则只置脏标记并复用同一个 Future（§1.4）。
  Future<void> _ensure() {
    if (_disposed) return Future<void>.value();
    final Future<void>? existing = _inFlight;
    if (existing != null) {
      _pendingDirty = true;
      return existing;
    }
    final Completer<void> done = Completer<void>();
    _inFlight = done.future;
    unawaited(_pump(done));
    return done.future;
  }

  Future<void> _pump(Completer<void> done) async {
    try {
      await _runOne();
      // 运行期间有新请求：补跑**一轮**（不叠加）。补跑期间再次到来的改动由
      // notifyLocalChange 的防抖重新排队，不会丢。
      if (_pendingDirty && !_disposed) {
        _pendingDirty = false;
        await _runOne();
      }
      done.complete();
    } catch (e, st) {
      // _runOne 已兜住全部异常；这里是防御性兜底，避免 Future 悬挂。
      done.completeError(e, st);
    } finally {
      _pendingDirty = false;
      _inFlight = null;
    }
  }

  // ---------- 单轮执行 ----------

  Future<void> _runOne() async {
    if (_disposed) return;
    final SyncConfig config;
    try {
      config = await _configStore.load();
    } catch (e) {
      _lastCompletedAt = _timers.now();
      _publish(_status.copyWith(kind: SyncStatusKind.failed, lastError: e));
      _scheduleBackoff();
      return;
    }

    if (!config.isConfigured) {
      // 未配置（或用户关了同步）：撤掉可能还在排队的重试，退避计数也归零，
      // 否则「关了同步」之后旧的退避 timer 仍会把标记过一次的同步跑起来。
      _cancelRetry();
      _backoffAttempt = 0;
      // 三要素齐、唯独密码读不回来 = 凭据库故障，不是没配过：两者都发
      // unconfigured 会把人引去翻配置表，而实际要做的是重输密码（§5.1）。
      _publish(config.credentialMissing
          ? credentialReadFailedStatus(_status)
          : unconfiguredStatus(_status));
      return;
    }

    _publish(_status.copyWith(kind: SyncStatusKind.running));
    try {
      final SyncReport report = await _factory.create(config).run();
      _lastCompletedAt = _timers.now();
      if (report.errors.isEmpty) {
        _backoffAttempt = 0;
        _cancelRetry();
        _publish(successStatus(report, _timers.now()));
      } else {
        _applyFailure(failedRunOutcome(_status, report));
      }
    } catch (e) {
      _lastCompletedAt = _timers.now();
      _applyFailure(mapSyncFailure(_status, e, _timers.now()));
    }
  }

  /// 落一条失败结论。
  ///
  /// [SyncFailureOutcome.retryAfter] 为 null 时**必须**撤销已排队的退避
  /// timer 并把计数归零（401/403 场景，见映射器注释）；为零走退避序列
  /// （档位由 [_backoffAttempt] 决定）；为其他值直接等这么久。
  void _applyFailure(SyncFailureOutcome outcome) {
    final Duration? retryAfter = outcome.retryAfter;
    if (retryAfter == null) {
      _cancelRetry();
      _backoffAttempt = 0;
      _publish(outcome.snapshot);
      return;
    }
    _publish(outcome.snapshot);
    if (retryAfter == Duration.zero) {
      _scheduleBackoff();
    } else {
      _scheduleRetry(retryAfter);
    }
  }

  void _scheduleBackoff() {
    final int index = _backoffAttempt < kSyncBackoff.length
        ? _backoffAttempt
        : kSyncBackoff.length - 1;
    _backoffAttempt++;
    _scheduleRetry(kSyncBackoff[index]);
  }

  void _scheduleRetry(Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = _timers.after(delay, () {
      _retryTimer = null;
      _ensure();
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _publish(SyncStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}

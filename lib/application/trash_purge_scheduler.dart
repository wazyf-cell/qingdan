// 回收站自动清空调度（M6-A4）。
//
// 诚实边界：Android 后台会被系统杀掉，**没有真定时**（总纲 §四.4 已确认不做）。
// 实际节奏 = 「应用启动时立即检查一次 + 应用存活期每 30 分钟再检查一次」。
// 用户天天开应用 ≈ 天天清；两周不开则两周后才清——数据不丢，只是没删。
// 只调 TaskUseCase，不碰 DAO（铁律）；也**不在 SyncCoordinator 里**——
// 同步关掉时回收站照样要清，两件事不耦合。
library;

import 'package:flutter/foundation.dart';

import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/sync/sync_timers.dart';

/// 检查节奏：与同步兜底轮询同值（30 分钟），但常量独立、互不牵连。
const Duration kTrashPurgeCheckInterval = Duration(minutes: 30);

class TrashPurgeScheduler {
  TrashPurgeScheduler({
    required this._useCase,
    required this._settings,
    SyncTimers? timers,
  }) : _timers = timers ?? const RealSyncTimers();

  final TaskUseCase _useCase;
  final SettingsModel _settings;
  final SyncTimers _timers;

  Cancelable? _timer;
  bool _started = false;
  bool _running = false;
  Future<void>? _lastTick;

  /// 立即检查一次，然后挂 30 分钟周期。幂等；异步体（首轮检查）在返回前完成。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final Future<void> first = _guardedRun();
    _lastTick = first;
    await first;
    // 首轮跑期间被 stop（Windows 关窗）→ 不再挂周期。
    if (!_started) return;
    _timer ??= _timers.periodic(kTrashPurgeCheckInterval, _onTick);
  }

  /// 取消周期并拒绝后续启动（与 [start] 成对；关窗路径调用）。
  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 供测试等待最近一轮检查落定（start 与周期 tick 共用同一个句柄）。
  @visibleForTesting
  Future<void>? get lastTick => _lastTick;

  void _onTick() {
    final Future<void> tick = _guardedRun();
    _lastTick = tick;
  }

  Future<void> _guardedRun() async {
    if (_running) return; // 单飞：一轮没跑完不重入。
    final int days = _settings.trashPurgeDays;
    if (days <= 0) return; // 永不：连用例都不调。
    _running = true;
    try {
      final int purged = await _useCase.purgeExpiredTrash(days: days);
      if (purged > 0) {
        // 只打条数，不打任何用户数据（标题/备注）。
        debugPrint('回收站自动清空：删除 $purged 条（阈值 $days 天）');
      }
    } catch (e) {
      // 失败只留类型名：异常原文可能携带行数据，不整条打出来。
      debugPrint('回收站自动清空失败：${e.runtimeType}');
    } finally {
      _running = false;
    }
  }
}

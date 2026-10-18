import "dart:async";

import "package:flutter/foundation.dart";

import "package:qingdan/sync/sync_coordinator.dart";
import "package:qingdan/sync/sync_status.dart";

/// 侧栏同步状态槽的数据模型（M3 §5.2）。
///
/// 只做两件事：订阅协调器的状态流、把最近状态与预算用量转成 UI 能读的
/// 值。它**不接触 DAO / AppServices**（AGENTS.md 铁律），UI 也不直接碰
/// 协调器——中间隔一层可测试的 ChangeNotifier。
class SyncStatusModel extends ChangeNotifier {
  SyncStatusModel({required SyncCoordinator coordinator, this.deviceId})
      : _coordinator = coordinator {
    _status = coordinator.status;
    _subscription = coordinator.statusStream.listen((SyncStatus s) {
      _status = s;
      notifyListeners();
    });
  }

  final SyncCoordinator _coordinator;
  late final StreamSubscription<SyncStatus> _subscription;
  late SyncStatus _status;

  /// 本机设备标识（详情卡展示；由 main 从数据库 `_meta` 读出后注入，
  /// UI 层不得自行访问数据库）。
  final String? deviceId;

  /// 最近一次状态快照。
  SyncStatus get status => _status;

  /// 本窗口已用请求数（详情卡「23 / 600」）。
  int get requestsUsedInWindow => _coordinator.requestsUsedInWindow;

  /// 手动同步（列表标题行按钮 / 详情卡按钮）。
  Future<void> syncNow() => _coordinator.syncNow();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

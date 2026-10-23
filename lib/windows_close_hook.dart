import 'package:window_manager/window_manager.dart';

import 'package:qingdan/application/trash_purge_scheduler.dart';
import 'package:qingdan/sync/sync_coordinator.dart';

/// Windows 关窗 = 退出：拦截关闭 → 触发一次同步（封顶 10s）→ destroy。
///
/// 从 `main.dart` 拆出来的（v1.0.6 加小组件装配后 main 越过 300 行上限，
/// AGENTS.md 的硬规矩）：这块只在桌面端生效，与 App 的装配顺序无关。
/// 监听器实例存进顶层变量（而非临时对象）——window_manager 的 addListener
/// 若收到会被 GC 的临时对象，回调会静默失效（该库的已知坑）。
_WindowCloseSyncHook? _windowCloseHook;

void installWindowsCloseHook(
    SyncCoordinator coordinator, TrashPurgeScheduler trashPurge) {
  windowManager.setPreventClose(true);
  _windowCloseHook = _WindowCloseSyncHook(coordinator, trashPurge);
  windowManager.addListener(_windowCloseHook!);
}

/// 关窗同步钩子（见 [installWindowsCloseHook]）。
class _WindowCloseSyncHook with WindowListener {
  _WindowCloseSyncHook(this._coordinator, this._trashPurge);

  final SyncCoordinator _coordinator;
  final TrashPurgeScheduler _trashPurge;
  bool _closing = false;

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;
    // 先停清空调度：退出窗口期不应再有物理删除发生（op-log 意图留在库里，
    // 下次启动的同步照常上传）。
    _trashPurge.stop();
    try {
      await _coordinator.syncNow().timeout(const Duration(seconds: 10));
    } catch (_) {
      // 超时或失败都不阻塞退出：数据留在本地 op-log，下次启动兜底再传。
    }
    await windowManager.destroy();
  }
}

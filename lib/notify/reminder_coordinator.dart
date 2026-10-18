// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 提醒协调器（M6-C2 §6）：把「什么时候重排」收在一处，让设置页与通知引擎互不认识。
///
/// 订阅的变更源（一律按 [Listenable] 收，所以本文件不 import 任何 `features/`）：
/// - [NotifySettingsStore]：任一 `notify.*` 改动（构造时给定，自动订阅）；
/// - 任务侧：`TaskPaneModel` 的创建/更新/完成/删除/进回收站末尾都会 `notifyListeners`；
/// - 学习通侧：`ChaoxingModel.refresh()` 结束（成功或失败）都会 `notifyListeners`。
/// 「启动」与「从后台回到前台」两个触发点由 `main.dart` / `app_lifecycle.dart` 打
/// [notifyChanged]，本类不自己碰生命周期。防抖照 `sync_coordinator.dart` 的写法：
/// trailing，每次新变更撤掉旧 Timer 重排（批量改 20 条只重排一次）。
///
/// 边界：只读数据、只调通知引擎，**不写库、不碰 UI 状态**。任何一次失败都只
/// `debugPrint`——提醒是增强功能，不能把任务列表或启动路径带崩。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/notify/chaoxing_snapshot.dart';
import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/notify/reminder_plan.dart';

/// 防抖窗口：变更停止这么久之后才真正重排。
const Duration kReminderDebounce = Duration(milliseconds: 500);

/// 任务来源：由装配根注入 `TaskUseCase.findAllActive`（UI 层不许碰 DAO，本类也不碰）。
typedef TaskReminderSource = Future<List<Task>> Function();

/// C4 §2 的筛选侧：学习通条目 → 提醒快照项。排除已隐藏 / 服务端已完成 / 已结束 /
/// 无截止时间 / 截止已过。放本文件（而不是 `ChaoxingModel`）：模型那边只留一个回调
/// 钩子（300 行红线），而这份筛选与排程判据本来就住在一起。
List<ChaoxingSnapshotItem> chaoxingSnapshotOf(
    List<ChaoxingTask> tasks, Set<String> hidden, DateTime now) =>
    <ChaoxingSnapshotItem>[
      for (final ChaoxingTask t in tasks)
        if (!hidden.contains(t.key) && !t.serverDone && t.ongoing)
          if (t.dueAt != null && t.dueAt!.isAfter(now))
            ChaoxingSnapshotItem(
                key: t.key, courseName: t.courseName, title: t.title, dueAt: t.dueAt),
    ];

class ReminderCoordinator {
  ReminderCoordinator({
    required NotificationService service,
    required NotifySettingsStore settings,
    required ChaoxingSnapshotStore snapshot,
    TaskReminderSource? taskSource,
    Iterable<Listenable> sources = const <Listenable>[],
    Duration debounce = kReminderDebounce,
  })  : _service = service,
        _settings = settings,
        _snapshot = snapshot,
        _taskSource = taskSource,
        _listenables = List<Listenable>.unmodifiable(<Listenable>[settings, ...sources]),
        _debounce = debounce;

  final NotificationService _service;
  final NotifySettingsStore _settings;
  final ChaoxingSnapshotStore _snapshot;
  final TaskReminderSource? _taskSource;
  final List<Listenable> _listenables;
  final Duration _debounce;

  Timer? _timer;
  bool _started = false, _disposed = false;

  /// 总开关关着时快照已经清过一次：不重复 `remove`（每次任务改动都会走到这里）。
  bool _snapshotCleared = false;

  /// 最近一次真正排下去的条数（测试与排查用）。
  int get lastScheduled => _lastScheduled;
  int _lastScheduled = 0;

  /// 订阅全部变更源并排第一次。幂等。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    for (final Listenable l in _listenables) {
      l.addListener(notifyChanged);
    }
    notifyChanged(); // 触发点「应用启动」
  }

  /// 任意变更入口：重置防抖计时，不做 IO。
  void notifyChanged() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      _timer = null;
      unawaited(rescheduleNow());
    });
  }

  /// 立刻全量重排，返回排下去的条数。总开关关掉 = `cancelAll()` + 清快照。
  Future<int> rescheduleNow() async {
    if (_disposed) return 0;
    try {
      final NotifySettings s = _settings.value;
      if (!s.enabled) {
        await _service.cancelAll();
        if (!_snapshotCleared) {
          await _snapshot.clearSnapshot(); // C4 §3：总开关关闭即清
          _snapshotCleared = true;
        }
        return _lastScheduled = 0;
      }
      _snapshotCleared = false;
      final List<Reminder> plan = planReminders(
        tasks: await _readTasks(),
        items: await _snapshot.readSnapshot(),
        now: DateTime.now(),
        cfg: s,
      );
      return _lastScheduled = await _service.rescheduleAll(plan);
    } catch (e) {
      // 只打类型：任务标题与课程名都是用户数据。
      debugPrint('提醒重排失败：${e.runtimeType}');
      return _lastScheduled;
    }
  }

  /// 没注入来源（数据库初始化失败、或纯 UI 测试）就当没有任务。
  Future<List<Task>> _readTasks() async =>
      _taskSource == null ? const <Task>[] : await _taskSource();

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_started) {
      for (final Listenable l in _listenables) {
        l.removeListener(notifyChanged);
      }
    }
  }
}

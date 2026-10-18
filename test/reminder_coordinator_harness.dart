// 提醒协调器测试的共用夹具（自 reminder_coordinator_test.dart 拆出；非 `_test`
// 文件，flutter test 不直接执行）。
//
// 拆分后的两份文件：
//  - reminder_coordinator_reschedule_test.dart —— 重排触发（防抖/触发源/总开关/静默失败）
//  - reminder_coordinator_snapshot_test.dart  —— 快照筛选与 ChaoxingModel 写入钩子
//
// 全部测试**不碰数据库**：任务侧走 `TaskReminderSource` 注入的内存表，通知侧走假
// `NotificationSink`，所以不需要 `tester.runAsync`。
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DidReceiveNotificationResponseCallback;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/import/chaoxing/chaoxing_client.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/notify/chaoxing_snapshot.dart';
import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/notify/reminder_coordinator.dart';

/// 只记录调用序列的假通知层（真插件在没有平台通道的测试里跑不起来）。
class FakeNotificationSink implements NotificationSink {
  final List<String> calls = <String>[];
  final List<ScheduledReminder> scheduled = <ScheduledReminder>[];
  bool permission = true, enabled = true;

  @override
  Future<void> initialize({DidReceiveNotificationResponseCallback? onResponse}) async =>
      calls.add('initialize');
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    scheduled.clear();
  }

  @override
  Future<void> schedule(ScheduledReminder item) async {
    calls.add('schedule:${item.id}');
    scheduled.add(item);
  }

  /// 最近一轮排下去的条数：`cancelAll` 会清空 [scheduled]，所以它就是「这一轮」的数量。
  int get lastRound => scheduled.length;
}

/// 测试用的窄时窗：不等 500ms，但防抖语义照旧。
const Duration kFast = Duration(milliseconds: 20);
const Duration kSettle = Duration(milliseconds: 120);

Task makeReminderTask(String id,
        {DateTime? due, bool completed = false, bool deleted = false}) =>
    Task(id: id, title: '任务$id', dueDate: due, completed: completed, deleted: deleted);

ChaoxingTask makeReminderChaoxingTask(
        String id, {DateTime? dueAt, bool ongoing = true, bool done = false, String? status}) =>
    ChaoxingTask(
        id: id,
        courseId: 'c1',
        courseName: '课程甲',
        title: '作业$id',
        kind: '作业',
        ongoing: ongoing,
        dueAt: dueAt,
        serverDone: done,
        serverStatus: status ?? '未提交');

class ReminderChaoxingClient extends ChaoxingClient {
  ReminderChaoxingClient() : super(cookie: 'placeholder-not-a-credential');
  List<ChaoxingTask> tasks = const <ChaoxingTask>[];
  bool fail = false;

  @override
  Future<List<ChaoxingTask>> fetchAllTasks() async {
    if (fail) throw StateError('作业页 502');
    courseCount = 1;
    return tasks;
  }

  @override
  void close() {}
}

/// `ChangeNotifier.hasListeners` 是 protected，只能从子类实例里读。用它真断言
/// 「dispose 把监听摘干净了」——否则 `_disposed` 的短路会让这条测试什么都没测到
/// （反证时把 removeListener 改成 addListener，没有这个探针它是绿的）。
class ReminderListenerProbe extends ChangeNotifier {
  bool get listened => hasListeners;
  void poke() => notifyListeners();
}

/// 一轮协调器测试的全部环境：prefs / 假通知层 / 设置存储 / 快照存储 / 内存任务表，
/// 外加 `build()`（起协调器并记下引用）与 `settle()`（等防抖落地）。
class ReminderHarness {
  ReminderHarness._(this.prefs, this.sink, this.service, this.store, this.snapshot);

  static Future<ReminderHarness> create() async {
    // 免打扰**显式关掉**：默认 23:00–07:00 开着时，任何「提前量已经过期」的提醒
    // 都会被顺延到次日 07:00（那是未来，过不了 `_finalize` 的过期滤网），于是
    // 同一条测试白天排 3 条、半夜排 4 条。套件曾在 23:00 跑，当场多出一条看不见
    // 来历的失败。顺延本身有专项测试（reminder_plan_quiet_and_limit_test，用固定
    // 的 now），协调器这边只关心「排了几条、id 连不连」，必须与墙上钟无关。
    SharedPreferences.setMockInitialValues(
        <String, Object>{'notify.quietHoursEnabled': false});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final FakeNotificationSink sink = FakeNotificationSink();
    final ReminderHarness h = ReminderHarness._(
      prefs,
      sink,
      NotificationService(sink: sink, supported: () => true),
      NotifySettingsStore(prefs: prefs),
      ChaoxingSnapshotStore(prefs: prefs),
    );
    await h.store.load();
    // 默认有一条 40 分钟后到期的任务：提前 30 分钟 + 到期时刻 → 恰好 2 条。
    h.table = <Task>[
      makeReminderTask('t1', due: DateTime.now().add(const Duration(minutes: 40)))
    ];
    return h;
  }

  final SharedPreferences prefs;
  final FakeNotificationSink sink;
  final NotificationService service;
  final NotifySettingsStore store;
  final ChaoxingSnapshotStore snapshot;
  List<Task> table = <Task>[];
  late ReminderCoordinator coordinator;

  /// 起一个协调器：默认订阅一个假 Listenable，验证「任务域变更 → 重排」这条线。
  ReminderCoordinator build(
      {TaskReminderSource? source, Iterable<Listenable>? sources}) {
    final ReminderCoordinator c = ReminderCoordinator(
      service: service,
      settings: store,
      snapshot: snapshot,
      taskSource: source ?? (() async => table),
      sources: sources ?? const <Listenable>[],
      debounce: kFast,
    );
    coordinator = c;
    return c;
  }

  Future<void> settle() => Future<void>.delayed(kSettle);
}

// 提醒协调器单测（M6-C2 §6 接线 + C4 §2 快照写入时机）。
//
// 全文件**不碰数据库**：任务侧走 `TaskReminderSource` 注入的内存表，通知侧走假
// `NotificationSink`，所以下面不需要 `tester.runAsync`。
//
// 反证点（每条都对应一处真实实现行为，改坏就会红）：防抖只排一次、总开关关掉
// 要 cancelAll + 清快照、设置变更要触发重排、dispose 后要静默、快照筛选的
// 五种排除、refresh 成功后写快照、写快照失败不许把成功抓取说成失败。
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DidReceiveNotificationResponseCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/chaoxing/chaoxing_prefs.dart';
import 'package:qingdan/import/chaoxing/chaoxing_client.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/notify/chaoxing_snapshot.dart';
import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/notify/reminder_coordinator.dart';
import 'package:qingdan/notify/reminder_plan.dart';
import 'package:qingdan/sync/secure_store.dart';

/// 只记录调用序列的假通知层（真插件在没有平台通道的测试里跑不起来）。
class _FakeSink implements NotificationSink {
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

Task _task(String id, {DateTime? due, bool completed = false, bool deleted = false}) =>
    Task(id: id, title: '任务$id', dueDate: due, completed: completed, deleted: deleted);

ChaoxingTask _cx(String id, {DateTime? dueAt, bool ongoing = true, bool done = false, String? status}) =>
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

class _FakeClient extends ChaoxingClient {
  _FakeClient() : super(cookie: 'placeholder-not-a-credential');
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
class _Probe extends ChangeNotifier {
  bool get listened => hasListeners;
  void poke() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _FakeSink sink;
  late NotificationService service;
  late NotifySettingsStore store;
  late ChaoxingSnapshotStore snapshot;
  late List<Task> table;
  late ReminderCoordinator coordinator;

  /// 起一个协调器：默认订阅一个假 Listenable，验证「任务域变更 → 重排」这条线。
  ReminderCoordinator build({TaskReminderSource? source, Iterable<Listenable>? sources}) {
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

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    sink = _FakeSink();
    service = NotificationService(sink: sink, supported: () => true);
    store = NotifySettingsStore(prefs: prefs);
    await store.load();
    snapshot = ChaoxingSnapshotStore(prefs: prefs);
    // 默认有一条 40 分钟后到期的任务：提前 30 分钟 + 到期时刻 → 恰好 2 条。
    table = <Task>[_task('t1', due: DateTime.now().add(const Duration(minutes: 40)))];
  });

  Future<void> settle() => Future<void>.delayed(kSettle);

  group('防抖与触发源', () {
    test('连续 5 次变更只重排一次（批量改地点不烧闹钟）', () async {
      final ReminderCoordinator c = build();
      c.start();
      c.notifyChanged();
      c.notifyChanged();
      c.notifyChanged();
      c.notifyChanged();
      await settle();
      expect(sink.calls.where((String x) => x == 'cancelAll').length, 1,
          reason: '防抖窗口内 5 次变更必须只排一轮');
      expect(sink.lastRound, 2, reason: '默认设置：提前 30 分钟 + 到期时刻');
    });

    test('NotifySettingsStore 的变更自动触发重排（设置页不需要认识协调器）', () async {
      final ReminderCoordinator c = build();
      c.start();
      await settle();
      final int before = sink.lastRound;
      await store.apply((NotifySettings s) => s.taskDueEnabled = false);
      await settle();
      expect(sink.lastRound, lessThan(before),
          reason: '关掉到期提醒后只剩提前那一条');
      expect(sink.lastRound, 1);
    });

    test('任务侧 Listenable（TaskPaneModel 的替身）触发重排并读到新数据', () async {
      final _Probe pane = _Probe();
      final ReminderCoordinator c = build(sources: <Listenable>[pane]);
      c.start();
      await settle();
      expect(sink.scheduled.map((ScheduledReminder r) => r.reminder.body),
          <String>['任务t1', '任务t1']);
      table = <Task>[
        _task('t2', due: DateTime.now().add(const Duration(minutes: 40))),
      ];
      pane.poke();
      await settle();
      expect(sink.scheduled.map((ScheduledReminder r) => r.reminder.body),
          <String>['任务t2', '任务t2'],
          reason: '重排必须重新读任务表，不能拿上一次的快照');
      pane.dispose();
    });

    test('start() 幂等：重复调用不会挂两份监听', () async {
      final ReminderCoordinator c = build();
      c.start();
      c.start();
      c.start();
      await settle();
      expect(sink.calls.where((String x) => x == 'cancelAll').length, 1);
    });
  });

  group('总开关', () {
    test('关掉 → cancelAll + 清快照 + 一条都不排', () async {
      await snapshot.writeSnapshot(<ChaoxingSnapshotItem>[
        ChaoxingSnapshotItem(
            key: 'k1',
            courseName: '课程甲',
            title: '作业1',
            dueAt: DateTime.now().add(const Duration(days: 1))),
      ]);
      final ReminderCoordinator c = build();
      c.start();
      await settle();
      // 任务 2 条（提前 30 + 到期）+ 学习通 2 条（提前 120 + 30，截止在 +1 天）。
      expect(sink.lastRound, 4);

      await store.setEnabled(false);
      await settle();
      expect(prefs.getString(kChaoxingSnapshotKey), isNull,
          reason: 'C4 §3：总开关关闭要清掉学习通提醒快照');
      expect(sink.lastRound, 0, reason: 'cancelAll 之后不应再有任何排程');
    });

    test('关着时再次变更不会重复清快照（清过一次就够）', () async {
      final ReminderCoordinator c = build();
      c.start();
      await store.setEnabled(false);
      await settle();
      // 关掉之后又落了一份快照（例如学习通在别处被刷新）：第二次重排不该再抹它，
      // 否则「清一次」的语义会变成「一直和写入方抢盘」。
      await snapshot.writeSnapshot(<ChaoxingSnapshotItem>[
        const ChaoxingSnapshotItem(
            key: 'k1', courseName: '课程甲', title: '作业1', dueAt: null),
      ]);
      final int before = sink.calls.length;
      coordinator.notifyChanged();
      await settle();
      expect(sink.calls.length, greaterThan(before), reason: '仍然会重排（只是排 0 条）');
      expect(prefs.getString(kChaoxingSnapshotKey), isNotNull,
          reason: '已清过一次就不该反复清盘');
    });

    test('重新打开后又能排提醒', () async {
      final ReminderCoordinator c = build();
      c.start();
      await store.setEnabled(false);
      await settle();
      expect(sink.lastRound, 0);
      await store.setEnabled(true);
      await settle();
      expect(sink.lastRound, 2);
    });
  });

  group('快照筛选（C4 §2）', () {
    test('排除已隐藏 / 已完成 / 已结束 / 无截止 / 截止已过', () {
      final DateTime now = DateTime(2026, 10, 18, 12);
      final DateTime future = now.add(const Duration(hours: 3));
      final List<ChaoxingSnapshotItem> kept = chaoxingSnapshotOf(
        <ChaoxingTask>[
          _cx('keep', dueAt: future, status: null),
          _cx('done', dueAt: future, done: true, status: null),
          _cx('ended', dueAt: future, ongoing: false, status: null),
          _cx('nodue', status: null),
          _cx('past', dueAt: now.subtract(const Duration(minutes: 1)), status: null),
          _cx('hidden', dueAt: future, status: null),
        ],
        <String>{'c1|hidden'},
        now,
      );
      expect(kept.map((ChaoxingSnapshotItem i) => i.key), <String>['c1|keep']);
      expect(kept.single.dueAt, future);
    });

    test('学习通项与任务项一起进同一份排程（id 连续、payload 正确）', () async {
      await snapshot.writeSnapshot(<ChaoxingSnapshotItem>[
        ChaoxingSnapshotItem(
            key: 'c1|a',
            courseName: '课程甲',
            title: '作业1',
            dueAt: DateTime.now().add(const Duration(minutes: 90))),
      ]);
      final ReminderCoordinator c = build();
      await c.rescheduleNow();
      expect(sink.lastRound, 3, reason: '任务 2 条 + 学习通第一档 1 条');
      expect(sink.scheduled.map((ScheduledReminder s) => s.id), <int>[0, 1, 2]);
      final List<Reminder> cx = sink.scheduled
          .map((ScheduledReminder s) => s.reminder)
          .where((Reminder r) => r.kind == kChaoxingReminderKind)
          .toList();
      expect(cx.single.payload, kChaoxingPayload);
      expect(cx.single.body, '课程甲 · 作业1');
      expect(c.lastScheduled, 3);
    });
  });

  group('失败要静默', () {
    test('任务源抛异常不外抛（提醒是增强功能，不能带崩任务列表）', () async {
      final ReminderCoordinator c =
          build(source: () async => throw StateError('库被打开了两次'));
      expect(await c.rescheduleNow(), 0, reason: '异常吞掉后返回上一次的值');
      c.start();
      await settle();
    });

    test('dispose 之后变更源再 notify 也不重排，且监听真的摘干净了', () async {
      final _Probe pane = _Probe();
      final ReminderCoordinator c = build(sources: <Listenable>[pane]);
      c.start();
      await settle();
      expect(pane.listened, isTrue, reason: '没订阅上，这条测试就什么都没测');
      final int before = sink.calls.length;
      await c.dispose();
      expect(pane.listened, isFalse, reason: '监听没摘干净：协调器比模型活得久就是泄漏');
      pane.poke();
      await store.setEnabled(false);
      await settle();
      expect(sink.calls.length, before, reason: 'dispose 后不该再排任何一轮');
      pane.dispose();
    });
  });

  group('ChaoxingModel 的快照钩子（C4 §2 写入时机）', () {
    late ChaoxingModel model;
    late _FakeClient client;

    Future<void> makeModel({bool hookThrows = false}) async {
      client = _FakeClient();
      model = ChaoxingModel(
        secure: InMemorySecureStore(<String, String>{
          ChaoxingModel.kCookieKey: 'placeholder-not-a-credential'
        }),
        prefs: ChaoxingPrefs(prefs: prefs),
        clock: () => DateTime(2026, 10, 18, 12),
        clientFactory: (String _) => client,
      );
      await model.restore();
      model.onReminderSnapshot = (List<ChaoxingTask> tasks, Set<String> hidden, DateTime now) async {
        if (hookThrows) throw StateError('prefs 写不进去');
        await snapshot.writeSnapshot(chaoxingSnapshotOf(tasks, hidden, now));
      };
    }

    test('refresh 成功后落快照，只含可排的项（隐藏的那条不落盘）', () async {
      await makeModel();
      final DateTime future = DateTime(2026, 10, 18, 12).add(const Duration(hours: 5));
      // 先隐藏 b：钩子必须把**当前** settings.hidden 传给筛选函数，传错就落进快照。
      await model.hide(_cx('b', dueAt: future));
      expect(model.settings.hidden, contains('c1|b'));
      client.tasks = <ChaoxingTask>[
        _cx('a', dueAt: future),
        _cx('b', dueAt: future),
        _cx('c', dueAt: future, done: true),
      ];
      await model.refresh();
      final List<ChaoxingSnapshotItem> read = await snapshot.readSnapshot();
      expect(read.map((ChaoxingSnapshotItem i) => i.key), <String>['c1|a']);
      expect(model.error, isNull);
      model.dispose();
    });

    test('快照写失败不许把一次成功的抓取标成失败', () async {
      await makeModel(hookThrows: true);
      client.tasks = <ChaoxingTask>[_cx('a', dueAt: DateTime(2026, 10, 18, 17))];
      await model.refresh();
      expect(model.error, isNull, reason: '写盘失败被吞在钩子里，不进 refresh 的 catch');
      expect(model.loggedIn, isTrue);
      expect(model.fetchedAt, isNotNull);
      model.dispose();
    });

    test('抓取失败时不写快照（没有可信的新数据，不能覆盖上一次）', () async {
      await makeModel();
      await snapshot.writeSnapshot(<ChaoxingSnapshotItem>[
        ChaoxingSnapshotItem(
            key: 'old',
            courseName: '课程甲',
            title: '上一次的作业',
            dueAt: DateTime(2026, 10, 18, 20)),
      ]);
      client.fail = true;
      await model.refresh();
      expect(model.error, isNotNull);
      final List<ChaoxingSnapshotItem> read = await snapshot.readSnapshot();
      expect(read.map((ChaoxingSnapshotItem i) => i.key), <String>['old'],
          reason: '写快照在 refresh 的成功路径末尾，失败时不该动盘');
      model.dispose();
    });
  });
}

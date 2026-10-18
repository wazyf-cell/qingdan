// 提醒协调器单测·重排触发部分（M6-C2 §6 接线）。自 reminder_coordinator_test.dart 拆出：
// 本文件管「防抖与触发源 / 总开关 / 失败要静默」三条线；快照筛选与 ChaoxingModel
// 写入钩子在孪生文件 reminder_coordinator_snapshot_test.dart。
//
// 全部分册**不碰数据库**：任务侧走 `TaskReminderSource` 注入的内存表，通知侧走假
// `NotificationSink`（共用夹具在 reminder_coordinator_harness.dart），所以不需要
// `tester.runAsync`。
//
// 反证点（每条都对应一处真实实现行为，改坏就会红）：防抖只排一次、总开关关掉
// 要 cancelAll + 清快照、设置变更要触发重排、dispose 后要静默。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/notify/chaoxing_snapshot.dart';
import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/notify/reminder_coordinator.dart';

import 'reminder_coordinator_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReminderHarness h;

  setUp(() async {
    h = await ReminderHarness.create();
  });

  group('防抖与触发源', () {
    test('连续 5 次变更只重排一次（批量改地点不烧闹钟）', () async {
      final ReminderCoordinator c = h.build();
      c.start();
      c.notifyChanged();
      c.notifyChanged();
      c.notifyChanged();
      c.notifyChanged();
      await h.settle();
      expect(h.sink.calls.where((String x) => x == 'cancelAll').length, 1,
          reason: '防抖窗口内 5 次变更必须只排一轮');
      expect(h.sink.lastRound, 2, reason: '默认设置：提前 30 分钟 + 到期时刻');
    });

    test('NotifySettingsStore 的变更自动触发重排（设置页不需要认识协调器）', () async {
      final ReminderCoordinator c = h.build();
      c.start();
      await h.settle();
      final int before = h.sink.lastRound;
      await h.store.apply((NotifySettings s) => s.taskDueEnabled = false);
      await h.settle();
      expect(h.sink.lastRound, lessThan(before),
          reason: '关掉到期提醒后只剩提前那一条');
      expect(h.sink.lastRound, 1);
    });

    test('任务侧 Listenable（TaskPaneModel 的替身）触发重排并读到新数据', () async {
      final ReminderListenerProbe pane = ReminderListenerProbe();
      final ReminderCoordinator c = h.build(sources: <Listenable>[pane]);
      c.start();
      await h.settle();
      expect(h.sink.scheduled.map((ScheduledReminder r) => r.reminder.body),
          <String>['任务t1', '任务t1']);
      h.table = <Task>[
        makeReminderTask('t2', due: DateTime.now().add(const Duration(minutes: 40))),
      ];
      pane.poke();
      await h.settle();
      expect(h.sink.scheduled.map((ScheduledReminder r) => r.reminder.body),
          <String>['任务t2', '任务t2'],
          reason: '重排必须重新读任务表，不能拿上一次的快照');
      pane.dispose();
    });

    test('start() 幂等：重复调用不会挂两份监听', () async {
      final ReminderCoordinator c = h.build();
      c.start();
      c.start();
      c.start();
      await h.settle();
      expect(h.sink.calls.where((String x) => x == 'cancelAll').length, 1);
    });
  });

  group('总开关', () {
    test('关掉 → cancelAll + 清快照 + 一条都不排', () async {
      await h.snapshot.writeSnapshot(<ChaoxingSnapshotItem>[
        ChaoxingSnapshotItem(
            key: 'k1',
            courseName: '课程甲',
            title: '作业1',
            dueAt: DateTime.now().add(const Duration(days: 1))),
      ]);
      final ReminderCoordinator c = h.build();
      c.start();
      await h.settle();
      // 任务 2 条（提前 30 + 到期）+ 学习通 2 条（提前 120 + 30，截止在 +1 天）。
      expect(h.sink.lastRound, 4);

      await h.store.setEnabled(false);
      await h.settle();
      expect(h.prefs.getString(kChaoxingSnapshotKey), isNull,
          reason: 'C4 §3：总开关关闭要清掉学习通提醒快照');
      expect(h.sink.lastRound, 0, reason: 'cancelAll 之后不应再有任何排程');
    });

    test('关着时再次变更不会重复清快照（清过一次就够）', () async {
      final ReminderCoordinator c = h.build();
      c.start();
      await h.store.setEnabled(false);
      await h.settle();
      // 关掉之后又落了一份快照（例如学习通在别处被刷新）：第二次重排不该再抹它，
      // 否则「清一次」的语义会变成「一直和写入方抢盘」。
      await h.snapshot.writeSnapshot(<ChaoxingSnapshotItem>[
        const ChaoxingSnapshotItem(
            key: 'k1', courseName: '课程甲', title: '作业1', dueAt: null),
      ]);
      final int before = h.sink.calls.length;
      h.coordinator.notifyChanged();
      await h.settle();
      expect(h.sink.calls.length, greaterThan(before), reason: '仍然会重排（只是排 0 条）');
      expect(h.prefs.getString(kChaoxingSnapshotKey), isNotNull,
          reason: '已清过一次就不该反复清盘');
    });

    test('重新打开后又能排提醒', () async {
      final ReminderCoordinator c = h.build();
      c.start();
      await h.store.setEnabled(false);
      await h.settle();
      expect(h.sink.lastRound, 0);
      await h.store.setEnabled(true);
      await h.settle();
      expect(h.sink.lastRound, 2);
    });
  });

  group('失败要静默', () {
    test('任务源抛异常不外抛（提醒是增强功能，不能带崩任务列表）', () async {
      final ReminderCoordinator c =
          h.build(source: () async => throw StateError('库被打开了两次'));
      expect(await c.rescheduleNow(), 0, reason: '异常吞掉后返回上一次的值');
      c.start();
      await h.settle();
    });

    test('dispose 之后变更源再 notify 也不重排，且监听真的摘干净了', () async {
      final ReminderListenerProbe pane = ReminderListenerProbe();
      final ReminderCoordinator c = h.build(sources: <Listenable>[pane]);
      c.start();
      await h.settle();
      expect(pane.listened, isTrue, reason: '没订阅上，这条测试就什么都没测');
      final int before = h.sink.calls.length;
      await c.dispose();
      expect(pane.listened, isFalse, reason: '监听没摘干净：协调器比模型活得久就是泄漏');
      pane.poke();
      await h.store.setEnabled(false);
      await h.settle();
      expect(h.sink.calls.length, before, reason: 'dispose 后不该再排任何一轮');
      pane.dispose();
    });
  });
}

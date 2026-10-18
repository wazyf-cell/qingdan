// 提醒协调器单测·快照部分（M6-C2 §6 接线 + C4 §2 快照写入时机）。
// 自 reminder_coordinator_test.dart 拆出：本文件管「快照筛选（C4 §2）」与
// 「ChaoxingModel 的快照钩子（C4 §2 写入时机）」；重排触发线（防抖 / 总开关 /
// 静默失败）在孪生文件 reminder_coordinator_reschedule_test.dart。
//
// 全部分册**不碰数据库**（共用夹具在 reminder_coordinator_harness.dart），
// 所以不需要 `tester.runAsync`。
//
// 反证点：快照筛选的五种排除、学习通项与任务项同批排程、refresh 成功后写快照、
// 写快照失败不许把成功抓取说成失败、抓取失败不动盘。
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/chaoxing/chaoxing_prefs.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/reminder_coordinator.dart';
import 'package:qingdan/notify/reminder_plan.dart';
import 'package:qingdan/sync/secure_store.dart';

import 'reminder_coordinator_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReminderHarness h;

  setUp(() async {
    h = await ReminderHarness.create();
  });

  group('快照筛选（C4 §2）', () {
    test('排除已隐藏 / 已完成 / 已结束 / 无截止 / 截止已过', () {
      final DateTime now = DateTime(2026, 10, 18, 12);
      final DateTime future = now.add(const Duration(hours: 3));
      final List<ChaoxingSnapshotItem> kept = chaoxingSnapshotOf(
        <ChaoxingTask>[
          makeReminderChaoxingTask('keep', dueAt: future, status: null),
          makeReminderChaoxingTask('done', dueAt: future, done: true, status: null),
          makeReminderChaoxingTask('ended', dueAt: future, ongoing: false, status: null),
          makeReminderChaoxingTask('nodue', status: null),
          makeReminderChaoxingTask('past', dueAt: now.subtract(const Duration(minutes: 1)), status: null),
          makeReminderChaoxingTask('hidden', dueAt: future, status: null),
        ],
        <String>{'c1|hidden'},
        now,
      );
      expect(kept.map((ChaoxingSnapshotItem i) => i.key), <String>['c1|keep']);
      expect(kept.single.dueAt, future);
    });

    test('学习通项与任务项一起进同一份排程（id 连续、payload 正确）', () async {
      await h.snapshot.writeSnapshot(<ChaoxingSnapshotItem>[
        ChaoxingSnapshotItem(
            key: 'c1|a',
            courseName: '课程甲',
            title: '作业1',
            dueAt: DateTime.now().add(const Duration(minutes: 90))),
      ]);
      final ReminderCoordinator c = h.build();
      await c.rescheduleNow();
      expect(h.sink.lastRound, 3, reason: '任务 2 条 + 学习通第一档 1 条');
      expect(h.sink.scheduled.map((ScheduledReminder s) => s.id), <int>[0, 1, 2]);
      final List<Reminder> cx = h.sink.scheduled
          .map((ScheduledReminder s) => s.reminder)
          .where((Reminder r) => r.kind == kChaoxingReminderKind)
          .toList();
      expect(cx.single.payload, kChaoxingPayload);
      expect(cx.single.body, '课程甲 · 作业1');
      expect(c.lastScheduled, 3);
    });
  });

  group('ChaoxingModel 的快照钩子（C4 §2 写入时机）', () {
    late ChaoxingModel model;
    late ReminderChaoxingClient client;

    Future<void> makeModel({bool hookThrows = false}) async {
      client = ReminderChaoxingClient();
      model = ChaoxingModel(
        secure: InMemorySecureStore(<String, String>{
          ChaoxingModel.kCookieKey: 'placeholder-not-a-credential'
        }),
        prefs: ChaoxingPrefs(prefs: h.prefs),
        clock: () => DateTime(2026, 10, 18, 12),
        clientFactory: (String _) => client,
      );
      await model.restore();
      model.onReminderSnapshot = (List<ChaoxingTask> tasks, Set<String> hidden, DateTime now) async {
        if (hookThrows) throw StateError('prefs 写不进去');
        await h.snapshot.writeSnapshot(chaoxingSnapshotOf(tasks, hidden, now));
      };
    }

    test('refresh 成功后落快照，只含可排的项（隐藏的那条不落盘）', () async {
      await makeModel();
      final DateTime future = DateTime(2026, 10, 18, 12).add(const Duration(hours: 5));
      // 先隐藏 b：钩子必须把**当前** settings.hidden 传给筛选函数，传错就落进快照。
      await model.hide(makeReminderChaoxingTask('b', dueAt: future));
      expect(model.settings.hidden, contains('c1|b'));
      client.tasks = <ChaoxingTask>[
        makeReminderChaoxingTask('a', dueAt: future),
        makeReminderChaoxingTask('b', dueAt: future),
        makeReminderChaoxingTask('c', dueAt: future, done: true),
      ];
      await model.refresh();
      final List<ChaoxingSnapshotItem> read = await h.snapshot.readSnapshot();
      expect(read.map((ChaoxingSnapshotItem i) => i.key), <String>['c1|a']);
      expect(model.error, isNull);
      model.dispose();
    });

    test('快照写失败不许把一次成功的抓取标成失败', () async {
      await makeModel(hookThrows: true);
      client.tasks = <ChaoxingTask>[
        makeReminderChaoxingTask('a', dueAt: DateTime(2026, 10, 18, 17))
      ];
      await model.refresh();
      expect(model.error, isNull, reason: '写盘失败被吞在钩子里，不进 refresh 的 catch');
      expect(model.loggedIn, isTrue);
      expect(model.fetchedAt, isNotNull);
      model.dispose();
    });

    test('抓取失败时不写快照（没有可信的新数据，不能覆盖上一次）', () async {
      await makeModel();
      await h.snapshot.writeSnapshot(<ChaoxingSnapshotItem>[
        ChaoxingSnapshotItem(
            key: 'old',
            courseName: '课程甲',
            title: '上一次的作业',
            dueAt: DateTime(2026, 10, 18, 20)),
      ]);
      client.fail = true;
      await model.refresh();
      expect(model.error, isNotNull);
      final List<ChaoxingSnapshotItem> read = await h.snapshot.readSnapshot();
      expect(read.map((ChaoxingSnapshotItem i) => i.key), <String>['old'],
          reason: '写快照在 refresh 的成功路径末尾，失败时不该动盘');
      model.dispose();
    });
  });
}

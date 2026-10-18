// 提醒计划单测·两个域各自的生成规则（M6-C2）。自 reminder_plan_test.dart 拆出：
// 本文件管「清单到期提醒」与「学习通截止提醒」两个 group（开关组合、过期与空
// dueDate 不排、四种排除、内容与 payload）；免打扰顺延与升序/200 条上限在孪生
// 文件 reminder_plan_quiet_and_limit_test.dart。
//
// 规划器是纯函数，夹具（配置实现、数据构造、锚定时刻）在 reminder_plan_fixture.dart。
// 本文件不许 import shared_preferences：「规划器不碰 prefs」这条边界要靠 import
// 列表本身守住（沿用拆分前的约定）。
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/notify/reminder_plan.dart';

import 'reminder_plan_fixture.dart';

void main() {
  group('清单到期提醒', () {
    test('提前 30 分钟与到期时刻都开：due=now+40min 排出两条', () {
      final List<Reminder> got = planTaskReminders(
          [makePlanTask('t1', due: inPlanMinutes(40))], kPlanNow, TestReminderConfig());
      expect(got.map((Reminder r) => r.at),
          [inPlanMinutes(10), inPlanMinutes(40)], // 提前那条在前
          reason: '两条的时刻与先后');
      expect(got.map((Reminder r) => r.subtext), ['30 分钟后到期', '现在到期']);
    });

    test('只开「提前提醒」：只剩提前那条', () {
      final List<Reminder> got = planTaskReminders(
          [makePlanTask('t1', due: inPlanMinutes(40))],
          kPlanNow,
          TestReminderConfig(taskDueEnabled: false));
      expect(got.length, 1);
      expect(got.single.at, inPlanMinutes(10));
    });

    test('只开「到期时刻提醒」：只剩到期那条', () {
      final List<Reminder> got = planTaskReminders(
          [makePlanTask('t1', due: inPlanMinutes(40))],
          kPlanNow,
          TestReminderConfig(taskLeadEnabled: false));
      expect(got.length, 1);
      expect(got.single.at, inPlanMinutes(40));
      expect(got.single.subtext, '现在到期');
    });

    test('两个开关都关：0 条', () {
      final List<Reminder> got = planTaskReminders(
          [makePlanTask('t1', due: inPlanMinutes(40))],
          kPlanNow,
          TestReminderConfig(taskLeadEnabled: false, taskDueEnabled: false));
      expect(got, isEmpty);
    });

    test('提前量可调：改成 60 分钟，提前那条跟着挪', () {
      final List<Reminder> got = planTaskReminders(
          [makePlanTask('t1', due: inPlanMinutes(90))],
          kPlanNow,
          TestReminderConfig(taskLeadMinutes: 60));
      expect(got.first.at, inPlanMinutes(30));
    });

    test('dueDate 已过去（now-1h）：0 条，不排历史通知', () {
      final List<Reminder> got = planTaskReminders(
          [makePlanTask('t1', due: kPlanNow.subtract(const Duration(hours: 1)))],
          kPlanNow,
          TestReminderConfig());
      expect(got, isEmpty);
    });

    test('dueDate 为 null：0 条', () {
      expect(
          planTaskReminders([makePlanTask('t1')], kPlanNow, TestReminderConfig()),
          isEmpty);
    });

    test('已完成 / 已进回收站：不提醒（这正是这两个事件要触发重排的原因）', () {
      expect(
          planTaskReminders([makePlanTask('t1', due: inPlanMinutes(40), done: true)],
              kPlanNow, TestReminderConfig()),
          isEmpty);
      expect(
          planTaskReminders([makePlanTask('t2', due: inPlanMinutes(40), trashed: true)],
              kPlanNow, TestReminderConfig()),
          isEmpty);
    });

    test('提醒总开关关掉：两个域都 0 条', () {
      const TestReminderConfig off = TestReminderConfig(enabled: false);
      expect(
          planTaskReminders([makePlanTask('t1', due: inPlanMinutes(40))], kPlanNow, off),
          isEmpty);
      expect(
          planChaoxingReminders(
              [makePlanChaoxing('c1', due: inPlanMinutes(40))], kPlanNow, off),
          isEmpty);
    });

    test('内容：kind / sourceKey / 标题 / 正文 / payload', () {
      final Reminder r = planTaskReminders(
              [makePlanTask('tid-9', due: inPlanMinutes(40))],
              kPlanNow,
              TestReminderConfig(taskLeadEnabled: false))
          .single;
      expect(r.kind, kTaskReminderKind);
      expect(r.sourceKey, 'tid-9');
      expect(r.title, '待办提醒');
      expect(r.body, '任务tid-9');
      expect(r.payload, 'tid-9', reason: '点通知要落到这条任务的详情页');
    });
  });

  group('学习通截止提醒', () {
    test('两档 120 / 30 分钟：两条，升序', () {
      final List<Reminder> got = planChaoxingReminders(
          [makePlanChaoxing('c1', due: inPlanMinutes(3 * 60))],
          kPlanNow,
          const TestReminderConfig(
              chaoxingLead1Minutes: 120, chaoxingLead2Minutes: 30));
      expect(got.map((Reminder r) => r.at),
          [inPlanMinutes(60), inPlanMinutes(150)]);
      expect(got.map((Reminder r) => r.subtext), ['10-18 13:00', '10-18 13:00']);
    });

    test('只开第一档 → 1 条；两档都关 → 0 条（不排截止那一刻）', () {
      final ChaoxingSnapshotItem item =
          makePlanChaoxing('c1', due: inPlanMinutes(3 * 60));
      expect(
          planChaoxingReminders(
                  [item], kPlanNow, TestReminderConfig(chaoxingLead2Enabled: false))
              .map((Reminder r) => r.at),
          [inPlanMinutes(60)]);
      expect(
          planChaoxingReminders(
              [item],
              kPlanNow,
              TestReminderConfig(
                  chaoxingLead1Enabled: false, chaoxingLead2Enabled: false)),
          isEmpty,
          reason: '学习通只有两档提前量，截止时刻本身不排通知');
    });

    test('四种排除：已隐藏 / 服务端已完成 / 已结束 / 无 dueAt', () {
      final DateTime due = inPlanMinutes(3 * 60);
      expect(
          planChaoxingReminders(
              [makePlanChaoxing('c1', due: due, hidden: true)], kPlanNow, TestReminderConfig()),
          isEmpty,
          reason: '已隐藏的列表项不该来打扰');
      expect(
          planChaoxingReminders([makePlanChaoxing('c1', due: due, serverDone: true)],
              kPlanNow, TestReminderConfig()),
          isEmpty);
      expect(
          planChaoxingReminders([makePlanChaoxing('c1', due: due, ongoing: false)],
              kPlanNow, TestReminderConfig()),
          isEmpty);
      expect(
          planChaoxingReminders([makePlanChaoxing('c1')], kPlanNow, TestReminderConfig()),
          isEmpty);
    });

    test('已过期（dueAt < now）：0 条', () {
      expect(
          planChaoxingReminders(
              [makePlanChaoxing('c1',
                  due: kPlanNow.subtract(const Duration(minutes: 5)))],
              kPlanNow,
              TestReminderConfig()),
          isEmpty);
    });

    test('内容：课程 · 标题、子文本是截止时间、payload 固定', () {
      final Reminder r = planChaoxingReminders([
        makePlanChaoxing('c1',
            due: inPlanMinutes(3 * 60), course: '电子工艺', title: '实验报告')
      ], kPlanNow, TestReminderConfig(chaoxingLead2Enabled: false)).single;
      expect(r.kind, kChaoxingReminderKind);
      expect(r.sourceKey, 'c1');
      expect(r.title, '学习通截止提醒');
      expect(r.body, '电子工艺 · 实验报告');
      expect(r.subtext, '10-18 13:00');
      expect(r.payload, kChaoxingPayload);
    });
  });
}

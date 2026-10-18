// 提醒计划单测·全局排程规则（M6-C2）。自 reminder_plan_test.dart 拆出：本文件管
// 「免打扰顺延」（含跨午夜两种落点、端点开闭、整条链路）与「升序与 200 条上限」
// 两个 group；两个域各自的生成规则在孪生文件
// reminder_plan_reminder_kinds_test.dart。
//
// 规划器是纯函数，夹具在 reminder_plan_fixture.dart。本文件同样不许 import
// shared_preferences（沿用拆分前约定）。
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/notify/reminder_plan.dart';

import 'reminder_plan_fixture.dart';

void main() {
  group('免打扰顺延', () {
    test('23:30 落在 23:00–07:00 → 次日 07:00（不丢弃）', () {
      expect(applyQuietHours(DateTime(2026, 10, 18, 23, 30), quietCrossMidnight),
          DateTime(2026, 10, 19, 7, 0));
    });

    test('凌晨 02:00 落在同一跨午夜区间 → 当日 07:00', () {
      expect(applyQuietHours(DateTime(2026, 10, 19, 2, 0), quietCrossMidnight),
          DateTime(2026, 10, 19, 7, 0));
    });

    test('不跨午夜（01:00–06:00）：02:30 → 当日 06:00', () {
      expect(applyQuietHours(DateTime(2026, 10, 19, 2, 30), quietSameDay),
          DateTime(2026, 10, 19, 6, 0));
    });

    test('区间外的时刻原样不动', () {
      expect(applyQuietHours(DateTime(2026, 10, 19, 10, 0), quietCrossMidnight),
          DateTime(2026, 10, 19, 10, 0));
      expect(applyQuietHours(DateTime(2026, 10, 19, 12, 0), quietSameDay),
          DateTime(2026, 10, 19, 12, 0));
    });

    test('右端点开：正好 07:00 / 正好 06:00 都不算落在区间内', () {
      expect(applyQuietHours(DateTime(2026, 10, 19, 7, 0), quietCrossMidnight),
          DateTime(2026, 10, 19, 7, 0));
      expect(applyQuietHours(DateTime(2026, 10, 19, 6, 0), quietSameDay),
          DateTime(2026, 10, 19, 6, 0),
          reason: '不跨午夜那一支的右端点也必须是开区间，否则 06:00 的提醒被白推到 18:00');
    });

    test('左端点闭：正好 23:00 与正好 01:00 都要顺延', () {
      expect(applyQuietHours(DateTime(2026, 10, 18, 23, 0), quietCrossMidnight),
          DateTime(2026, 10, 19, 7, 0));
      expect(applyQuietHours(DateTime(2026, 10, 19, 1, 0), quietSameDay),
          DateTime(2026, 10, 19, 6, 0));
    });

    test('免打扰关掉：原样返回', () {
      final DateTime at = DateTime(2026, 10, 18, 23, 30);
      expect(applyQuietHours(at, const TestReminderConfig()), at);
    });

    test('起止相等 = 空区间 → 不顺延（否则所有提醒挤到同一时刻）', () {
      expect(
          applyQuietHours(
              DateTime(2026, 10, 18, 23, 30),
              const TestReminderConfig(
                  quietHoursEnabled: true, quietStart: 1380, quietEnd: 1380)),
          DateTime(2026, 10, 18, 23, 30));
    });

    test('整条链路：到期 23:40 的两条都顺延到次日 07:00', () {
      final List<Reminder> got = planTaskReminders(
          [
            makePlanTask('t1',
                due: DateTime(2026, 10, 18, 23, 40)) // now=10:00，都在未来
          ],
          DateTime(2026, 10, 18, 10, 0),
          quietCrossMidnight);
      expect(got.length, 2, reason: '提前那条(23:10)与到期那条(23:40)都留着，不丢弃');
      expect(got.every((Reminder r) => r.at == DateTime(2026, 10, 19, 7, 0)), isTrue);
      // 顺延后已晚于到期时刻，文案只能说「现在到期」。
      expect(got.map((Reminder r) => r.subtext), ['现在到期', '现在到期']);
    });
  });

  group('升序与 200 条上限', () {
    test('350 条任务只留最早 200 条，且严格按 at 升序', () {
      final List<Task> many = <Task>[
        for (int i = 0; i < 350; i++)
          makePlanTask('t${i.toString().padLeft(3, '0')}', due: inPlanMinutes(i + 1))
      ];
      final List<Reminder> got = planTaskReminders(many, kPlanNow,
          TestReminderConfig(taskDueEnabled: false)); // 每任务只 1 条，便于精确数
      expect(got.length, kMaxScheduledReminders);
      expect(got.first.at, kPlanNow, reason: '第 29 号任务的提前量正好落在 now（不滤）');
      expect(got.last.at, inPlanMinutes(199));
      for (int i = 1; i < got.length; i++) {
        expect(got[i].at.isAfter(got[i - 1].at), isTrue,
            reason: '第 $i 条没有晚于前一条：升序被破坏');
      }
    });

    test('planReminders 合并两个域并全局升序', () {
      final List<Reminder> got = planReminders(
        tasks: [
          makePlanTask('t1', due: inPlanMinutes(150)),
          makePlanTask('t2', due: inPlanMinutes(20))
        ],
        items: [makePlanChaoxing('c1', due: inPlanMinutes(80))],
        now: kPlanNow,
        cfg: TestReminderConfig(taskLeadEnabled: false, chaoxingLead1Enabled: false),
      );
      expect(got.map((Reminder r) => r.at),
          [inPlanMinutes(20), inPlanMinutes(50), inPlanMinutes(150)]);
      expect(got.map((Reminder r) => r.kind),
          [kTaskReminderKind, kChaoxingReminderKind, kTaskReminderKind]);
    });

    test('planReminders 的上限也是 200 条（跨两个域）', () {
      final List<Reminder> got = planReminders(
        tasks: <Task>[
          for (int i = 0; i < 150; i++)
            makePlanTask('t$i', due: inPlanMinutes(2 * i + 1))
        ],
        items: <ChaoxingSnapshotItem>[
          for (int i = 0; i < 150; i++) makePlanChaoxing('c$i', due: inPlanMinutes(2 * i + 2))
        ],
        now: kPlanNow,
        cfg: TestReminderConfig(
            taskDueEnabled: false,
            chaoxingLead2Enabled: false,
            chaoxingLead1Minutes: 1),
      );
      expect(got.length, kMaxScheduledReminders);
      expect(got.map((Reminder r) => r.kind).toSet(),
          <String>{kTaskReminderKind, kChaoxingReminderKind});
    });

    test('同一时刻按来源键定序：截断结果可复现', () {
      final List<Reminder> got = planReminders(
        tasks: [makePlanTask('zz', due: inPlanMinutes(30))],
        items: [makePlanChaoxing('aa', due: inPlanMinutes(30))],
        now: kPlanNow,
        cfg: TestReminderConfig(
            taskLeadEnabled: false,
            chaoxingLead2Enabled: false,
            chaoxingLead1Minutes: 0),
      );
      expect(got.length, 2);
      expect(got.map((Reminder r) => r.sourceKey), ['aa', 'zz']);
    });
  });
}

// 提醒计划单测（M6-C2）。规划器是纯函数，这里覆盖它全部定死语义：
// 两个开关的四种组合、过期与空 dueDate 不排、免打扰顺延（含跨午夜两种落点）、
// 学习通四种排除、升序 + 200 条截断。
//
// 测试用 _Cfg 而不是 NotifySettings：本文件不许 import shared_preferences，
// 「规划器不碰 prefs」这条边界要靠 import 列表本身守住。
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/notify/reminder_plan.dart';

/// 规划器要的 11 项设置。默认值与总纲 §五 一致；免打扰默认**关**，
/// 这样每条用例都能单独说明「顺延」是不是真的发生了。
class _Cfg implements ReminderConfig {
  const _Cfg({
    this.enabled = true,
    this.taskLeadEnabled = true,
    this.taskDueEnabled = true,
    this.chaoxingLead1Enabled = true,
    this.chaoxingLead2Enabled = true,
    this.quietHoursEnabled = false,
    this.taskLeadMinutes = 30,
    this.chaoxingLead1Minutes = 120,
    this.chaoxingLead2Minutes = 30,
    this.quietStart = 1380,
    this.quietEnd = 420,
  });

  @override
  final bool enabled;
  @override
  final bool taskLeadEnabled;
  @override
  final bool taskDueEnabled;
  @override
  final bool chaoxingLead1Enabled;
  @override
  final bool chaoxingLead2Enabled;
  @override
  final bool quietHoursEnabled;
  @override
  final int taskLeadMinutes;
  @override
  final int chaoxingLead1Minutes;
  @override
  final int chaoxingLead2Minutes;
  @override
  final int quietStart;
  @override
  final int quietEnd;
}

/// 免打扰 23:00–07:00（跨午夜）。
const _Cfg _quietCross =
    _Cfg(quietHoursEnabled: true, quietStart: 1380, quietEnd: 420);

/// 免打扰 01:00–06:00（不跨午夜）。
const _Cfg _quietSameDay =
    _Cfg(quietHoursEnabled: true, quietStart: 60, quietEnd: 360);

Task _task(String id, {DateTime? due, bool done = false, bool trashed = false}) =>
    Task(
        id: id,
        title: '任务$id',
        dueDate: due,
        completed: done,
        deleted: trashed);

ChaoxingSnapshotItem _cx(String key,
    {DateTime? due,
    bool hidden = false,
    bool serverDone = false,
    bool ongoing = true,
    String course = '数据结构',
    String title = '第3次作业'}) =>
    ChaoxingSnapshotItem(
        key: key,
        courseName: course,
        title: title,
        dueAt: due,
        hidden: hidden,
        serverDone: serverDone,
        ongoing: ongoing);

void main() {
  final DateTime now = DateTime(2026, 10, 18, 10, 0); // 本地：周日上午 10:00
  DateTime inMinutes(int m) => now.add(Duration(minutes: m));

  group('清单到期提醒', () {
    test('提前 30 分钟与到期时刻都开：due=now+40min 排出两条', () {
      final List<Reminder> got =
          planTaskReminders([_task('t1', due: inMinutes(40))], now, _Cfg());
      expect(got.map((Reminder r) => r.at),
          [inMinutes(10), inMinutes(40)], // 提前那条在前
          reason: '两条的时刻与先后');
      expect(got.map((Reminder r) => r.subtext), ['30 分钟后到期', '现在到期']);
    });

    test('只开「提前提醒」：只剩提前那条', () {
      final List<Reminder> got = planTaskReminders(
          [_task('t1', due: inMinutes(40))], now, _Cfg(taskDueEnabled: false));
      expect(got.length, 1);
      expect(got.single.at, inMinutes(10));
    });

    test('只开「到期时刻提醒」：只剩到期那条', () {
      final List<Reminder> got = planTaskReminders(
          [_task('t1', due: inMinutes(40))], now, _Cfg(taskLeadEnabled: false));
      expect(got.length, 1);
      expect(got.single.at, inMinutes(40));
      expect(got.single.subtext, '现在到期');
    });

    test('两个开关都关：0 条', () {
      final List<Reminder> got = planTaskReminders([_task('t1', due: inMinutes(40))],
          now, _Cfg(taskLeadEnabled: false, taskDueEnabled: false));
      expect(got, isEmpty);
    });

    test('提前量可调：改成 60 分钟，提前那条跟着挪', () {
      final List<Reminder> got = planTaskReminders(
          [_task('t1', due: inMinutes(90))], now, _Cfg(taskLeadMinutes: 60));
      expect(got.first.at, inMinutes(30));
    });

    test('dueDate 已过去（now-1h）：0 条，不排历史通知', () {
      final List<Reminder> got = planTaskReminders(
          [_task('t1', due: now.subtract(const Duration(hours: 1)))], now, _Cfg());
      expect(got, isEmpty);
    });

    test('dueDate 为 null：0 条', () {
      expect(planTaskReminders([_task('t1')], now, _Cfg()), isEmpty);
    });

    test('已完成 / 已进回收站：不提醒（这正是这两个事件要触发重排的原因）', () {
      expect(
          planTaskReminders([_task('t1', due: inMinutes(40), done: true)], now, _Cfg()),
          isEmpty);
      expect(
          planTaskReminders(
              [_task('t2', due: inMinutes(40), trashed: true)], now, _Cfg()),
          isEmpty);
    });

    test('提醒总开关关掉：两个域都 0 条', () {
      const _Cfg off = _Cfg(enabled: false);
      expect(
          planTaskReminders([_task('t1', due: inMinutes(40))], now, off), isEmpty);
      expect(
          planChaoxingReminders([_cx('c1', due: inMinutes(40))], now, off), isEmpty);
    });

    test('内容：kind / sourceKey / 标题 / 正文 / payload', () {
      final Reminder r = planTaskReminders(
              [_task('tid-9', due: inMinutes(40))], now, _Cfg(taskLeadEnabled: false))
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
          [_cx('c1', due: inMinutes(3 * 60))],
          now,
          const _Cfg(chaoxingLead1Minutes: 120, chaoxingLead2Minutes: 30));
      expect(got.map((Reminder r) => r.at), [inMinutes(60), inMinutes(150)]);
      expect(got.map((Reminder r) => r.subtext), ['10-18 13:00', '10-18 13:00']);
    });

    test('只开第一档 → 1 条；两档都关 → 0 条（不排截止那一刻）', () {
      final ChaoxingSnapshotItem item = _cx('c1', due: inMinutes(3 * 60));
      expect(
          planChaoxingReminders([item], now, _Cfg(chaoxingLead2Enabled: false))
              .map((Reminder r) => r.at),
          [inMinutes(60)]);
      expect(
          planChaoxingReminders(
              [item], now, _Cfg(chaoxingLead1Enabled: false, chaoxingLead2Enabled: false)),
          isEmpty,
          reason: '学习通只有两档提前量，截止时刻本身不排通知');
    });

    test('四种排除：已隐藏 / 服务端已完成 / 已结束 / 无 dueAt', () {
      final DateTime due = inMinutes(3 * 60);
      expect(planChaoxingReminders([_cx('c1', due: due, hidden: true)], now, _Cfg()),
          isEmpty,
          reason: '已隐藏的列表项不该来打扰');
      expect(
          planChaoxingReminders([_cx('c1', due: due, serverDone: true)], now, _Cfg()),
          isEmpty);
      expect(
          planChaoxingReminders([_cx('c1', due: due, ongoing: false)], now, _Cfg()),
          isEmpty);
      expect(planChaoxingReminders([_cx('c1')], now, _Cfg()), isEmpty);
    });

    test('已过期（dueAt < now）：0 条', () {
      expect(
          planChaoxingReminders(
              [_cx('c1', due: now.subtract(const Duration(minutes: 5)))], now, _Cfg()),
          isEmpty);
    });

    test('内容：课程 · 标题、子文本是截止时间、payload 固定', () {
      final Reminder r = planChaoxingReminders([
        _cx('c1', due: inMinutes(3 * 60), course: '电子工艺', title: '实验报告')
      ], now, _Cfg(chaoxingLead2Enabled: false)).single;
      expect(r.kind, kChaoxingReminderKind);
      expect(r.sourceKey, 'c1');
      expect(r.title, '学习通截止提醒');
      expect(r.body, '电子工艺 · 实验报告');
      expect(r.subtext, '10-18 13:00');
      expect(r.payload, kChaoxingPayload);
    });
  });

  group('免打扰顺延', () {
    test('23:30 落在 23:00–07:00 → 次日 07:00（不丢弃）', () {
      expect(applyQuietHours(DateTime(2026, 10, 18, 23, 30), _quietCross),
          DateTime(2026, 10, 19, 7, 0));
    });

    test('凌晨 02:00 落在同一跨午夜区间 → 当日 07:00', () {
      expect(applyQuietHours(DateTime(2026, 10, 19, 2, 0), _quietCross),
          DateTime(2026, 10, 19, 7, 0));
    });

    test('不跨午夜（01:00–06:00）：02:30 → 当日 06:00', () {
      expect(applyQuietHours(DateTime(2026, 10, 19, 2, 30), _quietSameDay),
          DateTime(2026, 10, 19, 6, 0));
    });

    test('区间外的时刻原样不动', () {
      expect(applyQuietHours(DateTime(2026, 10, 19, 10, 0), _quietCross),
          DateTime(2026, 10, 19, 10, 0));
      expect(applyQuietHours(DateTime(2026, 10, 19, 12, 0), _quietSameDay),
          DateTime(2026, 10, 19, 12, 0));
    });

    test('右端点开：正好 07:00 / 正好 06:00 都不算落在区间内', () {
      expect(applyQuietHours(DateTime(2026, 10, 19, 7, 0), _quietCross),
          DateTime(2026, 10, 19, 7, 0));
      expect(applyQuietHours(DateTime(2026, 10, 19, 6, 0), _quietSameDay),
          DateTime(2026, 10, 19, 6, 0),
          reason: '不跨午夜那一支的右端点也必须是开区间，否则 06:00 的提醒被白推到 18:00');
    });

    test('左端点闭：正好 23:00 与正好 01:00 都要顺延', () {
      expect(applyQuietHours(DateTime(2026, 10, 18, 23, 0), _quietCross),
          DateTime(2026, 10, 19, 7, 0));
      expect(applyQuietHours(DateTime(2026, 10, 19, 1, 0), _quietSameDay),
          DateTime(2026, 10, 19, 6, 0));
    });

    test('免打扰关掉：原样返回', () {
      final DateTime at = DateTime(2026, 10, 18, 23, 30);
      expect(applyQuietHours(at, const _Cfg()), at);
    });

    test('起止相等 = 空区间 → 不顺延（否则所有提醒挤到同一时刻）', () {
      expect(
          applyQuietHours(
              DateTime(2026, 10, 18, 23, 30),
              const _Cfg(quietHoursEnabled: true, quietStart: 1380, quietEnd: 1380)),
          DateTime(2026, 10, 18, 23, 30));
    });

    test('整条链路：到期 23:40 的两条都顺延到次日 07:00', () {
      final List<Reminder> got = planTaskReminders(
          [
            _task('t1',
                due: DateTime(2026, 10, 18, 23, 40)) // now=10:00，都在未来
          ],
          DateTime(2026, 10, 18, 10, 0),
          _quietCross);
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
          _task('t${i.toString().padLeft(3, '0')}', due: inMinutes(i + 1))
      ];
      final List<Reminder> got = planTaskReminders(
          many, now, _Cfg(taskDueEnabled: false)); // 每任务只 1 条，便于精确数
      expect(got.length, kMaxScheduledReminders);
      expect(got.first.at, now, reason: '第 29 号任务的提前量正好落在 now（不滤）');
      expect(got.last.at, inMinutes(199));
      for (int i = 1; i < got.length; i++) {
        expect(got[i].at.isAfter(got[i - 1].at), isTrue,
            reason: '第 $i 条没有晚于前一条：升序被破坏');
      }
    });

    test('planReminders 合并两个域并全局升序', () {
      final List<Reminder> got = planReminders(
        tasks: [_task('t1', due: inMinutes(150)), _task('t2', due: inMinutes(20))],
        items: [_cx('c1', due: inMinutes(80))],
        now: now,
        cfg: _Cfg(taskLeadEnabled: false, chaoxingLead1Enabled: false),
      );
      expect(got.map((Reminder r) => r.at),
          [inMinutes(20), inMinutes(50), inMinutes(150)]);
      expect(got.map((Reminder r) => r.kind),
          [kTaskReminderKind, kChaoxingReminderKind, kTaskReminderKind]);
    });

    test('planReminders 的上限也是 200 条（跨两个域）', () {
      final List<Reminder> got = planReminders(
        tasks: <Task>[
          for (int i = 0; i < 150; i++)
            _task('t$i', due: inMinutes(2 * i + 1))
        ],
        items: <ChaoxingSnapshotItem>[
          for (int i = 0; i < 150; i++) _cx('c$i', due: inMinutes(2 * i + 2))
        ],
        now: now,
        cfg: _Cfg(
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
        tasks: [_task('zz', due: inMinutes(30))],
        items: [_cx('aa', due: inMinutes(30))],
        now: now,
        cfg: _Cfg(
            taskLeadEnabled: false,
            chaoxingLead2Enabled: false,
            chaoxingLead1Minutes: 0),
      );
      expect(got.length, 2);
      expect(got.map((Reminder r) => r.sourceKey), ['aa', 'zz']);
    });
  });
}

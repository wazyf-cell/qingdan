// 提醒规划器（纯函数）测试的共用夹具（自 reminder_plan_test.dart 拆出；非
// `_test` 文件，flutter test 不直接执行）。
//
// 拆分后的两份文件：
//  - reminder_plan_reminder_kinds_test.dart —— 两个域各自的提醒生成规则
//  - reminder_plan_quiet_and_limit_test.dart —— 免打扰顺延 + 升序与 200 条上限
//
// 本夹具不许 import shared_preferences：「规划器不碰 prefs」这条边界要靠
// 分册的 import 列表本身守住（沿用拆分前的约定）。
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/notify/reminder_plan.dart';

/// 规划器要的 11 项设置。默认值与总纲 §五 一致；免打扰默认**关**，
/// 这样每条用例都能单独说明「顺延」是不是真的发生了。
/// （原 `_Cfg`，为跨文件共用改为公开名。）
class TestReminderConfig implements ReminderConfig {
  const TestReminderConfig({
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
const TestReminderConfig quietCrossMidnight =
    TestReminderConfig(quietHoursEnabled: true, quietStart: 1380, quietEnd: 420);

/// 免打扰 01:00–06:00（不跨午夜）。
const TestReminderConfig quietSameDay =
    TestReminderConfig(quietHoursEnabled: true, quietStart: 60, quietEnd: 360);

/// 测试锚定时刻：本地 2026-10-18 周日上午 10:00。
final DateTime kPlanNow = DateTime(2026, 10, 18, 10, 0);

/// 相对 [kPlanNow] 的分钟偏移。
DateTime inPlanMinutes(int m) => kPlanNow.add(Duration(minutes: m));

/// 一条带到期时刻的任务（原 `_task`）。
Task makePlanTask(String id, {DateTime? due, bool done = false, bool trashed = false}) =>
    Task(
        id: id,
        title: '任务$id',
        dueDate: due,
        completed: done,
        deleted: trashed);

/// 一条学习通快照项（原 `_cx`）。
ChaoxingSnapshotItem makePlanChaoxing(String key,
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

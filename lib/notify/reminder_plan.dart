/// 提醒计划（M6-C2 引擎层）：**纯 Dart，零 Flutter / 零插件依赖，全部可单测**。
/// 三条定死语义（`待执行-M6C-设置与通知.md` §C2）：① `at` 已过去的提醒直接滤掉，
/// 不排历史通知；② 免打扰区间内的提醒**顺延**到区间结束时刻（不丢弃、跨午夜正确）；
/// ③ 一次最多 [kMaxScheduledReminders] 条，超出按 `at` 升序取前 N。
/// `ChaoxingSnapshotItem` 放本文件而非 `chaoxing_snapshot.dart`：那边读写
/// SharedPreferences 会拖进 Flutter，本文件必须纯 Dart，故由存储侧反向 import 它。
library;

import 'package:qingdan/domain/task.dart';

const int kMaxScheduledReminders = 200; // 一次排程的上限：防 AlarmManager 被打满
const String kTaskReminderKind = 'task'; // 清单域，走 qingdan_task 通道
const String kChaoxingReminderKind = 'chaoxing'; // 学习通域，走 qingdan_chaoxing
const String kChaoxingPayload = 'chaoxing'; // 通知点击后切到学习通页签

/// 规划器只读这 11 项，由 `NotifySettings` 实现（用抽象接口而不是 import 那边，
/// 是为了本文件零 Flutter 依赖——那边的 prefs 存取要碰 `flutter/services.dart`）。
abstract class ReminderConfig {
  bool get enabled;
  bool get taskLeadEnabled;
  bool get taskDueEnabled;
  bool get chaoxingLead1Enabled;
  bool get chaoxingLead2Enabled;
  bool get quietHoursEnabled;
  int get taskLeadMinutes;
  int get chaoxingLead1Minutes;
  int get chaoxingLead2Minutes;
  int get quietStart;
  int get quietEnd;
}

/// 一条排好的提醒：[sourceKey] = 来源实体键（任务 id / 学习通 key），
/// [payload] 供点击跳转，[subtext] 落到 `AndroidNotificationDetails.subText`。
class Reminder {
  const Reminder({
    required this.kind,
    required this.sourceKey,
    required this.at,
    required this.title,
    required this.body,
    required this.subtext,
    required this.payload,
  });
  final String kind, sourceKey, title, body, subtext, payload;

  /// 排程时刻：**本地** DateTime（免打扰顺延已算好，必然不早于传入的 now）。
  final DateTime at;
}

/// 学习通提醒快照项（C4 落盘的就是它）。三个 flag 是设备本地排除条件：写入方
/// （`ChaoxingModel.refresh()`）只该写未隐藏/未完成/未过期/有 dueAt 的项，规划器
/// 再兜一遍——快照是上次打开时抓的，其间用户能在网页里把作业交了。
class ChaoxingSnapshotItem {
  const ChaoxingSnapshotItem({
    required this.key,
    required this.courseName,
    required this.title,
    this.dueAt,
    this.hidden = false,
    this.serverDone = false,
    this.ongoing = true,
  });
  final String key, courseName, title;
  final DateTime? dueAt;
  final bool hidden, serverDone, ongoing;
}

/// 清单到期提醒：提前量与到期时刻两个**独立**开关，判据只看 [Task.dueDate]。
List<Reminder> planTaskReminders(
    List<Task> tasks, DateTime now, ReminderConfig cfg) {
  if (!cfg.enabled) return const <Reminder>[];
  final Duration lead = Duration(minutes: cfg.taskLeadMinutes);
  final List<Reminder> pending = <Reminder>[];
  for (final Task t in tasks) {
    final DateTime? due = t.dueDate;
    // 无到期不提醒；已完成 / 已进回收站也排除——这正是「完成」「进回收站」要触发
    // 重排的原因，否则重排了个寂寞。
    if (due == null || t.completed || t.deleted) continue;
    if (cfg.taskLeadEnabled) pending.add(_forTask(t, due.subtract(lead), cfg));
    if (cfg.taskDueEnabled) pending.add(_forTask(t, due, cfg));
  }
  return _finalize(pending, now);
}

/// 学习通截止提醒：两档提前量（默认 120 / 30 分钟），**不排截止那一刻**。
List<Reminder> planChaoxingReminders(
    List<ChaoxingSnapshotItem> items, DateTime now, ReminderConfig cfg) {
  if (!cfg.enabled) return const <Reminder>[];
  final List<Duration> leads = <Duration>[
    if (cfg.chaoxingLead1Enabled) Duration(minutes: cfg.chaoxingLead1Minutes),
    if (cfg.chaoxingLead2Enabled) Duration(minutes: cfg.chaoxingLead2Minutes),
  ];
  final List<Reminder> pending = <Reminder>[];
  for (final ChaoxingSnapshotItem it in items) {
    final DateTime? due = it.dueAt;
    // 四种排除：无 dueAt、已隐藏、服务端已完成、已结束(!ongoing)。「已过期
    // (dueAt < now)」不必单列——提前量必然更早，由 _finalize 滤掉。
    if (due == null || it.hidden || it.serverDone || !it.ongoing) continue;
    for (final Duration lead in leads) {
      pending.add(_forChaoxing(it, due.subtract(lead), cfg));
    }
  }
  return _finalize(pending, now);
}

/// 两个域合并成一份总计划：重排入口用它（顺延与过滤各自做完，再全局升序截断）。
List<Reminder> planReminders({required List<Task> tasks,
    required List<ChaoxingSnapshotItem> items, required DateTime now,
    required ReminderConfig cfg}) => _sortedCapped(<Reminder>[
  ...planTaskReminders(tasks, now, cfg),
  ...planChaoxingReminders(items, now, cfg)]);

/// 免打扰顺延：[at] 落在区间内就推到**区间结束时刻**，不丢弃。跨午夜
/// （`quietStart > quietEnd`，默认 23:00–07:00）两种落点：23:30 → **次日** 07:00、
/// 02:00 → **当日** 07:00；不跨午夜（01:00–06:00）推到当日结束时刻。右端点开
/// （`at == quietEnd` 不算落在内）。起止相等视为空区间 → 不顺延，否则所有提醒会
/// 挤到同一时刻。
DateTime applyQuietHours(DateTime at, ReminderConfig cfg) {
  if (!cfg.quietHoursEnabled) return at;
  final int start = cfg.quietStart, end = cfg.quietEnd;
  if (start == end) return at;
  final int minutes = at.hour * 60 + at.minute;
  final bool inQuiet = start < end
      ? minutes >= start && minutes < end
      : minutes >= start || minutes < end; // 跨午夜 = 头一段 + 尾一段
  if (!inQuiet) return at;
  // 只有落在 start 之后的头一段才推到次日，凌晨那段回到当日 end。
  final bool nextDay = start > end && minutes >= start;
  return DateTime(
      at.year, at.month, at.day + (nextDay ? 1 : 0), end ~/ 60, end % 60);
}

/// 先顺延，再按**顺延后**的时刻算相对文案（顺延可能把它推过到期点）。
Reminder _forTask(Task t, DateTime rawAt, ReminderConfig cfg) {
  final DateTime at = applyQuietHours(rawAt, cfg);
  return Reminder(
      kind: kTaskReminderKind, sourceKey: t.id, at: at, title: '待办提醒',
      body: t.title, payload: t.id, subtext: _relativeToDue(at, t.dueDate!));
}

Reminder _forChaoxing(
    ChaoxingSnapshotItem it, DateTime rawAt, ReminderConfig cfg) {
  final DateTime at = applyQuietHours(rawAt, cfg);
  return Reminder(
      kind: kChaoxingReminderKind, sourceKey: it.key, at: at,
      title: '学习通截止提醒', body: '${it.courseName} · ${it.title}',
      payload: kChaoxingPayload, subtext: _stamp(it.dueAt!));
}

/// 「30 分钟后到期 / 现在到期」：顺延后晚于到期时刻时也写「现在到期」，不新造
/// 文案、不谎报剩余时间。
String _relativeToDue(DateTime at, DateTime due) {
  final int minutes = due.difference(at).inMinutes;
  if (minutes <= 0) return '现在到期';
  if (minutes < 60) return '$minutes 分钟后到期';
  if (minutes < 1440) return '${minutes ~/ 60} 小时后到期';
  return '${minutes ~/ 1440} 天后到期';
}

/// `MM-dd HH:mm`：学习通通知的子文本就是截止时间原文。
String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 滤掉已过去的 → 升序 → 截断。顺序不能换：顺延会改变先后。
List<Reminder> _finalize(List<Reminder> pending, DateTime now) => _sortedCapped(
    <Reminder>[for (final Reminder r in pending) if (!r.at.isBefore(now)) r]);

List<Reminder> _sortedCapped(List<Reminder> reminders) {
  final List<Reminder> sorted = List<Reminder>.of(reminders)
    ..sort((Reminder a, Reminder b) {
      final int byAt = a.at.compareTo(b.at);
      // 同刻按来源键定序：List.sort 不稳定，截断处不能有随机结果。
      return byAt != 0 ? byAt : a.sourceKey.compareTo(b.sourceKey);
    });
  return sorted.length <= kMaxScheduledReminders
      ? sorted
      : sorted.sublist(0, kMaxScheduledReminders);
}

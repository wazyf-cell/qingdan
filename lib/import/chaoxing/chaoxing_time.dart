/// 学习通待办的时间文案（纯 Dart，无 Flutter 依赖，可单测）。
///
/// 剩余时长与截止行格式逐字对齐扩展成品界面；紧急度阈值取自油猴脚本
/// `扩展/作业列表.js` :3440-3442（含「小时」→ ≤24 小时算急，含「天」→ <1 天算急）。
///
/// 相对时间解析 [parseRemaining] 也住这里：作业页的 `.fr`（脚本 :757-791 抓的
/// 「剩余X小时」）与考试卡片页的 `dd`（:793-832 抓的同一形状）必须用同一份算法，
/// 各写一份迟早会漂。
library;

import 'chaoxing_models.dart';

/// 紧急度档位，由消费方决定配色（这里不碰颜色）。
enum ChaoxingUrgency { none, calm, soon, urgent, overdue }

/// 「剩余241小时」/「剩余120小时55分钟」/「剩余1天0小时」→ [Duration]。
///
/// **空 / 含「过期」/ 一个数字都没有 → null**（= 没有可用截止时间）。语义对齐
/// 脚本 `parseTimeToMinutes` :3268-3281：那里「过期」返回 -1（已过去）、没数字
/// 返回 `Infinity`（排到最后），两者在我们都归成「推不出绝对时刻」。
Duration? parseRemaining(String text) {
  if (text.isEmpty || text.contains('过期')) return null;
  final int days = _num(text, r'(\d+)\s*天');
  final int hours = _num(text, r'(\d+)\s*小时');
  final int minutes = _num(text, r'(\d+)\s*分');
  if (days == 0 && hours == 0 && minutes == 0) return null;
  return Duration(days: days, hours: hours, minutes: minutes);
}

int _num(String text, String pattern) =>
    int.tryParse(RegExp(pattern).firstMatch(text)?.group(1) ?? '') ?? 0;

/// 剩余时长文案，**与扩展成品界面逐字一致**：≥1 天省略分钟（`剩3天0小时`），
/// 不足 1 天带分钟（`剩23小时49分`），不足 1 分显示「不足1分」。
/// （用户 2026-10-17 早先给的示例是 `1天3小时34分`；同日改为「一比一复刻扩展」
/// 后以扩展为准，见变更日志第十一节。）传入负数按绝对值算。
String formatRemaining(Duration d) {
  final Duration a = d.abs();
  if (a.inMinutes < 1) return '不足1分';
  final int days = a.inDays;
  final int hours = a.inHours % 24;
  final int minutes = a.inMinutes % 60;
  if (days > 0) return '$days天$hours小时';
  if (hours > 0) return '$hours小时$minutes分';
  return '$minutes分';
}

/// 扩展卡片上的截止行：`10-18 22:59 截止（剩23小时49分）`。月日补零。
String formatDeadlineLine(DateTime due, DateTime now) {
  final String stamp =
      '${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')} '
      '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
  final Duration d = due.difference(now);
  return d.isNegative
      ? '$stamp 截止（已逾期 ${formatRemaining(d)}）'
      : '$stamp 截止（剩${formatRemaining(d)}）';
}

/// 考试卡片的两行时间：开始 / 截止。考试比作业多一个开始时刻，列表里
/// 只给截止会让「什么时候开考」看不出来（用户 2026-10-26 要求）。
///
/// 缺开始 / 缺截止都如实写「未知」，不猜；已过截止写「已过期」，
/// 与卡片原来的状态文案一致。
({String start, String end}) formatExamWindow(
    ChaoxingTask t, DateTime now) {
  final String start = t.startAt == null
      ? '开始时间未知'
      : '开始 ${_monthDayTime(t.startAt!)}';
  final DateTime? due = t.dueAt;
  final String end;
  if (due == null) {
    end = '截止时间未知';
  } else if (!t.ongoing || due.isBefore(now)) {
    end = '截止 ${_monthDayTime(due)}（已过期）';
  } else {
    end = '截止 ${_monthDayTime(due)}（剩${formatRemaining(due.difference(now))}）';
  }
  return (start: start, end: end);
}

String _monthDayTime(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

ChaoxingUrgency urgencyOf(DateTime? due, DateTime now) {
  if (due == null) return ChaoxingUrgency.none;
  final Duration d = due.difference(now);
  if (d.isNegative) return ChaoxingUrgency.overdue;
  if (d.inHours < 24) return ChaoxingUrgency.urgent;
  if (d.inHours < 72) return ChaoxingUrgency.soon;
  return ChaoxingUrgency.calm;
}

/// 这条待办当前**是否会被卡片上三色底**（红/黄/绿）。
///
/// 抽成一个函数的原因（M6B §B5）：卡片的着色条件与「隐藏时要不要弹确认」
/// 必须是同一个判定，两处各写一套阈值迟早漂移（一处弹确认、另一处不上色，
/// 用户就会认为「没上色的为什么问我」。
///
/// 作业仍是「待办 + 有截止」；考试与课堂活动常常在开始前就出现在列表里
/// （`startAt` 在未来 = `notStarted`），这两类同样按截止时间上色
/// （用户 2026-10-26 要求把作业的三色标识同步过去）。未开始的作业保持旧规则。
bool showsUrgencyTint(ChaoxingTask t, DateTime now) {
  if (t.dueAt == null) return false;
  final ChaoxingTaskState state = t.stateAt(now, done: false);
  if (state == ChaoxingTaskState.todo) return true;
  return state == ChaoxingTaskState.notStarted &&
      t.ongoing &&
      (t.source == ChaoxingSource.exam ||
          t.source == ChaoxingSource.activity);
}

/// 状态在分组/排序里的固定次序：待办最先，未开始次之，已完成、已结束垫底。
const List<ChaoxingTaskState> kStateOrder = <ChaoxingTaskState>[
  ChaoxingTaskState.todo,
  ChaoxingTaskState.notStarted,
  ChaoxingTaskState.done,
  ChaoxingTaskState.ended,
];

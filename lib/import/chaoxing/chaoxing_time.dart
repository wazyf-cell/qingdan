/// 学习通待办的时间文案（纯 Dart，无 Flutter 依赖，可单测）。
///
/// 剩余时长与截止行格式逐字对齐扩展成品界面；紧急度阈值取自油猴脚本
/// `扩展/作业列表.js` :3440-3442（含「小时」→ ≤24 小时算急，含「天」→ <1 天算急）。
library;

import 'chaoxing_models.dart';

/// 紧急度档位，由消费方决定配色（这里不碰颜色）。
enum ChaoxingUrgency { none, calm, soon, urgent, overdue }

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

ChaoxingUrgency urgencyOf(DateTime? due, DateTime now) {
  if (due == null) return ChaoxingUrgency.none;
  final Duration d = due.difference(now);
  if (d.isNegative) return ChaoxingUrgency.overdue;
  if (d.inHours < 24) return ChaoxingUrgency.urgent;
  if (d.inHours < 72) return ChaoxingUrgency.soon;
  return ChaoxingUrgency.calm;
}

/// 状态在分组/排序里的固定次序：待办最先，未开始次之，已完成、已结束垫底。
const List<ChaoxingTaskState> kStateOrder = <ChaoxingTaskState>[
  ChaoxingTaskState.todo,
  ChaoxingTaskState.notStarted,
  ChaoxingTaskState.done,
  ChaoxingTaskState.ended,
];

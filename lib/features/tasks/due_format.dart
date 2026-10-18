import 'package:flutter/material.dart';

import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/theme/app_colors.dart';

/// 到期时间文字（§2.1）：今天→「10:00」；今天之外→「明 10:00」「12/25」；
/// 已过期→整段用过期色；无日期→null（不显示）。
(String?, bool) formatDueText(DateTime? dueUtc, {required bool completed}) {
  if (dueUtc == null) return (null, false);
  final DateTime due = dueUtc.toLocal();
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime dueDay = DateTime(due.year, due.month, due.day);
  final bool overdue = !completed && due.isBefore(now);

  String two(int n) => n.toString().padLeft(2, '0');
  final String hhmm = '${two(due.hour)}:${two(due.minute)}';
  final int days = dueDay.difference(today).inDays;

  final String text;
  if (days == 0) {
    text = hhmm;
  } else if (days == 1) {
    text = '明 $hhmm';
  } else {
    text = '${due.month}/${due.day}';
  }
  return (text, overdue);
}

/// 两位补零（本文件与日期行共用）。
String twoDigits(int n) => n.toString().padLeft(2, '0');

/// 该日期是否填了时分。
///
/// **约定：`00:00` 视为「没填时间」**——`showDatePicker` 返回的就是当日 00:00，
/// 与「用户真的选了午夜」无法区分。要为区分而加一列标记就得动库 + 动同步序列化，
/// 收益不抵代价（M6-A §A3 定案）。
bool hasTimeOfDay(DateTime value) => value.hour != 0 || value.minute != 0;

/// 任务日期字段的展示文字（M6-A §A3）：
/// 无值 → [empty]（默认「未设置」）；有值没时间 → `10-18`；有时间 → `10-18 14:30`。
/// 入参按**本地时间**传（`Task` 里存的是 UTC，展示前要 `.toLocal()`）。
String formatTaskDate(DateTime? value, {String empty = '未设置'}) {
  if (value == null) return empty;
  final String day = '${twoDigits(value.month)}-${twoDigits(value.day)}';
  return hasTimeOfDay(value) ? '$day ${formatTimeOfDay(value)}' : day;
}

/// 时分展示 `14:30`（只在 [hasTimeOfDay] 为真时有意义；00:00 会显示成 `00:00`，
/// 调用方据此知道「没填时间」该走「无时间」文案）。
String formatTimeOfDay(DateTime value) =>
    '${twoDigits(value.hour)}:${twoDigits(value.minute)}';

/// 优先级竖条颜色（§1.2 旗标色；「无」返回 null → 不渲染上色条）。
Color? priorityColor(TaskPriority priority, AppColors colors) =>
    switch (priority) {
      TaskPriority.high => colors.priorityHigh,
      TaskPriority.medium => colors.priorityMedium,
      TaskPriority.low => colors.priorityLow,
      TaskPriority.none => null,
    };

/// 优先级中文名（详情下拉 / 右键子菜单）。
String priorityLabel(TaskPriority priority) => switch (priority) {
      TaskPriority.high => '高',
      TaskPriority.medium => '中',
      TaskPriority.low => '低',
      TaskPriority.none => '无',
    };

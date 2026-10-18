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

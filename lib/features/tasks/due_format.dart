import 'package:flutter/material.dart';

import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/domain/task_schedule.dart' show hasTimeOfDay;
import 'package:qingdan/theme/app_colors.dart';

export 'package:qingdan/domain/task_schedule.dart' show hasTimeOfDay;

/// 两位补零（本文件与日期行共用）。
String twoDigits(int n) => n.toString().padLeft(2, '0');

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

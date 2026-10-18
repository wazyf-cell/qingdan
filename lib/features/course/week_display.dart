// 周次与星期的显示文案（界面 §4.1:46 要求周次显示成「第 1-5、7-11(单)、12-16(双) 周」）。

import 'package:qingdan/domain/week_rule.dart' show formatWeeks;

const List<String> kWeekdayNames = <String>[
  '周一', '周二', '周三', '周四', '周五', '周六', '周日',
];

/// 1~7（ISO）→ 中文星期。
String weekdayName(int weekday) => kWeekdayNames[weekday - 1];

/// 周次列表 → 展示文案。
///
/// 先复用 [formatWeeks] 的紧凑写法（连续段 `1-5`、同奇偶段 `7-11单`），再把
/// `单`/`双` 渲染成设计稿的 `(单)`/`(双)` 形式，避免在 UI 层重写一套分段算法。
String formatWeeksForDisplay(List<int> weeks) {
  if (weeks.isEmpty) return '未设置周次';
  final String compact = formatWeeks(weeks)
      .replaceAll('单', '(单)')
      .replaceAll('双', '(双)');
  return '第 $compact 周';
}

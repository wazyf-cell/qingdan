import 'package:flutter/material.dart';

import 'package:qingdan/domain/week_rule.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 周次 chip 选择器（细化 §4.4:262-280）。
///
/// 这是「周次存 `List<int>`」这个定案（§2.4 方案 b）的直接红利：改某一周
/// 就是一次列表增删，不需要文本手术。
class WeekChipPicker extends StatelessWidget {
  const WeekChipPicker({
    super.key,
    required this.totalWeeks,
    required this.selected,
    required this.onChanged,
    this.isMobile = false,
  });

  final int totalWeeks;
  final List<int> selected;
  final ValueChanged<List<int>> onChanged;
  final bool isMobile;

  Set<int> get _set => <int>{...selected};

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Set<int> chosen = _set;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppDimens.s8,
          runSpacing: AppDimens.s8,
          children: <Widget>[
            for (int w = 1; w <= totalWeeks; w++)
              _Chip(
                week: w,
                on: chosen.contains(w),
                isMobile: isMobile,
                onTap: () {
                  final Set<int> next = <int>{...chosen};
                  if (!next.remove(w)) next.add(w);
                  onChanged(next.toList()..sort());
                },
              ),
          ],
        ),
        const SizedBox(height: AppDimens.s8),
        Row(
          children: <Widget>[
            TextButton(
              onPressed: () =>
                  onChanged(List<int>.generate(totalWeeks, (int i) => i + 1)),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () => onChanged(const <int>[]),
              child: const Text('清空'),
            ),
            TextButton(
              // 单/双 = 绝对奇偶周号（§3.3.1），不是「每隔一周」。
              onPressed: () => onChanged(<int>[
                for (int w = 1; w <= totalWeeks; w++)
                  if (w.isOdd) w,
              ]),
              child: const Text('单周'),
            ),
            TextButton(
              onPressed: () => onChanged(<int>[
                for (int w = 1; w <= totalWeeks; w++)
                  if (w.isEven) w,
              ]),
              child: const Text('双周'),
            ),
            // 计数用 Expanded 右对齐而不是 Spacer：Spacer 会吃掉全部剩余空间，
            // 窄屏（411dp）下文字必然溢出；Expanded 允许它优雅省略号。
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '已选 ${selected.length} / $totalWeeks 周',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.week,
    required this.on,
    required this.isMobile,
    required this.onTap,
  });

  final int week;
  final bool on;
  final bool isMobile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      key: ValueKey<String>('week-$week'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      child: Container(
        width: isMobile ? 44 : 36,
        height: isMobile ? 36 : 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? colors.accent : colors.surface,
          border: Border.all(color: on ? colors.accent : colors.divider),
          borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
        ),
        child: Text(
          '$week',
          style: TextStyle(
            fontSize: isMobile ? 13 : 12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? colors.surface : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 「从文本重建」：把任意周次文本（`1-5、7-11单`）解析成周次列表。
///
/// 返回 null 表示解析失败并带上原文错误说明，供界面提示（不静默吞错，§6.3.1）。
({List<int>? weeks, String? error}) rebuildWeeksFromText(
    String text, int totalWeeks) {
  try {
    final WeekRuleOutcome outcome =
        parseWeekRule(text, totalWeeks: totalWeeks);
    return (weeks: outcome.weeks, error: null);
  } on WeekRuleFormatException catch (e) {
    return (weeks: null, error: e.reason);
  }
}

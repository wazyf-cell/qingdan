import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 顶部星期轴（细化 §2.1:63、§2.5:117-119）：周几 + 日期，吸顶不随网格滚动。
///
/// [todayWeekday] 为 null 时整条没有任何今天痕迹（非当前周不加水印、不灰化）。
class CourseDayAxis extends StatelessWidget {
  const CourseDayAxis({
    super.key,
    required this.days,
    required this.axisWidth,
    required this.dateOf,
    required this.todayWeekday,
    required this.isMobile,
  });

  final List<int> days;
  final double axisWidth;
  final DateTime Function(int weekday) dateOf;
  final int? todayWeekday;
  final bool isMobile;

  static const List<String> _names = <String>[
    '周一', '周二', '周三', '周四', '周五', '周六', '周日',
  ];

  static String nameOf(int weekday) => _names[weekday - 1];

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      height: isMobile
          ? AppDimens.courseHeaderMobile
          : AppDimens.courseHeaderDesktop,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.divider, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: axisWidth),
          for (final int weekday in days)
            Expanded(
              child: Center(
                child: weekday == todayWeekday
                    ? TodayPill(
                        key: const ValueKey<String>('todayPill'),
                        label: _names[weekday - 1],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(_names[weekday - 1],
                              style: const TextStyle(fontSize: 13)),
                          Text('${dateOf(weekday).month}/${dateOf(weekday).day}',
                              style: TextStyle(
                                  fontSize: 10, color: colors.textSecondary)),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 「今天」列头的主题色胶囊（细化 §2.5:117，高 28dp、文字反色）。
class TodayPill extends StatelessWidget {
  const TodayPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      height: AppDimens.courseTodayPill,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.s12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(AppDimens.courseTodayPill / 2),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.surface)),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 今日摘要条（细化 §2.8:140）：44dp、主题色 4% 底，**今天在学期内才出现**，
/// 点击滚动定位到今天的列。学期外整条不渲染（不是灰显）。
class TodaySummaryBar extends StatelessWidget {
  const TodaySummaryBar({
    super.key,
    required this.today,
    required this.courses,
    required this.layout,
    this.onTap,
  });

  final DateTime today;
  final List<Course> courses;
  final SectionLayout layout;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: AppDimens.courseTodayBarHeight,
        padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.s12, vertical: AppDimens.s4),
        color: colors.accent.withValues(
            alpha: AppDimens.courseTodayBandOpacity * 4), // 摘要条比列带显眼一点
        alignment: Alignment.centerLeft,
        child: Text(
          todaySummaryLine(today, courses, layout),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: colors.textPrimary),
        ),
      ),
    );
  }
}

const List<String> _weekdayCn = <String>[
  '周一', '周二', '周三', '周四', '周五', '周六', '周日'
];

/// 摘要文案（纯函数，便于单测）：
/// `今天 · 周一 9/8 · 2 节：08:00 高等数学@逸夫楼201 · 10:15 线性代数`。
String todaySummaryLine(
    DateTime today, List<Course> courses, SectionLayout layout) {
  final String head =
      '今天 · ${_weekdayCn[today.weekday - 1]} ${today.month}/${today.day}';
  if (courses.isEmpty) return '$head · 今天没有课';
  final List<Course> sorted = <Course>[...courses]
    ..sort((Course a, Course b) => a.startSection.compareTo(b.startSection));
  final String body = sorted.map((Course c) {
    final int? start = layout.timeOf(c.startSection)?.startMinutes;
    final String time = start == null ? '未排' : formatMinutes(start);
    final String place =
        (c.location == null || c.location!.isEmpty) ? '' : '@${c.location}';
    return '$time ${c.name}$place';
  }).join(' · ');
  return '$head · ${sorted.length} 节：$body';
}

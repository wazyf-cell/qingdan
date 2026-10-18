import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_conflict.dart';
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_block.dart';

/// 左侧节次轴（细化 §2.1:62）：桌面两行（节号 + 开始时间），移动只放节号。
///
/// 它随网格一起纵向滚动（本视图没有横向滚动，所以恒可见，不需要真的「吸住」）。
class CourseSectionAxis extends StatelessWidget {
  const CourseSectionAxis(
      {super.key, required this.layout, required this.isMobile});

  final SectionLayout layout;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Stack(
      children: <Widget>[
        for (final SectionSlot slot in layout.slots)
          Positioned(
            top: slot.top + 2,
            left: 0,
            right: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text('${slot.section}', style: const TextStyle(fontSize: 12)),
                if (!isMobile)
                  Text(formatMinutes(slot.startMinutes),
                      style:
                          TextStyle(fontSize: 10, color: colors.textSecondary)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 一天的列：今天色带 + 1dp 分隔线 + 课程块（同槽垂直堆叠）。
class CourseDayColumn extends StatelessWidget {
  const CourseDayColumn({
    super.key,
    required this.layout,
    required this.groups,
    required this.isToday,
    required this.isMobile,
    this.onBlockTap,
  });

  final SectionLayout layout;
  final List<OverlapGroup> groups;
  final bool isToday;
  final bool isMobile;
  final void Function(Course course, List<Course> sameSlot)? onBlockTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colors.divider, width: 1),
          left: BorderSide(color: colors.divider, width: 1),
        ),
        color: isToday
            ? colors.accent
                .withValues(alpha: AppDimens.courseTodayBandOpacity)
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final SectionSlot slot in layout.slots)
            Positioned(
              top: slot.bottom,
              left: 0,
              right: 0,
              child: Container(height: 1, color: colors.divider),
            ),
          for (final OverlapGroup group in groups) ..._blocksOf(group),
        ],
      ),
    );
  }

  /// 一个组渲染成 1 个降级块，或 n 个堆叠块（块间 2dp，细化 §2.4:106）。
  List<Widget> _blocksOf(OverlapGroup group) {
    final ({double top, double height})? rect =
        layout.rectFor(group.spanStart, group.spanEnd);
    if (rect == null) return const <Widget>[]; // 缺节次 → 交「未排时间」区
    final double groupTop = rect.top;
    final double groupHeight = rect.height;

    if (group.needsCompactFor(groupHeight,
        minBlockDp: AppDimens.courseMinBlockHeight)) {
      final Course first = group.courses.first;
      return <Widget>[
        Positioned(
          top: groupTop,
          left: 1,
          right: 1,
          height: groupHeight,
          child: CourseBlock(
            key: ValueKey<String>('block-${first.id}'),
            name: first.name,
            colorIndex: first.effectiveColorIndex,
            height: groupHeight,
            badgeCount: group.badgeCount,
            isMobile: isMobile,
            onTap: () => onBlockTap?.call(first, group.courses),
          ),
        ),
      ];
    }

    final int n = group.courses.length;
    final double itemHeight =
        (groupHeight - (n - 1) * AppDimens.courseStackGap) / n;
    return <Widget>[
      for (int i = 0; i < n; i++)
        Positioned(
          top: groupTop + i * (itemHeight + AppDimens.courseStackGap),
          left: 1,
          right: 1,
          height: itemHeight,
          child: CourseBlock(
            key: ValueKey<String>('block-${group.courses[i].id}'),
            name: group.courses[i].name,
            location: group.courses[i].location,
            teacher: group.courses[i].teacher,
            colorIndex: group.courses[i].effectiveColorIndex,
            height: itemHeight,
            isMobile: isMobile,
            onTap: () => onBlockTap?.call(group.courses[i], group.courses),
          ),
        ),
    ];
  }
}

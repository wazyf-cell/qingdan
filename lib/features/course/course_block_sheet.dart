import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'package:qingdan/theme/app_palette.dart';

import 'week_display.dart';

/// 点击课程块的详情弹层（§4.1：桌面锚定 / 移动底部抽屉，本轮统一用两端各自的形态）。
///
/// 返回 true 表示用户点了「编辑」。
Future<bool?> showCourseBlockSheet(
  BuildContext context, {
  required Course course,
  required SectionLayout layout,
  required bool isMobile,
}) {
  final Widget body = CourseBlockDetail(
    course: course,
    layout: layout,
    onEdit: () => Navigator.of(context).pop(true),
  );
  return isMobile
      ? showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext ctx) => SafeArea(child: body),
        )
      : showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            content: SizedBox(width: 280, child: body),
          ),
        );
}

/// 详情内容：课名 + 星期节次 + 老师 + 地点 + 周次 + 本节课时间区间。
class CourseBlockDetail extends StatelessWidget {
  const CourseBlockDetail({
    super.key,
    required this.course,
    required this.layout,
    required this.onEdit,
  });

  final Course course;
  final SectionLayout layout;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.all(AppDimens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: CoursePalette.of(
                      brightness, courseColorIndex(course.name)),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppDimens.s8),
              Expanded(
                child: Text(course.name, style: AppTypography.panelTitle),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.s12),
          Text('星期节次：${weekdayName(course.weekday)} '
              '第 ${course.startSection}-${course.endSection} 节',
              style: AppTypography.body),
          if (course.teacher != null)
            Text('老师：${course.teacher}', style: AppTypography.body),
          if (course.location != null)
            Text('地点：${course.location}', style: AppTypography.body),
          Text('周次：${formatWeeksForDisplay(course.weeks)}',
              style: AppTypography.body),
          if (timeRangeText() != null)
            Text('本节课时间：${timeRangeText()}',
                style: AppTypography.meta
                    .copyWith(color: colors.textSecondary)),
          const SizedBox(height: AppDimens.s12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey<String>('block-edit'),
              onPressed: onEdit,
              child: const Text('编辑'),
            ),
          ),
        ],
      ),
    );
  }

  /// 本节课的起止时间（由作息表换算；节次缺失时不显示，不瞎猜）。
  String? timeRangeText() {
    final int? start = layout.timeOf(course.startSection)?.startMinutes;
    final int? end = layout.timeOf(course.endSection)?.endMinutes;
    if (start == null || end == null) return null;
    return '${formatMinutes(start)}–${formatMinutes(end)}';
  }
}

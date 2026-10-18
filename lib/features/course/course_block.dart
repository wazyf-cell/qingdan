import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_palette.dart';

/// 课程块（细化 §2.3:84-101、§2.4:103-111）。
///
/// 底色 = 调色板色 16% 透明，左侧 3dp 实色竖条，课名用同色的前景变体。
/// **不用阴影**（细化 §0:22：高程只用表面色差 + 1dp 分隔线表达）。
///
/// 同槽多门课时，块本身**只装当前选中的那一门**；循环角标与「2/3」计数由
/// [CourseDayColumn] 叠在块上（见 course_cycle_badge.dart，2026-10-19 改版：
/// 原来的均分堆叠与「+N」降级块一起废掉）。
class CourseBlock extends StatelessWidget {
  const CourseBlock({
    super.key,
    required this.name,
    required this.colorIndex,
    required this.height,
    this.location,
    this.teacher,
    this.trailingReserve = 0,
    this.isMobile = false,
    this.onTap,
  });

  final String name;
  final int colorIndex;
  final double height;
  final String? location;
  final String? teacher;

  /// 右上角给组内计数小字让出的宽度（0 = 没有叠加物）。
  ///
  /// 窄屏一格只有 70dp 左右，课名本来就要省略号，不让位的话省略号会直接压在
  /// 「2/3」上面（细化 §2.4，2026-10-19）。
  final double trailingReserve;
  final bool isMobile;
  final VoidCallback? onTap;

  /// 密度阶梯（细化 §2.3:96-101）：决定块里放得下几行信息。
  ///
  /// 移动端永不显示老师（§4.1：宽度不足时只显示课名与地点）。
  bool get _showLocation => height >= 38;
  bool get _showTeacher =>
      !isMobile && height >= 72 && (teacher?.isNotEmpty ?? false);
  bool get _singleLineName => height < 72;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final Color base = CoursePalette.of(brightness, colorIndex);
    final Radius radius = Radius.circular(
        isMobile ? AppDimens.radiusMobile : AppDimens.radiusDesktop);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: CoursePalette.blockBackground(brightness, colorIndex),
          borderRadius: BorderRadius.all(radius),
        ),
        child: Stack(
          children: <Widget>[
            // 左侧 3dp 实色竖条，跟随块圆角（细化 §2.3:87）。
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: AppDimens.courseBarWidth,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.only(
                    topLeft: radius,
                    bottomLeft: radius,
                  ),
                ),
              ),
            ),
            Padding(
              padding: AppDimens.courseBlockPadding.copyWith(
                  right: AppDimens.courseBlockPadding.right + trailingReserve),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    maxLines: _singleLineName ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 15 / 12,
                      fontWeight: FontWeight.w600,
                      color: CoursePalette.foreground(brightness, colorIndex),
                    ),
                  ),
                  if (_showLocation && (location?.isNotEmpty ?? false))
                    Text(
                      location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 13 / 10,
                        color: colors.textSecondary,
                      ),
                    ),
                  if (_showTeacher)
                    Text(
                      teacher!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 13 / 10,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

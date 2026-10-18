import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_palette.dart';

/// 课程块（细化 §2.3:84-101、§2.4:103-111）。
///
/// 底色 = 调色板色 16% 透明，左侧 3dp 实色竖条，课名用同色的前景变体。
/// **不用阴影**（细化 §0:22：高程只用表面色差 + 1dp 分隔线表达）。
class CourseBlock extends StatelessWidget {
  const CourseBlock({
    super.key,
    required this.name,
    required this.colorIndex,
    required this.height,
    this.location,
    this.teacher,
    this.badgeCount = 0,
    this.isMobile = false,
    this.onTap,
  });

  final String name;
  final int colorIndex;
  final double height;
  final String? location;
  final String? teacher;

  /// > 0 表示这是**降级容器块**：只显示课名首二字，右上角「+N」角标
  /// （细化 §2.4:108-109：N 为被折进去的条数，角标不用错误色）。
  final int badgeCount;
  final bool isMobile;
  final VoidCallback? onTap;

  /// 密度阶梯（细化 §2.3:96-101）：决定块里放得下几行信息。
  ///
  /// 移动端永不显示老师（§4.1：宽度不足时只显示课名与地点）。
  bool get _showLocation => height >= 38;
  bool get _showTeacher =>
      !isMobile && height >= 72 && (teacher?.isNotEmpty ?? false);
  bool get _singleLineName => height < 72;

  String get _displayName {
    if (badgeCount > 0) {
      // 降级：只留首二字。
      return name.characters.take(2).string;
    }
    return name;
  }

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
              padding: AppDimens.courseBlockPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _displayName,
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
            if (badgeCount > 0)
              Positioned(
                right: 3,
                top: 3,
                child: _Badge(count: badgeCount, colors: colors),
              ),
          ],
        ),
      ),
    );
  }
}

/// 「+N」角标：次要文字色底 + 表面色字（细化 §2.4:109 写「反白字」又说「次要文字色底」，
/// 两处自相矛盾；按「不用错误色」的硬约束取后者为准，2026-10-10 定案）。
class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.colors});

  final int count;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colors.textSecondary,
        borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      ),
      child: Text(
        '+$count',
        style: TextStyle(
          fontSize: 11,
          height: 13 / 11,
          fontWeight: FontWeight.w600,
          color: colors.surface,
        ),
      ),
    );
  }
}

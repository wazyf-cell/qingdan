import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 课表二级页的统一外壳：Scaffold + 与「课表管理」同款的 AppBar 与 1dp 分隔线。
///
/// 手机端把原来的弹层换成整页时，四个页面都套这一层，避免各写一份 AppBar
/// 造成字号/颜色漂移。
class CoursePageScaffold extends StatelessWidget {
  const CoursePageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.textSecondary,
        titleTextStyle: AppTypography.pageTitle
            .copyWith(fontSize: 17, color: colors.textPrimary),
        title: Text(title),
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.divider),
        ),
      ),
      body: child,
    );
  }
}

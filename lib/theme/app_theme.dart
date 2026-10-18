import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 应用主题装配：MaterialApp 的浅/深两套 `ThemeData` 由此产出。
///
/// 设计基线（方案设计-M1界面.md）：
/// - §1.1 高程用表面色差 + 1dp 分隔线表达，不用投影（浮层除外）；
/// - §1.2 主题跟随系统 + 应用内三选项，切换即时生效、不做过渡动画；
/// - 自定义语义色（优先级/来源/accentFaint 等）经 `ThemeExtension` 挂载，
///   消费方统一走 `AppColors.of(context)`。
class AppTheme {
  AppTheme._();

  /// 浅色主题。
  static ThemeData light() => _build(Brightness.light, AppColors.light());

  /// 深色主题。
  static ThemeData dark() => _build(Brightness.dark, AppColors.dark());

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.surface,
      secondary: colors.accent,
      onSecondary: colors.surface,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      error: colors.overdue,
      onError: colors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.bg,
      splashFactory: NoSplash.splashFactory,
      extensions: <ThemeExtension<dynamic>>[colors],
      textTheme: TextTheme(
        titleLarge: AppTypography.pageTitle,
        titleMedium: AppTypography.panelTitle,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.meta,
        labelSmall: AppTypography.counter,
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      // §1.1：去掉 Material 默认投影体系，层次靠表面色差与分隔线。
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surface,
        // §1.5 浮层阴影：y+2 blur 8 @ 20% 黑。
        elevation: 8,
        shadowColor: const Color(0x33000000),
      ),
    );
  }
}

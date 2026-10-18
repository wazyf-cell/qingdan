import 'package:flutter/material.dart';

/// 语义色 token（`开发文档/02-方案设计/方案设计-M1界面.md` §1.2，色值逐条照抄）。
///
/// 统一访问入口：[AppColors.of]（内部为
/// `Theme.of(context).extension<AppColors>()!`）。
/// 注意：
/// - 优先级「无」不上色，不设 token，消费方直接不渲染竖条；
/// - 来源「任务」无标记，不设 token；
/// - accentFaint 为「主色 @ 透明度」（浅 10% / 深 16%），以 alpha 前缀编码。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.divider,
    required this.accent,
    required this.accentFaint,
    required this.success,
    required this.overdue,
    required this.priorityHigh,
    required this.priorityMedium,
    required this.priorityLow,
    required this.sourceEvent,
    required this.sourceCourse,
    required this.dueUrgentBg,
    required this.dueNearBg,
    required this.dueSafeBg,
  });

  /// 浅色板（§1.2 表格「浅色」列）。
  const AppColors.light()
      : this(
          bg: const Color(0xFFF7F7F8),
          surface: const Color(0xFFFFFFFF),
          surfaceHigh: const Color(0xFFFAFAFB),
          textPrimary: const Color(0xFF1F2328),
          textSecondary: const Color(0xFF6B7280),
          textFaint: const Color(0xFF9CA3AF),
          divider: const Color(0xFFE5E7EB),
          accent: const Color(0xFF4263EB),
          accentFaint: const Color(0x1A4263EB), // 10%
          success: const Color(0xFF30A46C),
          overdue: const Color(0xFFD93025),
          priorityHigh: const Color(0xFFE5484D),
          priorityMedium: const Color(0xFFF5A524),
          priorityLow: const Color(0xFF3B82F6),
          sourceEvent: const Color(0xFF8E4EC6),
          sourceCourse: const Color(0xFF12A594),
          dueUrgentBg: const Color(0xFFFFF5F5),
          dueNearBg: const Color(0xFFFFF7E6),
          dueSafeBg: const Color(0xFFF0FBF0),
        );

  /// 深色板（§1.2 表格「深色」列）。
  const AppColors.dark()
      : this(
          bg: const Color(0xFF101113),
          surface: const Color(0xFF17181C),
          surfaceHigh: const Color(0xFF1E2024),
          textPrimary: const Color(0xFFE6E8EB),
          textSecondary: const Color(0xFF9AA0A6),
          textFaint: const Color(0xFF5F6368),
          divider: const Color(0xFF26282C),
          accent: const Color(0xFF7C93F5),
          accentFaint: const Color(0x297C93F5), // 16%
          success: const Color(0xFF3DD68C),
          overdue: const Color(0xFFFF7A72),
          priorityHigh: const Color(0xFFFF6369),
          priorityMedium: const Color(0xFFFFB224),
          priorityLow: const Color(0xFF52A9FF),
          sourceEvent: const Color(0xFFC298FF),
          sourceCourse: const Color(0xFF4CCBAC),
          dueUrgentBg: const Color(0xFF2A1D1E),
          dueNearBg: const Color(0xFF2A2417),
          dueSafeBg: const Color(0xFF1A2A1E),
        );

  /// 窗口底、页面底。
  final Color bg;

  /// 侧栏、列表、面板底。
  final Color surface;

  /// 输入框底、hover 行底。
  final Color surfaceHigh;

  /// 任务标题（主文字）。
  final Color textPrimary;

  /// 元信息、分组头、时间。
  final Color textSecondary;

  /// 占位符、禁用。
  final Color textFaint;

  /// 行分隔、边框、网格线。
  final Color divider;

  /// 选中、勾选框、今天高亮、焦点。
  final Color accent;

  /// 选中行底、今天列色带（accent @ 10% / 16%）。
  final Color accentFaint;

  /// 已完成勾选、完成时间。
  final Color success;

  /// 逾期到期时间文字。
  final Color overdue;

  /// 优先级-高（旗标色）。
  final Color priorityHigh;

  /// 优先级-中（旗标色）。
  final Color priorityMedium;

  /// 优先级-低（旗标色）。
  final Color priorityLow;

  /// 来源-外部事件（6dp 圆点）。
  final Color sourceEvent;

  /// 来源-课表（M4 预留，6dp 菱形点）。
  final Color sourceCourse;

  /// 学习通到期底色三档（2026-10-17 用户要求：1 天内淡红 / 3 天内淡黄 /
  /// 其余期限内淡绿）。色值不是随手挑的：浅底再深一点就把 `textSecondary`
  /// 压到 4.5:1 以下（实测 #FFF3F3 只有 4.46），所以取「能过文字档的最深值」，
  /// 靠同排的 6dp 竖条（[overdue] / [priorityMedium] / [success]）拉开辨识度。
  /// 断言在 `test/palette_contrast_test.dart`。
  final Color dueUrgentBg;
  final Color dueNearBg;
  final Color dueSafeBg;

  /// 统一访问入口。
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? textPrimary,
    Color? textSecondary,
    Color? textFaint,
    Color? divider,
    Color? accent,
    Color? accentFaint,
    Color? success,
    Color? overdue,
    Color? priorityHigh,
    Color? priorityMedium,
    Color? priorityLow,
    Color? sourceEvent,
    Color? sourceCourse,
    Color? dueUrgentBg,
    Color? dueNearBg,
    Color? dueSafeBg,
  }) =>
      AppColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textFaint: textFaint ?? this.textFaint,
        divider: divider ?? this.divider,
        accent: accent ?? this.accent,
        accentFaint: accentFaint ?? this.accentFaint,
        success: success ?? this.success,
        overdue: overdue ?? this.overdue,
        priorityHigh: priorityHigh ?? this.priorityHigh,
        priorityMedium: priorityMedium ?? this.priorityMedium,
        priorityLow: priorityLow ?? this.priorityLow,
        sourceEvent: sourceEvent ?? this.sourceEvent,
        sourceCourse: sourceCourse ?? this.sourceCourse,
        dueUrgentBg: dueUrgentBg ?? this.dueUrgentBg,
        dueNearBg: dueNearBg ?? this.dueNearBg,
        dueSafeBg: dueSafeBg ?? this.dueSafeBg,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentFaint: Color.lerp(accentFaint, other.accentFaint, t)!,
      success: Color.lerp(success, other.success, t)!,
      overdue: Color.lerp(overdue, other.overdue, t)!,
      priorityHigh: Color.lerp(priorityHigh, other.priorityHigh, t)!,
      priorityMedium: Color.lerp(priorityMedium, other.priorityMedium, t)!,
      priorityLow: Color.lerp(priorityLow, other.priorityLow, t)!,
      sourceEvent: Color.lerp(sourceEvent, other.sourceEvent, t)!,
      sourceCourse: Color.lerp(sourceCourse, other.sourceCourse, t)!,
      dueUrgentBg: Color.lerp(dueUrgentBg, other.dueUrgentBg, t)!,
      dueNearBg: Color.lerp(dueNearBg, other.dueNearBg, t)!,
      dueSafeBg: Color.lerp(dueSafeBg, other.dueSafeBg, t)!,
    );
  }
}

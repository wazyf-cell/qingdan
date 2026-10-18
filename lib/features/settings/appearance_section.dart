import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'package:qingdan/theme/theme_mode_model.dart';

/// 设置 · 外观节（§1.2）：主题三选项「浅色 / 深色 / 跟随系统」，切换即时生效。
class AppearanceSection extends StatelessWidget {
  /// [showTitle] 为 false 时不画节标题：窄屏的二级页顶栏已经写了「外观」，
  /// 再画一次就是两行同名（桌面对话框的右栏没有顶栏，靠这个标题认节）。
  const AppearanceSection({super.key, this.showTitle = true});

  final bool showTitle;

  static const List<(ThemeMode, String, IconData)> _options = <(ThemeMode, String, IconData)>[
    (ThemeMode.light, '浅色', Icons.light_mode_outlined),
    (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
    (ThemeMode.system, '跟随系统', Icons.settings_suggest_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final ThemeModeModel model = context.watch<ThemeModeModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('外观',
              style:
                  AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
        ],
        Text('主题',
            style:
                AppTypography.meta.copyWith(color: colors.textSecondary)),
        const SizedBox(height: AppDimens.s8),
        for (final (ThemeMode mode, String label, IconData icon) in _options)
          _ThemeOption(
            icon: icon,
            label: label,
            selected: model.mode == mode,
            colors: colors,
            onTap: () => model.setMode(mode),
          ),
      ],
    );
  }
}

/// 单个主题选项行：32dp 高、选中态 accentFaint 行底 + accent 图标文字 + 对勾。
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.colors,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final AppColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget row = Container(
      height: AppDimens.sidebarItemHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.s8),
      decoration: BoxDecoration(
        color: selected ? colors.accentFaint : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon,
              size: 20,
              color: selected ? colors.accent : colors.textSecondary),
          const SizedBox(width: AppDimens.s8),
          Expanded(
            child: Text(label,
                style: AppTypography.body.copyWith(
                    color: selected ? colors.accent : colors.textPrimary)),
          ),
          if (selected)
            Icon(Icons.check, size: 16, color: colors.accent),
        ],
      ),
    );
    return InkWell(
      onTap: onTap,
      hoverColor: colors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      child: row,
    );
  }
}

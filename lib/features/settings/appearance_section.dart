import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'package:qingdan/theme/theme_mode_model.dart';

import 'settings_model.dart';

/// 设置 · 外观节（§1.2 + M6-C C1）：主题三选项 + 手机默认页签 + 底部角标。
///
/// 后两项原来在「通用」里，但它们管的全是**界面长什么样、开屏看见什么**，
/// 归到外观后「通用」就只剩跟系统打交道的事，两节不再互相夹带。
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
    final SettingsModel settings = context.watch<SettingsModel>();

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
        // 下面两项只对**窄屏形态**有意义（桌面没有底部页签，桌面从侧栏选视图），
        // 所以文案里写清楚作用范围，不留一个看起来全局生效、实际只管手机的开关。
        const SizedBox(height: AppDimens.s24),
        Text('手机默认打开的页面',
            style:
                AppTypography.meta.copyWith(color: colors.textSecondary)),
        const SizedBox(height: AppDimens.s8),
        SegmentedButton<ShellTab>(
          key: const ValueKey<String>('settings-default-tab'),
          showSelectedIcon: false,
          segments: SettingsModel.kDefaultTabChoices
              .map((ShellTab t) =>
                  ButtonSegment<ShellTab>(value: t, label: Text(t.label)))
              .toList(),
          selected: <ShellTab>{settings.defaultTab},
          onSelectionChanged: (Set<ShellTab> next) =>
              settings.setDefaultTab(next.first),
        ),
        const SizedBox(height: AppDimens.s16),
        Text('底部页签角标',
            style:
                AppTypography.meta.copyWith(color: colors.textSecondary)),
        SwitchListTile(
          key: const ValueKey<String>('settings-show-badges'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: settings.showBadges,
          onChanged: settings.setShowBadges,
          title: Text('显示待办数字',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
        ),
        // 角标会「停在上次拉取」是定案里写明接受的行为，不说一句就像 bug。
        Text('清单角标 = 今天未完成数；学习通角标 = 待办条数，'
            '24 小时内有到期时变红。学习通只在你打开那个页面时拉取，'
            '没打开过就一直停在上一次的数字。',
            style:
                AppTypography.meta.copyWith(color: colors.textFaint, height: 1.4)),
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

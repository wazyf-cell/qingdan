import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'settings_model.dart';

/// 设置 · 通用节（M5 定案第 2、10 条）：默认打开的页签 + 角标开关。
///
/// 两项都只对**窄屏形态**有意义（桌面没有底部页签，桌面从侧栏选视图），
/// 所以文案里写清楚作用范围，不留一个看起来全局生效、实际只管手机的开关。
class GeneralSection extends StatelessWidget {
  const GeneralSection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final SettingsModel model = context.watch<SettingsModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('通用',
              style:
                  AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
        ],
        _label(colors, '手机默认打开的页面'),
        SegmentedButton<ShellTab>(
          showSelectedIcon: false,
          segments: SettingsModel.kDefaultTabChoices
              .map((ShellTab t) =>
                  ButtonSegment<ShellTab>(value: t, label: Text(t.label)))
              .toList(),
          selected: <ShellTab>{model.defaultTab},
          onSelectionChanged: (Set<ShellTab> next) =>
              model.setDefaultTab(next.first),
        ),
        const SizedBox(height: AppDimens.s8),
        _label(colors, '底部页签角标'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: model.showBadges,
          onChanged: model.setShowBadges,
          title: Text('显示待办数字',
              style:
                  AppTypography.body.copyWith(color: colors.textPrimary)),
        ),
        // 角标会「停在上次拉取」是定案里写明接受的行为，不说一句就像 bug。
        _note(colors, '清单角标 = 今天未完成数；学习通角标 = 待办条数，'
            '24 小时内有到期时变红。学习通只在你打开那个页面时拉取，'
            '没打开过就一直停在上一次的数字。'),
      ],
    );
  }

  static Widget _label(AppColors colors, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.s4),
        child: Text(text,
            style: AppTypography.meta.copyWith(color: colors.textSecondary)),
      );

  static Widget _note(AppColors colors, String text) => Padding(
        padding: const EdgeInsets.only(top: AppDimens.s4),
        child: Text(text,
            style: AppTypography.meta
                .copyWith(color: colors.textFaint, height: 1.4)),
      );
}

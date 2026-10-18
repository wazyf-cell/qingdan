import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'settings_nav.dart';

/// 设置入口：桌面端对话框容器（七节，与手机一级页同一份 [settingsEntries]）。
///
/// 形态：左侧导航 + 右侧内容区。窄屏不用这个对话框（640×440 比手机屏还宽，
/// 右栏被挤没），走 `settings_page.dart` 的「一级列表 → 二级整页」。
/// 节组件两端共用，不复制。
void showSettingsDialog(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭设置',
    barrierColor: const Color(0x66000000), // 遮罩 40% 黑（§2.6 同款）
    transitionDuration: Duration.zero, // §1.2：不做过渡动画
    pageBuilder: (BuildContext ctx, _, _) {
      return const Center(child: _SettingsDialog());
    },
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  /// 当前选中的节 id；默认第一行（外观）。
  SettingsSectionId _section = SettingsSectionId.appearance;

  static final List<SettingsEntry> _entries = settingsEntries();

  SettingsEntry get _current =>
      _entries.firstWhere((SettingsEntry e) => e.id == _section);

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      ),
      child: Container(
        width: 640,
        height: 440,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
          boxShadow: AppDimens.overlayShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildNav(colors),
            Container(width: 1, color: colors.divider),
            _buildContent(colors),
          ],
        ),
      ),
    );
  }

  // ---- 左侧导航 ----
  Widget _buildNav(AppColors colors) {
    return SizedBox(
      width: 160,
      child: Container(
        color: colors.surfaceHigh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppDimens.s16),
              child: Text('设置',
                  style: AppTypography.panelTitle
                      .copyWith(color: colors.textPrimary)),
            ),
            for (final SettingsEntry entry in _entries)
              _NavItem(
                icon: entry.icon,
                label: entry.title,
                selected: _section == entry.id,
                colors: colors,
                onTap: () => setState(() => _section = entry.id),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppDimens.s16),
              child: Text('关闭',
                  style: AppTypography.meta.copyWith(color: colors.textFaint)),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 右侧内容区 ----
  Widget _buildContent(AppColors colors) {
    return Expanded(
      // key 让切换节时整棵子树重建：各节都有自己的 StatefulWidget 状态
      // （同步节的输入框、通知节的回执），不换 key 会被 Flutter 复用成串台。
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.s24),
        child: SingleChildScrollView(
          child: KeyedSubtree(
            key: ValueKey<SettingsSectionId>(_current.id),
            child: _current.content(true),
          ),
        ),
      ),
    );
  }
}

/// 左侧导航项（与侧栏规格一致：32dp 高、左 16dp、图标-文字 8dp）。
class _NavItem extends StatelessWidget {
  const _NavItem({
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
      color: selected ? colors.accentFaint : null,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.s16),
      child: Row(
        children: <Widget>[
          Icon(icon,
              size: 20,
              color: selected ? colors.accent : colors.textSecondary),
          const SizedBox(width: AppDimens.s8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body
                  .copyWith(color: selected ? colors.accent : colors.textPrimary),
            ),
          ),
        ],
      ),
    );
    return InkWell(onTap: onTap, hoverColor: colors.surfaceHigh, child: row);
  }
}

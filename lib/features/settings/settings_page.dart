import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'settings_nav.dart';
import 'settings_section_page.dart';

/// 手机端的设置：一级七行，点进去是各自的整页（M6-C C1，从四行扩到七行）。
///
/// 为什么不再是一长条 ListView：全塞一页要滚很久，而且 `SyncSection` 自带
/// `SingleChildScrollView`，嵌在 ListView 里是「滚动套滚动」。二级页各自独立滚动，
/// 顶栏写节名，所以节组件用 `showTitle: false` 不再自绘同名标题。
///
/// 行的内容与顺序全部来自 [settingsEntries]：桌面对话框左栏读同一份，
/// 两边不会再各写一遍、顺序漂掉。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.s8),
      children: <Widget>[
        for (final SettingsEntry entry in settingsEntries())
          _NavRow(entry: entry),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.entry});

  final SettingsEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return ListTile(
      key: ValueKey<String>(entry.rowKey),
      leading: Icon(entry.icon, size: 22, color: colors.textSecondary),
      title: Text(entry.title,
          style: AppTypography.body.copyWith(color: colors.textPrimary)),
      subtitle: Text(entry.subtitle,
          style: AppTypography.meta.copyWith(color: colors.textFaint)),
      trailing: Icon(Icons.chevron_right, size: 20, color: colors.textFaint),
      onTap: () => pushSettingsSection(context,
          title: entry.title, content: entry.content),
    );
  }
}

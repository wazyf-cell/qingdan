import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'about_section.dart';
import 'appearance_section.dart';
import 'general_section.dart';
import 'sync_section.dart';

/// 手机端的设置：一级只有四行，点进去是各自的整页（2026-10-18 用户改的形态）。
///
/// 为什么不再是一长条 ListView：四节全塞一页要滚很久，而且 `SyncSection` 自带
/// `SingleChildScrollView`，嵌在 ListView 里是「滚动套滚动」。二级页各自独立滚动，
/// 顶栏写节名，所以节组件用 `showTitle: false` 不再自绘同名标题。
///
/// 桌面仍用 `settings_dialog.dart` 那个左导航右内容的对话框：640×440 放得下，
/// 而且它没有"点进去"这一说。节组件两端共用，不复制。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.s8),
      children: <Widget>[
        _NavRow(
          rowKey: 'settings-appearance',
          icon: Icons.palette_outlined,
          title: '外观',
          subtitle: '主题：浅色 / 深色 / 跟随系统',
          page: const _AppearancePage(),
        ),
        _NavRow(
          rowKey: 'settings-sync',
          icon: Icons.cloud_outlined,
          title: '同步',
          subtitle: '地址、账号与手动同步',
          page: const _SyncPage(),
        ),
        _NavRow(
          rowKey: 'settings-general',
          icon: Icons.tune,
          title: '通用',
          subtitle: '默认打开的页面、角标',
          page: const _GeneralPage(),
        ),
        _NavRow(
          rowKey: 'settings-about',
          icon: Icons.info_outline,
          title: '关于',
          subtitle: '版本与数据存放',
          page: const _AboutPage(),
        ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
  });

  final String rowKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return ListTile(
      key: ValueKey<String>(rowKey),
      leading: Icon(icon, size: 22, color: colors.textSecondary),
      title: Text(title,
          style: AppTypography.body.copyWith(color: colors.textPrimary)),
      subtitle: Text(subtitle,
          style: AppTypography.meta.copyWith(color: colors.textFaint)),
      trailing: Icon(Icons.chevron_right, size: 20, color: colors.textFaint),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (BuildContext _) => page),
      ),
    );
  }
}

/// 二级页外壳：只有顶栏标题 + 一节内容。顶栏写节名，内容不再自绘标题。
class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

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
        titleTextStyle: AppTypography.pageTitle.copyWith(
            fontSize: 17, color: colors.textPrimary),
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimens.panelPadding),
        child: child,
      ),
    );
  }
}

class _AppearancePage extends StatelessWidget {
  const _AppearancePage();

  @override
  Widget build(BuildContext context) => const SettingsSectionPage(
      title: '外观', child: AppearanceSection(showTitle: false));
}

class _SyncPage extends StatelessWidget {
  const _SyncPage();

  @override
  Widget build(BuildContext context) => const SettingsSectionPage(
      title: '同步', child: SyncSection(showTitle: false));
}

class _GeneralPage extends StatelessWidget {
  const _GeneralPage();

  @override
  Widget build(BuildContext context) => const SettingsSectionPage(
      title: '通用', child: GeneralSection(showTitle: false));
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) => const SettingsSectionPage(
      title: '关于', child: AboutSection(showTitle: false));
}

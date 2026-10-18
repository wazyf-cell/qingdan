import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'about_section.dart' show kAppVersion;
import 'notify_section.dart';
import 'permissions_sheet.dart';
import 'settings_section_page.dart';

/// 设置 · 通用节（M6-C C1 重排 + C3 权限入口 + E1/E2 两个占位）。
///
/// 原来这里的两项（默认页签、角标）其实是「界面表现」，已挪到外观节；
/// 通用节现在管的是**跟系统打交道**的事：通知权限、后台与省电、语言、更新。
class GeneralSection extends StatelessWidget {
  const GeneralSection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('通用',
              style:
                  AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
        ],
        ListTile(
          key: const ValueKey<String>('general-notify-page'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('通知权限与提醒',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: const Text('系统通知开关、提醒档位与免打扰',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => pushSettingsSection(context,
              title: '通知', content: NotifySection.new),
        ),
        ListTile(
          key: const ValueKey<String>('general-permissions'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('后台与省电',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: const Text('通知设置 / 电池优化 / 应用详情，以及自启动的说明',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => showPermissionsSheet(context),
        ),
        // E2：语言整行禁用。做半套 i18n 比不做更糟——切了语言只有一半界面跟着变。
        ListTile(
          key: const ValueKey<String>('settings-language'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          enabled: false,
          title: Text('语言',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: const Text('简体中文 · 英文版尚未制作',
              style: AppTypography.meta),
          trailing: _Soon(colors: colors),
        ),
        // E1：占位**不发任何网络请求**（联网只会得到一个失败提示，反而像功能坏了）。
        ListTile(
          key: const ValueKey<String>('settings-update'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('检查更新',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: Text('当前 v$kAppVersion · 更新源尚未配置',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => _showUpdateNotice(context),
        ),
      ],
    );
  }

  Future<void> _showUpdateNotice(BuildContext context) => showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('检查更新'),
          content: Text(
              '当前版本 v$kAppVersion。更新源尚未配置：'
              '本项目的更新将从 GitHub Releases 拉取，等仓库发布第一个 Release 后启用。',
              style: AppTypography.body),
          actions: <Widget>[
            TextButton(
              key: const ValueKey<String>('update-ok'),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
}

/// 「即将推出」小标签：占位行不能只靠置灰让人猜它是坏了还是没做。
class _Soon extends StatelessWidget {
  const _Soon({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s8, vertical: AppDimens.s4),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      ),
      child: Text('即将推出',
          style: AppTypography.meta.copyWith(
              fontSize: 10, color: colors.textFaint)),
    );
  }
}

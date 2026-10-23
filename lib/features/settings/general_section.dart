import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'add_widget_sheet.dart';
import 'notify_section.dart';
import 'permissions_sheet.dart';
import 'settings_section_page.dart';
import 'update_rows.dart';

/// 设置 · 通用节（M6-C C1 重排 + C3 权限入口 + E2 语言占位）。
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
              title: '通知', content: (bool showTitle) => NotifySection(showTitle: showTitle)),
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
        // v1.0.6：桌面小组件入口。副标题如实写「系统会确认」——requestPinAppWidget
        // 做不到静默添加，写成「一键添加」就是在替系统许诺。
        ListTile(
          key: const ValueKey<String>('settings-add-widget'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('添加小组件',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: const Text('清单 / 课表 / 学习通放到桌面（系统会确认）',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => showAddWidgetSheet(context),
        ),
        // E2：语言整行禁用。做半套 i18n 比不做更糟——切了语言只有一半界面跟着变。
        //
        // 2026-10-19 去掉「英文版尚未制作 · 即将推出」这句：需求规格书、项目概览、
        // 「明确不做」清单里**都没有多语言这一项**，是这句占位文案自己造出了一个
        // 「欠着的基本功能」的错觉（用户据此问「中英文都有吧」）。禁用是真的，
        // 「即将推出」不是——没有排期的事不许写在界面上。
        ListTile(
          key: const ValueKey<String>('settings-language'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          enabled: false,
          title: Text('语言',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: const Text('简体中文（本应用只做简体中文）',
              style: AppTypography.meta),
        ),
        // E1 占位已在 v1.0.2 换成真控件：一行查 GitHub Releases，一行跳仓库。
        const UpdateRows(),
      ],
    );
  }
}

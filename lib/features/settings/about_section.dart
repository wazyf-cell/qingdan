import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'help_section.dart';
import 'settings_section_page.dart';

/// 与 `pubspec.yaml` 的 `version:` 手工同步。
///
/// 不引 `package_info_plus`（本轮定死「不新增依赖」），代价是它是个手抄常量，
/// 所以 `test/app_version_test.dart` 直接读 pubspec 比对：改了版本号忘了改这里，
/// 那条测试就红——留一个永远显示 0.1.0 的死字符串比不显示更糟。
const String kAppVersion = '1.0.0';

/// 设置 · 关于节（M5 定案第 13 条 + M6-C C1 / C6 / E1）。
class AboutSection extends StatelessWidget {
  const AboutSection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('关于',
              style:
                  AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
        ],
        Row(
          children: <Widget>[
            Text('清单',
                style:
                    AppTypography.body.copyWith(color: colors.textPrimary)),
            const Spacer(),
            Text('v$kAppVersion',
                key: const ValueKey<String>('app-version'),
                style: AppTypography.meta.copyWith(color: colors.textSecondary)),
          ],
        ),
        // E1：更新通道没配就明说，别留一个看起来会自己更新的版本号。
        Text('更新通道：未配置',
            style: AppTypography.meta.copyWith(color: colors.textFaint)),
        const SizedBox(height: AppDimens.s12),
        Text(
            '任务、清单与课表都存在这台设备的本地数据库里；开了同步，才把改动写进'
            '你自己配置的那个目录（本地文件夹或 WebDAV）。项目里没有、也不会自建任何服务器。',
            style: AppTypography.meta
                .copyWith(color: colors.textSecondary, height: 1.5)),
        const SizedBox(height: AppDimens.s8),
        Text('学习通待办是登录状态下现拉的只读快照，不落本地库、不参与同步。',
            style: AppTypography.meta
                .copyWith(color: colors.textFaint, height: 1.5)),
        const SizedBox(height: AppDimens.s16),
        ListTile(
          key: const ValueKey<String>('settings-help'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('使用说明',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: const Text('四个页签怎么用、怎么导课表、提醒为什么有时不响',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => pushSettingsSection(context,
              title: '使用说明', content: (bool showTitle) => HelpSection(showTitle: showTitle)),
        ),
        ListTile(
          key: const ValueKey<String>('settings-licenses'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('开源许可',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: const Text('本应用用到的第三方依赖的许可证',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => showLicensePage(
            context: context,
            applicationName: '清单',
            applicationVersion: 'v$kAppVersion',
          ),
        ),
      ],
    );
  }
}

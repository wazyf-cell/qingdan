import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/platform/system_intents.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'package:qingdan/update/install_policy.dart';
import 'package:qingdan/update/update_checker.dart' show kRepoUrl;

import 'help_section.dart';
import 'licenses_page.dart';
import 'settings_section_page.dart';

/// 与 `pubspec.yaml` 的 `version:` 手工同步。
///
/// 不引 `package_info_plus`（本轮定死「不新增依赖」），代价是它是个手抄常量，
/// 所以 `test/app_version_test.dart` 直接读 pubspec 比对：改了版本号忘了改这里，
/// 那条测试就红——留一个永远显示 0.1.0 的死字符串比不显示更糟。
const String kAppVersion = '1.0.13';

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
        // v1.0.2：更新通道从「未配置」变成真通道，入口在 设置 → 通用。
        Text('更新通道：GitHub Releases（设置 → 通用 → 检测更新）',
            style: AppTypography.meta.copyWith(color: colors.textFaint)),
        const SizedBox(height: AppDimens.s8),
        // 能不能覆盖安装只取决于签名。这段与检测更新弹层、发布页正文共用同一份文字，
        // 之前三处各写各的，结果发布页说「直接覆盖」，真机上正好反过来。
        Text(kInstallPolicyText,
            key: const ValueKey<String>('about-install-policy'),
            style: AppTypography.meta
                .copyWith(color: colors.textFaint, height: 1.5)),
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
        const SizedBox(height: AppDimens.s8),
        Text(
            '课表仅作参考，可能因教务调整而更新不及时；实时信息请以「蓝航APP」或学校教务系统为准。'
            '本应用只适配南昌航空大学强智教务，其他学校需自行 fork 或改源码。',
            key: const ValueKey<String>('about-disclaimer'),
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
          key: const ValueKey<String>('settings-issues'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('问题与建议',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: const Text('GitHub Issues；合适的建议会采用',
              style: AppTypography.meta),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _openIssues(context),
        ),
        ListTile(
          key: const ValueKey<String>('settings-licenses'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('开源许可',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: const Text('应用许可证、上游来源与第三方依赖',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => showLicensesPage(context),
        ),
      ],
    );
  }

  Future<void> _openIssues(BuildContext context) async {
    final bool ok = await SystemIntents.openUrl('$kRepoUrl/issues');
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('打不开浏览器。地址是 $kRepoUrl/issues')),
    );
  }
}

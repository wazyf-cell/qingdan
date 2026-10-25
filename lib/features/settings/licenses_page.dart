import 'package:flutter/material.dart';

import 'package:qingdan/platform/system_intents.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'package:qingdan/update/update_checker.dart' show kRepoUrl;

import 'about_section.dart' show kAppVersion;

/// 开源许可整页：先用人话讲清本应用与上游来源，再给完整第三方许可证的入口。
///
/// 原来的 `showLicensePage` 直接抛出一长串英文依赖条目，既没有本应用自己的
/// AGPL 说明，也看不出哪些是移植来源。完整法律文本仍保留在 Flutter 的
/// LicensePage 里，这里只负责把结构和入口做清楚。
Future<void> showLicensesPage(BuildContext context) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext _) => const LicensesPage(),
    ));

class LicensesPage extends StatelessWidget {
  const LicensesPage({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final bool ok = await SystemIntents.openUrl(url);
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('打不开浏览器。地址是 $url')),
    );
  }

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
        titleTextStyle: AppTypography.pageTitle
            .copyWith(fontSize: 17, color: colors.textPrimary),
        title: const Text('开源许可'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.divider),
        ),
      ),
      body: ListView(
        key: const ValueKey<String>('licenses-page'),
        padding: const EdgeInsets.all(AppDimens.panelPadding),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('清单 v$kAppVersion',
                      style: AppTypography.panelTitle
                          .copyWith(color: colors.textPrimary)),
                  const SizedBox(height: AppDimens.s4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.s8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.accentFaint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('GNU AGPL-3.0-or-later',
                        style: AppTypography.meta
                            .copyWith(color: colors.accent)),
                  ),
                  const SizedBox(height: AppDimens.s8),
                  Text(
                    '本应用是自用工具，按现状提供，不附带任何担保。'
                    '可以自由使用、修改和分发；分发修改版或把它作为网络服务提供时，'
                    '需要继续使用 AGPL-3.0-or-later 并提供对应源码。',
                    style: AppTypography.body.copyWith(
                        color: colors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          _section(context, '上游与移植'),
          _paragraph(
              context,
              '学习通解析器的「读哪些字段、请求哪个 URL」这层接口契约，移植自 '
              'Cooanyh/chaoxing-list（AGPL-3.0-or-later）。没有拷贝它的界面、样式'
              '或上报代码。'),
          _paragraph(
              context,
              '课表导入的若干算法与结构参考了 WakeUp 课程表与 TickTick 的逆向工程资料；'
              '仓库不分发它们的二进制、原生库或资源。逐文件来源写在对应源码文件头，'
              '汇总见仓库的 NOTICE。'),
          _paragraph(
              context,
              '其余第三方依赖按 pubspec.yaml 使用；每个包自己的 LICENSE 随包分发。'
              '完整依赖许可证可以点下面的按钮查看。'),
          Wrap(
            spacing: AppDimens.s8,
            runSpacing: AppDimens.s4,
            children: <Widget>[
              TextButton.icon(
                key: const ValueKey<String>('licenses-open-repo'),
                onPressed: () => _open(context, kRepoUrl),
                icon: const Icon(Icons.code, size: 18),
                label: const Text('打开源码仓库'),
              ),
              TextButton.icon(
                key: const ValueKey<String>('licenses-open-notice'),
                onPressed: () => _open(context, '$kRepoUrl/blob/main/NOTICE'),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('查看 NOTICE'),
              ),
              TextButton.icon(
                key: const ValueKey<String>('licenses-full'),
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: '清单',
                  applicationVersion: 'v$kAppVersion',
                  applicationLegalese: 'AGPL-3.0-or-later',
                ),
                icon: const Icon(Icons.list_alt, size: 18),
                label: const Text('完整依赖许可证'),
              ),
            ],
          ),
          _section(context, '数据与隐私'),
          _paragraph(
              context,
              '本应用只适配南昌航空大学强智教务的课表页面结构，未做其他学校的适配；'
              '要用于其他学校请 fork 或拉取源码自行改装解析器。课表仅作参考，'
              '实时信息以「蓝航APP」或学校教务系统为准。'),
          _paragraph(
              context,
              '没有自建服务端，也没有账号体系。任务、清单、学期与课表默认只存在这台设备；'
              '只有你自己配置的本地文件夹或 WebDAV 会收到同步数据。'),
          _paragraph(
              context,
              '学习通会话只存系统凭据库；学习通待办是只读快照，不落本地库、不参与同步。'
              '卸载会清空本机数据库，换签名或重装前请先导出课表并完成同步。'),
          _section(context, '反馈'),
          _paragraph(
              context,
              '有问题或改进建议，请到 GitHub Issues 提；合适的会采用，但不保证全部实现。'
              '课表仅作参考，实时信息请以「蓝航APP」或学校教务系统为准。'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey<String>('licenses-open-issues'),
              onPressed: () => _open(context, '$kRepoUrl/issues'),
              icon: const Icon(Icons.bug_report_outlined, size: 18),
              label: const Text('提交 Issue'),
            ),
          ),
          const SizedBox(height: AppDimens.s16),
          Text(
            '完整法律文本以仓库 LICENSE 与各依赖自带 LICENSE 为准；本页只是导读。',
            style: AppTypography.meta.copyWith(color: colors.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: AppDimens.s16, bottom: AppDimens.s4),
        child: Text(title,
            style: AppTypography.panelTitle
                .copyWith(color: AppColors.of(context).textPrimary)),
      );

  Widget _paragraph(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.s8),
        child: Text(text,
            style: AppTypography.meta.copyWith(
                color: AppColors.of(context).textSecondary, height: 1.45)),
      );
}

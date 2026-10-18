import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 与 `pubspec.yaml` 的 `version:` 手工同步。
///
/// 不引 `package_info_plus`（本轮定死「不新增依赖」），代价是它是个手抄常量，
/// 所以 `test/app_version_test.dart` 直接读 pubspec 比对：改了版本号忘了改这里，
/// 那条测试就红——留一个永远显示 0.1.0 的死字符串比不显示更糟。
const String kAppVersion = '1.0.0';

/// 设置 · 关于节（M5 定案第 13 条）。只说两件事：版本号与数据到底在哪儿。
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
      ],
    );
  }
}

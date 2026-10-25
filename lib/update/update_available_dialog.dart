import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'release_notes_text.dart';
import 'update_checker.dart';
import 'update_install_button.dart';

/// 冷启动自动查到新版本时弹的公告（v1.0.10 小更新）。
///
/// 关掉（按钮 / 点框外 / 返回）就记住这个版本，下一次冷启动不再弹；
/// 将来出现更新的版本仍会再弹。
Future<void> showUpdateAvailableDialog(
  BuildContext context, {
  required String currentVersion,
  required ReleaseInfo release,
  UpdateChecker? checker,
}) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext _) => UpdateAvailableDialog(
        currentVersion: currentVersion,
        release: release,
        checker: checker,
      ),
    );

class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.currentVersion,
    required this.release,
    this.checker,
  });

  final String currentVersion;
  final ReleaseInfo release;
  final UpdateChecker? checker;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String? notes = dialogReleaseNotes(release.notes);
    return AlertDialog(
      key: const ValueKey<String>('update-available-dialog'),
      title: Text('发现新版本 v${release.version}'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('当前 v$currentVersion',
                  style: AppTypography.meta
                      .copyWith(color: colors.textFaint)),
              const SizedBox(height: AppDimens.s8),
              Text(
                notes ?? '新版本已发布，点下面「下载并安装」即可更新。',
                key: const ValueKey<String>('update-available-notes'),
                style: AppTypography.body.copyWith(
                    color: colors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppDimens.s12),
              UpdateInstallButton(
                key: const ValueKey<String>('update-available-install'),
                currentVersion: currentVersion,
                release: release,
                checker: checker,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('update-available-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

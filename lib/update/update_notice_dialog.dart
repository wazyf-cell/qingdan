/// 「本次更新内容」弹层（v1.0.3）：升级后第一次启动时把这一版改了什么说清楚。
///
/// 用对话框而不是横幅：横幅要占掉清单顶部一行，看完还得手动关；而这条消息
/// 一辈子只该出现一次，用弹层最省事。它**不是确认框**——点框外、按返回都能关掉，
/// 关掉就等于看过了，不给用户「必须先点某个按钮」的负担。
library;

import 'package:flutter/material.dart';

import 'package:qingdan/platform/system_intents.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'package:qingdan/update/install_policy.dart';
import 'package:qingdan/update/release_notes.dart';
import 'package:qingdan/update/update_checker.dart' show kRepoUrl;
import 'package:qingdan/update/update_install_button.dart';

/// 弹出本版说明。返回的 Future 在弹层关闭（含点框外/返回）后完成，
/// 调用方据此才写「已看过」——中途被杀掉下次还会再弹，宁可多弹一次也别漏。
Future<void> showUpdateNotice(BuildContext context, {required String version}) =>
    showDialog<void>(
      context: context,
      // 显式写出来：这是「顺手看一眼」的消息，遮罩可关是有意为之，不是默认值碰巧。
      barrierDismissible: true,
      builder: (BuildContext _) => UpdateNoticeDialog(
        version: version,
        notes: releaseNotesFor(version),
      ),
    );

class UpdateNoticeDialog extends StatefulWidget {
  const UpdateNoticeDialog({super.key, required this.version, this.notes});

  final String version;
  final String? notes;

  @override
  State<UpdateNoticeDialog> createState() => _UpdateNoticeDialogState();
}

class _UpdateNoticeDialogState extends State<UpdateNoticeDialog> {
  /// 「打不开」的本地回执。**不用 SnackBar**：它会画在弹层退场之后没人看的那一层
  /// （同一课在课表弹层与设置页栽过两次，见 `update_rows.dart` 的 _said）。
  String? _said;

  Future<void> _openRepo() async {
    final bool ok = await SystemIntents.openUrl(kRepoUrl);
    if (ok || !mounted) return;
    setState(() => _said = '打不开浏览器。地址是 $kRepoUrl');
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String notes = widget.notes?.trim() ?? '';
    return AlertDialog(
      key: const ValueKey<String>('update-notice'),
      title: const Text('本次更新内容'),
      content: SizedBox(
        // 说明可能有好几行；框定宽度让换行位置稳定，也让长文在窄屏上能滚动，
        // 而不是把按钮挤出屏幕（Release 的 body 没有长度上限）。
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('v${widget.version}',
                        style: AppTypography.meta
                            .copyWith(color: colors.textFaint)),
                    const SizedBox(height: AppDimens.s8),
                    Text(
                      notes.isEmpty ? '本次更新没有附说明' : notes,
                      key: const ValueKey<String>('update-notice-text'),
                      style: AppTypography.body.copyWith(
                          color: colors.textSecondary, height: 1.5),
                    ),
                    if (_said != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppDimens.s8),
                        child: Text(_said!,
                            key: const ValueKey<String>(
                                'update-notice-open-failed'),
                            style: AppTypography.meta
                                .copyWith(color: colors.overdue)),
                      ),
                    const SizedBox(height: AppDimens.s8),
                    // 能不能覆盖安装取决于签名，这一段与关于页、检测更新弹层共用同一份文字。
                    Text(kInstallPolicyText,
                        key: const ValueKey<String>('update-notice-policy'),
                        style: AppTypography.meta.copyWith(
                            fontSize: 11,
                            color: colors.textFaint,
                            height: 1.4)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimens.s8),
            // 固定在正文下面：说明再长也不会把安装按钮顶到屏幕外。
            UpdateInstallButton(currentVersion: widget.version),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('update-notice-repo'),
          onPressed: _openRepo,
          child: const Text('查看发布页'),
        ),
        FilledButton(
          key: const ValueKey<String>('update-notice-ok'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

/// 首启引导（M6-C6，用户裁决 Q26）。
///
/// **用对话框而不是系统通知**：首启时通知权限还没授予，发通知等于石沉大海
/// （需求原文「弹通知提示」的不可行之处）。`main.dart` 在首帧后调一次
/// [maybeShowFirstRunGuide]；两个按钮都把 `ui.guideSeen` 置 true，「以后再说」
/// 也不再弹——所以遮罩点不掉（`barrierDismissible: false`），不给第三条静默路径。
/// 框里一次只说一件事，不掺「同步未配置」之类的告警。
library;

import 'package:flutter/material.dart';

import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'help_section.dart' show pushHelpPage;

enum _Choice { later, openHelp }

/// `ui.guideSeen == false` 时弹欢迎框；看过（两个按钮任点一个）就永远不再弹。
Future<void> maybeShowFirstRunGuide(
    BuildContext context, SettingsModel settings) async {
  if (settings.guideSeen) return;
  // 弹层退场时本 widget 可能已经不在树里，先抓住 Navigator。
  final NavigatorState nav = Navigator.of(context, rootNavigator: true);
  final AppColors colors = AppColors.of(context);
  final _Choice? choice = await showDialog<_Choice>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) => AlertDialog(
      key: const ValueKey<String>('first-run-guide'),
      title: const Text('欢迎使用清单'),
      content: Text(
        '首次使用建议先看一眼「使用说明」（设置 → 关于 → 使用说明），'
        '里面有登录学习通、导入课表、设置提醒的做法。',
        style: AppTypography.body
            .copyWith(color: colors.textSecondary, height: 1.5),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('guide-later'),
          onPressed: () => Navigator.of(ctx).pop(_Choice.later),
          child: const Text('以后再说'),
        ),
        FilledButton(
          key: const ValueKey<String>('guide-open-help'),
          onPressed: () => Navigator.of(ctx).pop(_Choice.openHelp),
          child: const Text('去看使用说明'),
        ),
      ],
    ),
  );
  await settings.setGuideSeen(true);
  if (choice != _Choice.openHelp) return;
  if (nav.mounted) {
    await pushHelpPage(nav.context);
    return;
  }
  // 宿主已经不在了（测试里整个树被拆掉）：不报错，交给下次从「关于」进。
}

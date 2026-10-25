import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/settings/about_section.dart' show kAppVersion;

import 'update_available_dialog.dart';
import 'update_checker.dart';

/// 已关闭过的「新版本」列表：同一个版本只弹一次，出现更新的版本还会弹。
const String kDismissedUpdateVersionsKey = 'app.dismissedUpdateVersions';

typedef UpdateDialogShower = Future<void> Function(
  BuildContext context,
  String currentVersion,
  ReleaseInfo latest,
  UpdateChecker checker,
);

/// 冷启动自动检查一次 GitHub Releases；有新版本且没被关过就弹公告。
///
/// 只由根组件在**进程启动**时调用一次：从后台切回来不会重复查、也不会重复弹。
/// 任何失败（无网络、GitHub 拦请求、解析不了）都静默——这是附加提醒，
/// 不该在启动路径上甩一个错误框。
Future<void> maybeShowUpdateOnLaunch(
  BuildContext context, {
  UpdateChecker? checker,
  String currentVersion = kAppVersion,
  SharedPreferences? prefs,
  UpdateDialogShower? showDialogFn,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final UpdateChecker c = checker ?? UpdateChecker();
    final UpdateResult r = await c.check(currentVersion);
    if (r.status != UpdateStatus.available || !context.mounted) return;
    // 检查期间用户可能已经进了某个页面/开着别的弹层：这次不叠一个公告上去。
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final SharedPreferences p =
        prefs ?? await SharedPreferences.getInstance();
    final ReleaseInfo latest = r.latest!;
    final List<String> dismissed =
        p.getStringList(kDismissedUpdateVersionsKey) ?? const <String>[];
    if (dismissed.contains(latest.version)) return;
    if (!context.mounted) return;

    await (showDialogFn ?? _showDialog)(
        context, currentVersion, latest, c);
    // 关掉（含点框外/返回）才记：弹层还开着时被杀掉，下次启动还会提醒。
    await p.setStringList(
      kDismissedUpdateVersionsKey,
      <String>{...dismissed, latest.version}.toList()..sort(),
    );
  } catch (e) {
    debugPrint('启动检测更新失败（静默）：${e.runtimeType}');
  }
}

Future<void> _showDialog(BuildContext context, String currentVersion,
        ReleaseInfo latest, UpdateChecker checker) =>
    showUpdateAvailableDialog(context,
        currentVersion: currentVersion,
        release: latest,
        checker: checker);

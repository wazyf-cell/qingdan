// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 升级后首次启动的一次性提醒（v1.0.3）。
///
/// 判据是 SharedPreferences 里记的「上次看过的版本」和当前版本是否不同；
/// 这一格为空时再问系统「这个包是装的还是更新的」（1.0.2 没写过这一格，
/// 否则升级上来的用户永远看不到说明）。
/// **不记时间戳**——时间戳既不会让语义更准，还会在用户改系统时间时把消息
/// 多弹一次（或永远不弹）。
/// 只进偏好文件、不进数据库、不参与同步：它描述的是这台设备装过哪些包。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/settings/about_section.dart' show kAppVersion;
import 'package:qingdan/platform/system_intents.dart';

import 'update_notice_dialog.dart';

/// 偏好键名是公开契约：以后要排查「为什么没弹 / 为什么老弹」，看的就是这一格。
const String kLastSeenVersionKey = 'app.lastSeenVersion';

/// 只负责「上次看过哪一版」这一格偏好的读写。
///
/// 与 `ChaoxingPrefs` 同一形状：允许注入已初始化的实例，测试才不用碰真实磁盘。
class UpdateNoticeStore {
  UpdateNoticeStore({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<String?> readLastSeen() async =>
      (await _instance()).getString(kLastSeenVersionKey);

  Future<void> writeLastSeen(String version) async {
    await (await _instance()).setString(kLastSeenVersionKey, version);
  }
}

/// 启动后（首帧之后）调一次：该弹就弹，不该弹就悄悄把当前版本记下。
///
/// [version] 与 [store] 只为测试留口子，生产调用就是 `maybeShowUpdateNotice(context)`。
Future<void> maybeShowUpdateNotice(
  BuildContext context, {
  String version = kAppVersion,
  UpdateNoticeStore? store,
  Future<bool> Function()? updatedSinceInstall,
}) async {
  final UpdateNoticeStore s = store ?? UpdateNoticeStore();
  try {
    final String? lastSeen = await s.readLastSeen();
    // 等偏好读完时树可能已经拆了（测试、极快的退出），这时候再拿 context 弹框就是错的。
    if (!context.mounted) return;
    if (lastSeen == null) {
      // 这一格为空有两种人：真·第一次装，和**从 1.0.2 升级上来**的
      // （1.0.2 还没有这个功能，从没写过它）。后者正是最该看到说明的人，
      // 所以问系统「这个包是装上的还是更新上来的」，而不是一律当全新安装。
      final bool upgraded = await (updatedSinceInstall ?? _updatedSinceInstall)();
      if (!context.mounted) return;
      // 全新安装：没有「旧版」这个参照，看到的只是一堆陌生改动。记下即可。
      if (!upgraded) {
        await s.writeLastSeen(version);
        return;
      }
    } else if (lastSeen == version) {
      return;
    }
    await showUpdateNotice(context, version: version);
    // 关闭之后才记：弹层还开着时应用被杀，下次启动会再弹一次，
    // 这比「没看到就被记成已看过、以后再也不弹」安全。
    await s.writeLastSeen(version);
  } catch (e) {
    // 弹层是锦上添花，不值得让它在启动路径上抛异常；读写失败就当这次没弹。
    debugPrint('更新说明读写失败，本次不弹：${e.runtimeType}');
  }
}

/// 安装/更新时间差超过这个宽容值才算「升级」：全新安装的两个时间戳是同一刻，
/// 但个别 ROM 会差几毫秒，不能要求严格相等。
const int kInstallSlackMs = 60 * 1000;

/// 这个包是不是「从旧版更新上来的」。拿不到时间就按全新安装处理——
/// 宁可少弹一次，也不要在第一次装应用时就甩一份「本次更新内容」。
Future<bool> _updatedSinceInstall() async {
  final ({int firstInstallTime, int lastUpdateTime})? times =
      await SystemIntents.installTimes();
  if (times == null) return false;
  return times.lastUpdateTime - times.firstInstallTime > kInstallSlackMs;
}

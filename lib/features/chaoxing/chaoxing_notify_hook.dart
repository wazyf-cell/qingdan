/// 学习通「到期提醒」的取消钩子（M6B §B4 需要，M6C 批填肉）。
///
/// 本批不装 `flutter_local_notifications` 的装配（那是 M6C §6 的范围），但退出
/// 登录这条用户路径必须**当场就有明确语义**「已排的提醒会被取消」。所以这里给
/// 一个可替换的实现位：默认无操作，C 批把 [cancelAllChaoxingNotifications]
/// 指向真正的通知服务即可，调用点一行都不用改。
library;

import 'package:flutter/foundation.dart';

typedef ChaoxingNotifyCanceller = Future<void> Function();

/// 默认实现：无操作。M6C 接线时改成 `NotificationHooks.cancelAllChaoxing`。
ChaoxingNotifyCanceller cancelAllChaoxingNotifications = () async {};

/// 退出登录时调用。日志只打这条路径本身，不打任何条目内容或凭据。
Future<void> cancelChaoxingReminders() async {
  await cancelAllChaoxingNotifications();
  debugPrint('chaoxing: 已请求取消到期提醒（未接线时为空操作）');
}

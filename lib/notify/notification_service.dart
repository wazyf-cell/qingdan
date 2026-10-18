/// 通知引擎层（M6-C2）：初始化 / 权限查询 / 「先 cancelAll 再全量重排」。
///
/// 插件 API 签名全部核对过 pub 缓存源码（本机 `F:/Code/AndroidStudio-Cache/
/// hosted/pub.dev/`：flutter_local_notifications **22.3.1** + platform_interface
/// **12.2.0**），逐条写在调用点注释里——网上大量 9.x/16.x 教程的参数名与此不同。
/// 时区（§0.2）：`initializeTimeZones()` 后**不设 local location**，排程用绝对时刻
/// `tz.TZDateTime.from(at.toUtc(), tz.UTC)`；跨夏令时会偏一小时，中国不实行夏令时、
/// 对本用户无影响，**不要为此引入 `flutter_timezone`**。闹钟用非精确模式
/// `inexactAllowWhileIdle`（§0.2.4），故不需要 `SCHEDULE_EXACT_ALARM` 权限。
/// 任何一次插件调用失败都只 `debugPrint` 不外抛：通知是增强功能，不能拖垮启动。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:qingdan/notify/reminder_plan.dart';

/// Android 通道。创建后**不要改 id**（改了旧通道会残留在系统通知设置里）。
const String kTaskChannelId = 'qingdan_task', kTaskChannelName = '清单提醒';
const String kChaoxingChannelId = 'qingdan_chaoxing',
    kChaoxingChannelName = '学习通提醒';

/// 非精确闹钟：不要换成 `exact` / `alarmClock`，那需要额外的精确闹钟权限。
const AndroidScheduleMode kAndroidScheduleMode =
    AndroidScheduleMode.inexactAllowWhileIdle;

/// 通知小图标名。插件按 **drawable/** 解析它（`...Plugin.java:855` →
/// `getIdentifier(name, DRAWABLE, packageName)`），`@mipmap/ic_launcher` 不在这个
/// 命名空间里，早前写 'ic_launcher' 的结果是通知照发、小图标空白。
/// 资源在 `res/drawable/ic_stat_qingdan.xml`（纯白剪影，Android 只认 alpha）。
const String kNotificationIcon = 'ic_stat_qingdan';

/// 通知只在 Android 生效（§0.1）。补充实测：22.3.1 带了 windows 子包，但
/// `initialize()` 在 windows 分支要求 `settings.windows != null` 否则抛
/// `ArgumentError`（L186-191），排程路径也不完整——仍按「仅 Android」接线。
bool notificationPlatformSupported() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 排下去的一条通知：[id] = 过滤后列表的下标（每次都全量重排，下标足够稳定，
/// 也不会像 hash 那样碰撞到让两条提醒互相顶掉）。
class ScheduledReminder {
  const ScheduledReminder(this.id, this.reminder);
  final int id;
  final Reminder reminder;
}

/// 引擎依赖的最小能力面：真实实现碰插件，测试装假的来断言调用序列与 id。
abstract class NotificationSink {
  Future<void> initialize({DidReceiveNotificationResponseCallback? onResponse});
  Future<bool> requestPermission();
  Future<bool> isEnabled();
  Future<void> cancelAll();
  Future<void> schedule(ScheduledReminder item);
}

/// 排程策略：一律全量重排，不做增量 diff（通知只有几十条，全量更不容易出错）。
class NotificationService {
  NotificationService({NotificationSink? sink, bool Function()? supported})
      : _sink = sink ?? PluginNotificationSink(),
        _supported = supported ?? notificationPlatformSupported;
  final NotificationSink _sink;
  final bool Function() _supported;
  bool get supported => _supported();

  /// 返回通知功能是否可用；异常（Windows / 平台不支持 / 权限被拒）都吞掉。
  Future<bool> initialize({DidReceiveNotificationResponseCallback? onResponse}) =>
      _bool(() async {
        await _sink.initialize(onResponse: onResponse);
        return true;
      }, '通知初始化');

  /// 权限请求时机：首次进入「通知」二级页时调，不在应用启动时调（§C2.5）。
  Future<bool> requestPermission() =>
      _bool(() => _sink.requestPermission(), '通知权限请求');

  Future<bool> notificationsEnabled() =>
      _bool(() => _sink.isEnabled(), '通知状态查询');

  Future<void> cancelAll() async {
    if (!supported) return;
    try {
      await _sink.cancelAll();
    } catch (e) {
      debugPrint('取消全部通知失败：${e.runtimeType}');
    }
  }

  /// 一律先 `cancelAll()` 再逐条重排，返回真正排下去的条数。下标即 id，所以必须
  /// **先滤掉已过去的**（插件 `validateDateIsInTheFuture` 对过去时刻抛异常），
  /// 再取前 [kMaxScheduledReminders] 条，id 才连续。
  Future<int> rescheduleAll(List<Reminder> reminders) async {
    if (!supported) return 0;
    final DateTime now = DateTime.now();
    final List<Reminder> upcoming = <Reminder>[
      for (final Reminder r in reminders)
        if (r.at.isAfter(now)) r,
    ].take(kMaxScheduledReminders).toList(growable: false);
    await cancelAll();
    int ok = 0;
    for (int i = 0; i < upcoming.length; i++) {
      try {
        await _sink.schedule(ScheduledReminder(i, upcoming[i]));
        ok++;
      } catch (e) {
        debugPrint('第 $i 条提醒排程失败：${e.runtimeType}');
      }
    }
    return ok;
  }

  /// 唯一的异常出口：不支持就返回 false，异常只打类型（原文可能含用户数据）。
  Future<bool> _bool(Future<bool> Function() body, String what) async {
    if (!supported) return false;
    try {
      return await body();
    } catch (e) {
      debugPrint('$what 失败：${e.runtimeType}');
      return false;
    }
  }
}

/// 真机用的 [NotificationSink]：转发到 `flutter_local_notifications` 插件。
class PluginNotificationSink implements NotificationSink {
  PluginNotificationSink([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;

  /// 非 Android 返回 null（`T? resolvePlatformSpecificImplementation<T>()`）。
  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> initialize(
      {DidReceiveNotificationResponseCallback? onResponse}) async {
    tzdata.initializeTimeZones(); // 只装载时区数据库；不调 setLocalLocation（§0.2）
    // 22.3.1: `Future<bool?> initialize({required InitializationSettings settings,
    //   DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    //   DidReceiveBackgroundNotificationResponseCallback? ...})`
    await _plugin.initialize(
      settings: const InitializationSettings(
          android: AndroidInitializationSettings(kNotificationIcon)),
      onDidReceiveNotificationResponse: onResponse,
    );
    // 22.x 只有单数版 `createNotificationChannel(AndroidNotificationChannel)`；
    // AndroidNotificationChannel(this.id, this.name, {description, importance, …})
    final AndroidFlutterLocalNotificationsPlugin? a = _android;
    await a?.createNotificationChannel(const AndroidNotificationChannel(
        kTaskChannelId, kTaskChannelName,
        description: '清单任务的到期与提前提醒', importance: Importance.high));
    await a?.createNotificationChannel(const AndroidNotificationChannel(
        kChaoxingChannelId, kChaoxingChannelName,
        description: '学习通作业与课堂活动的截止提醒', importance: Importance.high));
  }

  @override
  Future<bool> requestPermission() async =>
      // `requestNotificationsPermission()` → `Future<bool?>`：API 33+ 要
      // POST_NOTIFICATIONS，更旧的版本是 no-op。
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<bool> isEnabled() async =>
      // `areNotificationsEnabled()` → `Future<bool?>`：系统总开关与权限的综合结果。
      await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<void> cancelAll() => _plugin.cancelAll(); // `Future<void> cancelAll()`

  @override
  Future<void> schedule(ScheduledReminder item) async {
    final Reminder r = item.reminder;
    final bool fromChaoxing = r.kind == kChaoxingReminderKind;
    // 22.3.1: `Future<void> zonedSchedule({required int id, required TZDateTime
    //   scheduledDate, required NotificationDetails notificationDetails,
    //   required AndroidScheduleMode androidScheduleMode, String? title,
    //   String? body, String? payload, DateTimeComponents? matchDateTimeComponents})`
    //   —— 前四个都是 **required 命名参数**（Android 实现里那个叫 scheduleMode）。
    await _plugin.zonedSchedule(
      id: item.id,
      scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC), // §0.2 绝对时刻
      notificationDetails: NotificationDetails(
          // AndroidNotificationDetails(this.channelId, this.channelName, {...})：
          // 通道 id/名仍是位置参数；子文本字段名是 `subText`（不是 `subtext`）。
          android: AndroidNotificationDetails(
              fromChaoxing ? kChaoxingChannelId : kTaskChannelId,
              fromChaoxing ? kChaoxingChannelName : kTaskChannelName,
              importance: Importance.high,
              priority: Priority.high,
              subText: r.subtext)),
      androidScheduleMode: kAndroidScheduleMode,
      title: r.title,
      body: r.body,
      payload: r.payload,
    );
  }
}

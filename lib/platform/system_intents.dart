import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// C3 系统权限深链：把用户送去 Android 系统里应用自己改不动的那几个页面
/// （通知设置 / 电池优化白名单 / 应用详情页）。
///
/// 为什么是 MethodChannel 而不是 URL 插件：这些设置页不是 URL，只能靠原生
/// Intent 打开；而本批禁止新增 pubspec 依赖，通道属于平台代码，不受该限制。
///
/// 契约：**四个方法都只返回 bool，永不抛异常**。设置页在 Windows 上同样会调
/// 它们，平台不支持、原生通道未注册、Intent 找不到接收方，统统折算成 false，
/// 由调用方提示「打不开，请手动到 系统设置 → 应用 → 清单 里找」。
class SystemIntents {
  SystemIntents._();

  /// 通道名与 `SystemIntents.kt` 的 CHANNEL 常量成对，改一边必须改另一边。
  static const MethodChannel _ch = MethodChannel('qingdan/system');

  /// 用 [defaultTargetPlatform] 而不是 `Platform.isAndroid`：前者能在测试里用
  /// `debugDefaultTargetPlatformOverride` 切到 Android，否则「方法名对不对、
  /// 通道到底调没调」这类断言只能在真机上过，离线测试就退化成只测 false 分支。
  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 通知设置：Android 8+ 走本应用通知页，原生侧失败回落应用详情页。
  static Future<bool> openNotificationSettings() => _invoke('openNotificationSettings');

  /// 电池优化白名单**列表页**（让用户自己把本应用打开，不是直接弹授权框）。
  static Future<bool> openBatteryOptimizationSettings() =>
      _invoke('openBatteryOptimizationSettings');

  /// 应用详情页：厂商 ROM 的自启动 / 省电入口各家路径不同，这里是不确定下的通用兜底。
  static Future<bool> openAppDetails() => _invoke('openAppDetails');

  /// 严格版通知页：Android 8 以下直接返回 false、不回落，留给调用方自己决定兜底。
  static Future<bool> openAppNotificationSettings() => _invoke('openAppNotificationSettings');

  static Future<bool> _invoke(String method) async {
    if (!_isAndroid) return false; // Windows 端也会调到这里，必须先短路再碰通道
    try {
      return await _ch.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

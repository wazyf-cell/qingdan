import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// C3 系统权限深链 + 外链跳转：把用户送去 Android 系统里应用自己改不动的地方
/// （通知设置 / 电池优化白名单 / 应用详情页 / 系统浏览器里的一个网页）。
///
/// 为什么是 MethodChannel 而不是 url_launcher：设置页根本不是 URL，只能靠原生
/// Intent 打开；既然为了它们已经开了这条通道，打开网页就顺手复用同一条，
/// 不必为「跳浏览器」这一件事再加一个 pubspec 依赖。
///
/// 契约：**所有方法都只返回 bool，永不抛异常**。设置页在 Windows 上同样会调
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

  /// 用系统浏览器打开一个网页链接（更新通道「GitHub 仓库」按钮走这里）。
  ///
  /// 只放行 http/https：链接是从 GitHub API 响应里读出来的，属于半外部输入，
  /// `file://` / `intent://` / `javascript:` 交出去就是拿用户的设备开盲盒。
  static Future<bool> openUrl(String url) {
    final String? scheme = Uri.tryParse(url)?.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return Future<bool>.value(false);
    return _invoke('openUrl', <String, String>{'url': url});
  }

  /// 安装时间与最近更新时间（毫秒时间戳）。拿不到就返回 null。
  ///
  /// 更新说明用它区分「全新安装」与「从旧版升级」：1.0.2 从没写过
  /// `app.lastSeenVersion`，只看偏好文件会把升级当成第一次装这应用。
  /// 升级时 [lastUpdateTime] 晚于 [firstInstallTime]，全新安装两者是同一刻。
  static Future<({int firstInstallTime, int lastUpdateTime})?> installTimes() async {
    if (!_isAndroid) return null;
    try {
      // 先按 Object? 取再判类型：通道那头回错形状（旧版本 APK、测试假实现）
      // 不该在这里抛 TypeError，调用方只需要「拿不到」这一个结论。
      final Object? raw = await _ch.invokeMethod<Object?>('installTimes');
      if (raw is! Map) return null;
      final Object? first = raw['firstInstallTime'];
      final Object? last = raw['lastUpdateTime'];
      if (first is! int || last is! int) return null;
      return (firstInstallTime: first, lastUpdateTime: last);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 本机首选 ABI（`Build.SUPPORTED_ABIS[0]`，例如 `arm64-v8a`）。拿不到返回 null。
  static Future<String?> deviceAbi() async {
    if (!_isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('deviceAbi');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 本应用**已安装版本**的签名证书 SHA-256（小写十六进制）；取不到返回 null。
  ///
  /// 用它和下载到的 APK 比对：不一致就说明这台设备上是另一个签名的旧包，
  /// 系统安装器只会回一句英文的 `UPDATE_INCOMPATIBLE`，不如我们提前说清楚。
  static Future<String?> packageSignature() =>
      _stringMethod('packageSignature');

  /// 一个 APK 文件的签名证书 SHA-256；文件不存在或解析失败返回 null。
  static Future<String?> apkSignature(String path) =>
      _stringMethod('apkSignature', <String, String>{'path': path});

  /// 本应用有没有「安装未知应用」的授权。Android 8 以下恒为 true。
  static Future<bool> canInstallPackages() => _invoke('canInstallPackages');

  /// 打开本应用的「安装未知应用」系统页。允许后系统不会回调，让用户回来再点一次。
  static Future<bool> openInstallPermission() => _invoke('openInstallPermission');

  /// 调起系统安装器（APK 走 FileProvider）。用户还要在系统界面点一次「安装」。
  static Future<bool> installApk(String path) =>
      _invoke('installApk', <String, String>{'path': path});

  static Future<String?> _stringMethod(String method,
      [Map<String, String>? args]) async {
    if (!_isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> _invoke(String method, [Map<String, String>? args]) async {
    if (!_isAndroid) return false; // Windows 端也会调到这里，必须先短路再碰通道
    try {
      return await _ch.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

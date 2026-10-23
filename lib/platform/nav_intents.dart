import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 长按快捷方式 → 应用内路由的通道（v1.0.6）。
///
/// 通道名与 `AppNav.kt` 的 `CHANNEL` 常量成对，改一边必须改另一边。
/// 契约与 `SystemIntents` 相同：**永不抛异常**，拿不到路由就返回 null / 不回调
/// —— Windows 与测试环境没有这个通道，不能因此打断启动。
class NavIntents {
  NavIntents._();

  static const MethodChannel _ch = MethodChannel('qingdan/nav');

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 冷启动时快捷方式带来的路由；没有则 null。
  ///
  /// 必须在 [setHandler] 之后、首帧画完后调用一次：原生在收到这次调用前会把
  /// 路由暂存，所以「先启动、后问」不会丢。
  static Future<String?> initialRoute() async {
    if (!_isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('initialRoute');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 应用已在后台时，点快捷方式触发的路由回调。
  static void setHandler(void Function(String route) onRoute) {
    _ch.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'route' && call.arguments is String) {
        onRoute(call.arguments as String);
      }
      return null;
    });
  }
}

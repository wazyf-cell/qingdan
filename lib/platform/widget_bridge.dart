import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 桌面小组件 → 原生的桥（v1.0.6）。
///
/// 只做三件事：让桌面重画一次、问本机桌面支不支持「直接钉一个卡片」、
/// 发起钉卡片请求。**永不抛异常**：Windows / 测试环境没有这条通道，
/// 设置页照常显示，只是点了没效果——调用方要按 bool 提示。
class WidgetBridge {
  WidgetBridge._();

  static const MethodChannel _ch = MethodChannel('qingdan/widgets');

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 应用内数据变了 → 让桌面上三个卡片重画。
  static Future<void> refresh() async {
    if (!_isAndroid) return;
    try {
      await _ch.invokeMethod<void>('refreshWidgets');
    } on PlatformException {
      // 组件被移除 / 通道缺失都不影响应用内功能。
    } on MissingPluginException {
      // 同上。
    }
  }

  /// 本机桌面是否支持 `requestPinAppWidget`。
  static Future<bool> isPinSupported() => _invoke('isPinSupported');

  /// 请求把某个卡片钉到桌面（系统仍会弹一次确认）。
  ///
  /// [provider] 取 `today` / `course` / `chaoxing`。
  static Future<bool> pin(String provider) =>
      _invoke('pinWidget', <String, String>{'provider': provider});

  /// 打开系统桌面（钉卡片不受支持时的兜底：用户要自己去长按空白处）。
  static Future<bool> goHome() => _invoke('goHome');

  static Future<bool> _invoke(String method, [Map<String, String>? args]) async {
    if (!_isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

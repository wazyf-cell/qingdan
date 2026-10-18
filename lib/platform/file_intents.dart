import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// M6-D §9.2 导出落地：把导出的字节写到磁盘。
///
/// 通道名与 `FileIntents.kt` 的 CHANNEL 常量成对（`qingdan/file`），改一边必须改另一边。
/// 为什么 Android 不用 `getSaveLocation`：`file_selector_android 0.5.2+11` 没实现它，
/// 直接调会抛（§9.2 定案），只能走 MethodChannel + `ACTION_CREATE_DOCUMENT`。
///
/// **null 与异常不是一回事**：`createDocument` 返回 null == 用户在系统「另存为」里
/// 按了取消，调用方必须什么都不写；原生侧真正不可用（无接收方 / 通道异常）才抛，
/// 调用方据此才允许落 `writeAppDocument` 兜底。把取消当故障会偷偷生成用户没同意的
/// 文件，把故障当取消就是第二个「点了没反应」事故。
class FileIntents {
  FileIntents._();

  static const MethodChannel _ch = MethodChannel('qingdan/file');

  /// 用 [defaultTargetPlatform] 而不是 `Platform.isAndroid`：前者能在测试里用
  /// `debugDefaultTargetPlatformOverride` 切到 Android（同 `system_intents.dart`）。
  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 拉起系统「另存为」。返回 SAF content URI（Android）或绝对路径（桌面）；
  /// **null = 用户取消**。Android 原生不可用抛 PlatformException / MissingPluginException，
  /// 非 Android 分支通道未注册（测试环境）一律返回 null、不抛。
  static Future<String?> createDocument({
    required String mime,
    required String fileName,
  }) async {
    if (_isAndroid) {
      return _ch.invokeMethod<String>('createDocument', <String, Object?>{
        'mime': mime,
        'fileName': fileName,
      });
    }
    try {
      // 桌面没有 mime 参数可传（getSaveLocation 不收），扩展名已经写进 fileName。
      final FileSaveLocation? loc =
          await getSaveLocation(suggestedName: fileName);
      return loc?.path;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 把 [bytes] 写进 [createDocument] 返回的位置。失败（只读 URI、provider 抽风、
  /// 通道异常）一律折算成 false，由调用方决定是否落兜底，不向上抛。
  static Future<bool> writeToUri(String uri, Uint8List bytes) async {
    if (_isAndroid) {
      try {
        return await _ch.invokeMethod<bool>('writeToUri',
                <String, Object?>{'uri': uri, 'bytes': bytes}) ??
            false;
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return false;
      }
    }
    try {
      await File(uri).writeAsBytes(bytes); // Windows 拿到的就是绝对路径
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// 兜底路径：写 `应用文档目录/exports/<fileName>`，返回**完整路径**（界面要原样
  /// 显示给用户 + 「复制路径」）。失败返回 null。[documentsPathOverride] 仅供测试
  /// 注入临时目录，生产调用不要传（所以不加 `@visibleForTesting`：生产路径真的会调它）。
  static Future<String?> writeAppDocument({
    required String fileName,
    required Uint8List bytes,
    String? documentsPathOverride,
  }) async {
    try {
      final String base = documentsPathOverride ??
          (await getApplicationDocumentsDirectory()).path;
      final Directory exports = Directory('$base/exports');
      await exports.create(recursive: true);
      final File file = File('${exports.path}/$fileName');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      // path_provider 未注册（测试）、磁盘只读、文件名被系统拒绝——统统 null，
      // 由界面显示「导出失败」，不让异常穿透到 UI 层。
      return null;
    }
  }
}

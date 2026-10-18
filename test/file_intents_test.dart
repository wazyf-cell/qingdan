import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/platform/file_intents.dart';

/// §9.2 平台通道的离线彩排：断言**方法名、参数、以及取消/异常两条出口**。
/// Kotlin 侧行为不在这里验证（未编译未真机，见交付说明）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel ch = MethodChannel('qingdan/file');
  final List<MethodCall> calls = <MethodCall>[];

  void mockAndroid(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (MethodCall call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
    debugDefaultTargetPlatformOverride = null;
  });

  final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);

  group('Android 走 qingdan/file 通道', () {
    test('createDocument 方法名与 mime/fileName 参数原样送达', () async {
      mockAndroid((_) => 'content://document/7');
      final String? uri = await FileIntents.createDocument(
          mime: 'text/calendar', fileName: '2026_秋季.ics');
      expect(uri, 'content://document/7');
      expect(calls.single.method, 'createDocument');
      expect(calls.single.arguments['mime'], 'text/calendar');
      expect(calls.single.arguments['fileName'], '2026_秋季.ics');
    });

    test('用户取消（原生回 null）→ null，不抛', () async {
      mockAndroid((_) => null);
      expect(
          await FileIntents.createDocument(
              mime: 'text/csv', fileName: 'a.csv'),
          isNull);
    });

    test('原生不可用（PlatformException）→ 抛给调用方，与取消区分', () async {
      mockAndroid(
          (_) => throw PlatformException(code: 'unavailable'));
      await expectLater(
          FileIntents.createDocument(mime: 'text/csv', fileName: 'a.csv'),
          throwsA(isA<PlatformException>()));
    });

    test('writeToUri 透传 uri 与字节，回传真值', () async {
      mockAndroid((MethodCall call) {
        expect(call.method, 'writeToUri');
        expect(call.arguments['uri'], 'content://document/7');
        expect(call.arguments['bytes'], bytes);
        return true;
      });
      expect(
          await FileIntents.writeToUri('content://document/7', bytes), isTrue);
    });

    test('writeToUri 原生异常 → false，不抛', () async {
      mockAndroid((_) => throw PlatformException(code: 'io'));
      expect(await FileIntents.writeToUri('content://x', bytes), isFalse);
    });
  });

  group('非 Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);

    test('createDocument 不碰通道：file_selector 未注册时返回 null 而不是抛',
        () async {
      // 测试环境没有任何插件实现；若这里去 invoke 了 qingdan/file 或抛了
      // MissingPluginException，本条必红。
      expect(
          await FileIntents.createDocument(
              mime: 'text/calendar', fileName: 'a.ics'),
          isNull);
    });

    test('writeToUri 按绝对路径直写磁盘（Windows 分支）', () async {
      final Directory tmp = Directory.systemTemp.createTempSync('qingdan_fi');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final String path = '${tmp.path}\\out.ics';
      expect(await FileIntents.writeToUri(path, bytes), isTrue);
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('writeToUri 写不进去 → false（目录不存在）', () async {
      expect(await FileIntents.writeToUri(r'D:\no_such_dir\x.ics', bytes),
          isFalse);
    });
  });

  group('writeAppDocument 兜底', () {
    test('写进 <目录>/exports/<文件名>，返回完整路径', () async {
      final Directory tmp = Directory.systemTemp.createTempSync('qingdan_app');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final String? saved = await FileIntents.writeAppDocument(
          fileName: '2026_秋季.csv',
          bytes: bytes,
          documentsPathOverride: tmp.path);
      expect(saved, isNotNull);
      expect(File(saved!).existsSync(), isTrue);
      expect(File(saved).readAsBytesSync(), bytes);
      // 必须落在 exports/ 子目录（界面展示的「完整路径」以能真的打开为准）
      expect(File(saved).parent.path.endsWith('exports'), isTrue);
      expect(saved, contains('exports'));
    });

    test('目录创建不了 → null，不抛', () async {
      // 用 Windows 非法路径字符（|）而不是「D 盘不存在的目录」：后者在
      // recursive:true 下会被当场创建出来，测不到失败分支。
      final String? saved = await FileIntents.writeAppDocument(
          fileName: 'a.csv',
          bytes: bytes,
          documentsPathOverride: r'x|y');
      expect(saved, isNull);
    });
  });
}

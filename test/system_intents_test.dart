import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/platform/system_intents.dart';

/// C3 + 更新通道验收：方法名与 Kotlin 侧的 `when` 分支一一对应、任何异常都吞成
/// false、非 Android（Windows 设置页同样会调这些方法）既不碰通道也不抛。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 通道名在此写死：实现里若改了名字，mock 就挂不上，未注册通道 → false，
  // 「方法名对不对」与「通道名对不对」是同一条契约的两端。
  const MethodChannel channel = MethodChannel('qingdan/system');
  final List<MethodCall> calls = <MethodCall>[];

  /// 装一个假原生侧：记录调用顺序，并按 [reply] 决定回执。
  void mockChannel(Object? Function(MethodCall call) reply) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply(call);
        });
  }

  void clearMock() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    clearMock();
  });

  group('Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('四个方法打到的方法名与顺序', () async {
      mockChannel((_) => true);

      await SystemIntents.openNotificationSettings();
      await SystemIntents.openBatteryOptimizationSettings();
      await SystemIntents.openAppDetails();
      await SystemIntents.openAppNotificationSettings();

      expect(
        calls.map((MethodCall c) => c.method).toList(),
        <String>[
          'openNotificationSettings',
          'openBatteryOptimizationSettings',
          'openAppDetails',
          'openAppNotificationSettings',
        ],
      );
    });

    test('原生回 true 时四个方法都返回 true', () async {
      mockChannel((_) => true);

      expect(await SystemIntents.openNotificationSettings(), isTrue);
      expect(await SystemIntents.openBatteryOptimizationSettings(), isTrue);
      expect(await SystemIntents.openAppDetails(), isTrue);
      expect(await SystemIntents.openAppNotificationSettings(), isTrue);
    });

    test('原生回 false 与回 null 都算「没打开」', () async {
      mockChannel((MethodCall c) => c.method == 'openAppDetails' ? false : null);

      expect(await SystemIntents.openAppDetails(), isFalse);
      expect(await SystemIntents.openNotificationSettings(), isFalse);
    });

    test('PlatformException 吞成 false，不冒泡到设置页', () async {
      mockChannel((_) => throw PlatformException(code: 'activity-not-found'));

      await expectLater(SystemIntents.openAppDetails(), completion(isFalse));
    });

    test('通道没人实现（MissingPluginException）同样是 false', () async {
      clearMock(); // 未注册 mock handler 的通道在测试环境里直接抛 MissingPluginException

      await expectLater(SystemIntents.openBatteryOptimizationSettings(), completion(isFalse));
    });

    test('调用不带参数——原生侧只认方法名', () async {
      mockChannel((_) => true);

      await SystemIntents.openAppDetails();

      expect(calls, hasLength(1));
      expect(calls.single.arguments, isNull);
    });

    // openUrl 是这批里唯一带参数的方法：链接来自 GitHub API 响应，属于半外部输入。
    test('openUrl 把地址原样带过去，并回传原生侧的成败', () async {
      mockChannel((_) => true);

      expect(
          await SystemIntents.openUrl('https://github.com/wazyf-cell/qingdan'),
          isTrue);
      expect(calls.single.method, 'openUrl');
      expect(calls.single.arguments,
          <String, String>{'url': 'https://github.com/wazyf-cell/qingdan'});

      mockChannel((_) => false); // 设备上没有能打开网页的应用
      expect(await SystemIntents.openUrl('https://example.com'), isFalse);
    });

    test('openUrl 只放行 http/https，其余协议一次都不碰通道', () async {
      mockChannel((_) => true);

      for (final String bad in <String>[
        'file:///data/data/com.qingdan.qingdan/files/qingdan.db',
        'content://sms/inbox',
        'intent#Intent;scheme=tel;action=android.intent.action.DIAL;end',
        'javascript:alert(1)',
        '',
      ]) {
        expect(await SystemIntents.openUrl(bad), isFalse,
            reason: '「$bad」不该被交给系统去打开');
      }
      expect(calls, isEmpty, reason: '挡协议要在碰通道之前，不是之后');
    });

    // 1.0.4：应用内下载安装。方法名与返回值形状都是 Dart↔Kotlin 的契约。
    test('更新安装的五个方法名与参数', () async {
      mockChannel((MethodCall c) => switch (c.method) {
            'deviceAbi' => 'arm64-v8a',
            'packageSignature' || 'apkSignature' => 'abc123',
            _ => true,
          });

      expect(await SystemIntents.deviceAbi(), 'arm64-v8a');
      expect(await SystemIntents.packageSignature(), 'abc123');
      expect(await SystemIntents.apkSignature('/tmp/a.apk'), 'abc123');
      expect(await SystemIntents.canInstallPackages(), isTrue);
      expect(await SystemIntents.openInstallPermission(), isTrue);
      expect(await SystemIntents.installApk('/tmp/a.apk'), isTrue);

      expect(calls.map((MethodCall c) => c.method).toList(), <String>[
        'deviceAbi',
        'packageSignature',
        'apkSignature',
        'canInstallPackages',
        'openInstallPermission',
        'installApk',
      ]);
      // 带路径的两个方法必须原样把路径带过去（原生侧靠它找文件）。
      expect((calls[2].arguments as Map<Object?, Object?>)['path'], '/tmp/a.apk');
      expect((calls[5].arguments as Map<Object?, Object?>)['path'], '/tmp/a.apk');
    });

    test('签名读不到时返回 null，而不是空串（调用方靠 null 判「比不了」）', () async {
      mockChannel((_) => null);

      expect(await SystemIntents.packageSignature(), isNull);
      expect(await SystemIntents.apkSignature('/tmp/a.apk'), isNull);
      expect(await SystemIntents.deviceAbi(), isNull);
    });
  });

  group('非 Android（显式指定平台，不靠测试主机是什么）', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);

    test('四个方法一律 false 且一次都不碰通道', () async {
      mockChannel((_) => true); // 就算原生侧说「能打开」也必须被平台短路挡在前面

      expect(await SystemIntents.openNotificationSettings(), isFalse);
      expect(await SystemIntents.openBatteryOptimizationSettings(), isFalse);
      expect(await SystemIntents.openAppDetails(), isFalse);
      expect(await SystemIntents.openAppNotificationSettings(), isFalse);
      expect(await SystemIntents.openUrl('https://github.com'), isFalse);
      expect(calls, isEmpty);
    });

    test('其它非 Android 平台（linux）也不抛', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      mockChannel((_) => true);

      await expectLater(SystemIntents.openAppDetails(), completion(isFalse));
      expect(calls, isEmpty);
    });

    test('更新安装的方法在非 Android 上返回 null/false，且不碰通道', () async {
      mockChannel((_) => true);

      expect(await SystemIntents.deviceAbi(), isNull);
      expect(await SystemIntents.packageSignature(), isNull);
      expect(await SystemIntents.apkSignature('/tmp/a.apk'), isNull);
      expect(await SystemIntents.canInstallPackages(), isFalse);
      expect(await SystemIntents.installApk('/tmp/a.apk'), isFalse);
      expect(calls, isEmpty);
    });
  });
}

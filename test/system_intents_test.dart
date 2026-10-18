import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/platform/system_intents.dart';

/// C3 验收：四个方法名与 Kotlin 侧的 `when` 分支一一对应、任何异常都吞成 false、
/// 非 Android（Windows 设置页同样会调这些方法）既不碰通道也不抛。
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
  });

  group('非 Android（显式指定平台，不靠测试主机是什么）', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);

    test('四个方法一律 false 且一次都不碰通道', () async {
      mockChannel((_) => true); // 就算原生侧说「能打开」也必须被平台短路挡在前面

      expect(await SystemIntents.openNotificationSettings(), isFalse);
      expect(await SystemIntents.openBatteryOptimizationSettings(), isFalse);
      expect(await SystemIntents.openAppDetails(), isFalse);
      expect(await SystemIntents.openAppNotificationSettings(), isFalse);
      expect(calls, isEmpty);
    });

    test('其它非 Android 平台（linux）也不抛', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      mockChannel((_) => true);

      await expectLater(SystemIntents.openAppDetails(), completion(isFalse));
      expect(calls, isEmpty);
    });
  });
}

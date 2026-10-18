// 设置 · 通知节（M6-C2 §3）—— 平台差异与降级那一半（自
// `notify_section_test.dart` 按 group 边界拆出，断言一条未改）。
//
// 三个 group：Windows 端（插件不支持 → 整节置灰、开关点不动、不弹权限框）、
// 桌面 1280（同一份组件 key 齐全、改档位同样落盘、showTitle 默认自绘一份）、
// 装配缺失要降级不许红屏（没有 NotifySettingsStore → 一行可读提示）。
//
// 窄屏 411 在 `notify_section_narrow_test.dart`；共用夹具在
// `notify_section_harness.dart`。全文件不碰数据库，所以不需要 `tester.runAsync`。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/notify/notify_settings.dart';

import 'notify_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotifySectionHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late SharedPreferences prefs;
  late FakeNotifySink sink;

  setUp(() async {
    h = await NotifySectionHarness.start();
    prefs = h.prefs;
    sink = h.sink;
  });

  tearDown(() => h.stop());

  Future<void> pumpSection(WidgetTester tester,
          {double width = 411,
          bool supported = true,
          bool withStore = true,
          bool showTitle = true}) =>
      h.pumpSection(tester,
          width: width, supported: supported, withStore: withStore,
          showTitle: showTitle);

  Future<void> pickLead(WidgetTester tester, String key, String label) =>
      h.pickLead(tester, key, label);

  group('Windows 端（§0.1：插件不支持）', () {
    testWidgets('整节置灰 + 说明文字，开关点不动、也不弹权限框',
        (WidgetTester tester) async {
      await pumpSection(tester, supported: false);

      expect(find.text('Windows 端暂不支持系统通知，提醒功能仅在 Android 上生效。'),
          findsOneWidget);
      expect(sink.calls, isNot(contains('requestPermission')),
          reason: '不支持的平台不该弹权限框');
      // 控件仍在场（隐藏会让人以为设置丢了），但被 IgnorePointer 挡住。
      for (final String key in kAllKeys.where((String k) => !k.startsWith('notify-perm'))) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: '缺 $key');
      }
      await tester.tap(find.byKey(const ValueKey<String>('notify-enabled')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(prefs.getBool(NotifySettings.kEnabledKey), isNull,
          reason: '置灰必须真的点不动（IgnorePointer 生效）');
      expect(find.text('去开启'), findsNothing);
    });
  });

  group('桌面 1280', () {
    testWidgets('同一份组件：key 齐全，改档位同样落盘',
        (WidgetTester tester) async {
      await pumpSection(tester, width: 1280);
      for (final String key in kAllKeys) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: '缺 $key');
      }
      await pickLead(tester, 'notify-task-lead-minutes', '60 分钟');
      expect(prefs.getInt(NotifySettings.kTaskLeadMinutesKey), 60);

      await tester.tap(find.byKey(const ValueKey<String>('notify-cx-lead2')));
      await tester.pumpAndSettle();
      expect(prefs.getBool(NotifySettings.kCxLead2EnabledKey), isFalse);
    });

    testWidgets('showTitle 默认 true：节名自绘一份，不多不少',
        (WidgetTester tester) async {
      await pumpSection(tester, width: 1280);
      expect(find.text('通知'), findsOneWidget,
          reason: '设置树传 showTitle:false 时不该再有第二份，默认才自绘');
    });
  });

  group('装配缺失要降级，不许红屏', () {
    testWidgets('没有 NotifySettingsStore → 一行可读提示',
        (WidgetTester tester) async {
      await pumpSection(tester, withStore: false);
      expect(find.textContaining('NotifySettingsStore 未注册进 Provider 树'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

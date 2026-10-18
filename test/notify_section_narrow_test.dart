// 设置 · 通知节（M6-C2 §3）—— 窄屏 411 那一半（自 `notify_section_test.dart`
// 按 group 边界拆出，断言一条未改）。
//
// 双端各 pump 一次（总纲铁律 8：411 与 1280 都要过）——本节的档位下拉与免打扰
// 按钮两端布局不同，历史上「只 pump 桌面壳」让四条移动端布局缺陷溜到真机才发现。
// 改档位的断言一律**读 prefs**，不只看 UI：UI 对了但没落盘 = 重启就丢。
// 全文件不碰数据库（本节只依赖 NotifySettingsStore / NotificationService），
// 所以不需要 `tester.runAsync`。
//
// Windows 置灰 / 桌面 1280 / 装配缺失降级在 `notify_section_platform_test.dart`；
// 共用夹具在 `notify_section_harness.dart`。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late NotifySettingsStore store;

  setUp(() async {
    h = await NotifySectionHarness.start();
    prefs = h.prefs;
    sink = h.sink;
    store = h.store;
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

  group('窄屏 411', () {
    testWidgets('13 个控件 key 全在场，进页才请求权限（不在启动时）',
        (WidgetTester tester) async {
      await pumpSection(tester);
      for (final String key in kAllKeys) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget,
            reason: '通知节缺少 key $key');
      }
      expect(sink.calls, contains('requestPermission'),
          reason: '§C2 §5：首次进入本页才弹权限框');
      expect(find.text('提前'), findsNWidgets(3));
    });

    testWidgets('二级页形态（showTitle:false）不再自绘节名——顶栏已经写了',
        (WidgetTester tester) async {
      await pumpSection(tester, showTitle: false);
      expect(find.text('通知'), findsNothing,
          reason: 'S1 在设置页栽过一次重复标题（顶栏 + 内容各一份）');
      expect(find.byKey(const ValueKey<String>('notify-enabled')), findsOneWidget);
    });

    testWidgets('改一档提前量 → prefs 读到新值（不是只看 UI）',
        (WidgetTester tester) async {
      await pumpSection(tester);
      expect(prefs.getInt(NotifySettings.kTaskLeadMinutesKey), isNull,
          reason: '未改过之前 prefs 里不该有这个 key（默认值只在内存里）');

      await pickLead(tester, 'notify-task-lead-minutes', '15 分钟');
      expect(prefs.getInt(NotifySettings.kTaskLeadMinutesKey), 15);

      await pickLead(tester, 'notify-cx-lead1-minutes', '360 分钟');
      expect(prefs.getInt(NotifySettings.kCxLead1MinutesKey), 360);

      await pickLead(tester, 'notify-cx-lead2-minutes', '5 分钟');
      expect(prefs.getInt(NotifySettings.kCxLead2MinutesKey), 5);

      // 内存值同步跟上：协调器订阅的就是它。
      expect(store.value.taskLeadMinutes, 15);
      expect(find.text('15 分钟'), findsOneWidget);
    });

    testWidgets('开关逐个落盘：总开关 / 到期时刻 / 免打扰',
        (WidgetTester tester) async {
      await pumpSection(tester);
      await tester.tap(find.byKey(const ValueKey<String>('notify-enabled')));
      await tester.pumpAndSettle();
      expect(prefs.getBool(NotifySettings.kEnabledKey), isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('notify-task-due')));
      await tester.pumpAndSettle();
      expect(prefs.getBool(NotifySettings.kTaskDueEnabledKey), isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('notify-quiet')));
      await tester.pumpAndSettle();
      expect(prefs.getBool(NotifySettings.kQuietEnabledKey), isFalse);
    });

    testWidgets('免打扰起止走 showTimePicker，选完落回当日分钟数',
        (WidgetTester tester) async {
      await pumpSection(tester);
      expect(store.value.quietStart, 1380, reason: '默认 23:00');
      expect(find.text('开始 23:00'), findsOneWidget);
      expect(prefs.getInt(NotifySettings.kQuietStartKey), isNull,
          reason: 'load() 只读不写：没动过之前 prefs 里不该有这个 key');

      await tester.tap(find.byKey(const ValueKey<String>('notify-quiet-start')));
      await tester.pumpAndSettle();
      expect(find.text('免打扰开始时间'), findsOneWidget,
          reason: 'helpText 是这条路径唯一的可定位锚点');
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final Finder fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, '8');
      await tester.pumpAndSettle();
      await tester.enterText(fields.last, '30');
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // 输入模式默认 12 小时制（MaterialLocalizations.alwaysUse24HourFormat=false），
      // 初始值 23:00 把 period 定在 PM，所以填 8 得到的是 **20:30**——正好验证
      // hour/minute → 当日分钟数 的换算不是简单拼数字。
      expect(prefs.getInt(NotifySettings.kQuietStartKey), 20 * 60 + 30,
          reason: 'TimeOfDay 只许停在 UI 层，落盘必须是分钟数 int');
      expect(find.text('开始 20:30'), findsOneWidget);
    });

    testWidgets('权限未开启：顶部橙色提示，但下方开关照样能改',
        (WidgetTester tester) async {
      sink.permission = false;
      await pumpSection(tester);
      expect(find.text('系统通知权限：未开启'), findsOneWidget);
      expect(find.text('系统通知权限未开启，提醒不会响。'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('notify-task-lead')));
      await tester.pumpAndSettle();
      expect(prefs.getBool(NotifySettings.kTaskLeadEnabledKey), isFalse,
          reason: '§C2 §3：用户可以先把设置存好，不必先开权限');
    });

    testWidgets('「去开启」打到 C3 的深链通道；打不开时给手动路径文案',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('qingdan/system'), (MethodCall call) async {
        calls.add(call);
        return false; // 原生侧找不到接收方
      });
      sink.permission = false;
      await pumpSection(tester);

      await tester.tap(find.byKey(const ValueKey<String>('notify-perm-open')));
      await tester.pumpAndSettle();
      expect(calls.map((MethodCall c) => c.method),
          <String>['openAppNotificationSettings', 'openAppDetails'],
          reason: '严格版失败要回落应用详情页，两条都失败才说话');
      expect(find.textContaining('打不开，请手动到 系统设置 → 应用 → 清单 里找'), findsOneWidget);
      // widget 测试的 invariant 检查在 tearDown 之前跑，debug 变量必须在本体内还原。
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

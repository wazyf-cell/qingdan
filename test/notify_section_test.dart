// 设置 · 通知节（M6-C2 §3）的 widget 测试。
//
// 双端各 pump 一次（总纲铁律 8：411 与 1280 都要过）——本节的档位下拉与免打扰
// 按钮两端布局不同，历史上「只 pump 桌面壳」让四条移动端布局缺陷溜到真机才发现。
// 改档位的断言一律**读 prefs**，不只看 UI：UI 对了但没落盘 = 重启就丢。
// 全文件不碰数据库（本节只依赖 NotifySettingsStore / NotificationService），
// 所以不需要 tester.runAsync。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DidReceiveNotificationResponseCallback;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/settings/notify_section.dart';
import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/theme/app_theme.dart';

class _FakeSink implements NotificationSink {
  final List<String> calls = <String>[];
  bool permission = true, enabled = true;

  @override
  Future<void> initialize(
      {DidReceiveNotificationResponseCallback? onResponse}) async {
    calls.add('initialize');
  }

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    return permission;
  }

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<void> schedule(ScheduledReminder item) async {}
}

const List<String> kAllKeys = <String>[
  'notify-enabled',
  'notify-task-lead',
  'notify-task-lead-minutes',
  'notify-task-due',
  'notify-cx-lead1',
  'notify-cx-lead1-minutes',
  'notify-cx-lead2',
  'notify-cx-lead2-minutes',
  'notify-quiet',
  'notify-quiet-start',
  'notify-quiet-end',
  'notify-perm-status',
  'notify-perm-open',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _FakeSink sink;
  late NotifySettingsStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    sink = _FakeSink();
    store = NotifySettingsStore(prefs: prefs);
    await store.load();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('qingdan/system'), null);
  });

  Future<void> pumpSection(WidgetTester tester,
      {double width = 411,
      bool supported = true,
      bool withStore = true,
      bool showTitle = true}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        if (withStore)
          ChangeNotifierProvider<NotifySettingsStore>.value(value: store),
        Provider<NotificationService>(
            create: (_) =>
                NotificationService(sink: sink, supported: () => supported)),
      ],
      // 必须走 AppTheme：AppColors.of 读的是它装的 ThemeExtension。
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: NotifySection(showTitle: showTitle),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 打开档位下拉并选一项。测试里刻意选**页面上唯一出现**的那个文案，
  /// 免得和别的下拉当前显示的值撞车（三个下拉都渲染各自的当前值）。
  Future<void> pickLead(WidgetTester tester, String key, String label) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

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

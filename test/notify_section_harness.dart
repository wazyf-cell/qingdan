// 设置 · 通知节测试的共用夹具（自 `notify_section_test.dart` 拆出；非 `_test`
// 文件，flutter test 不直接执行）。
//
// 拆分后的两份文件（按原文件已有的 group 边界切）：
//  - `notify_section_narrow_test.dart` —— group「窄屏 411」：13 个 key、档位/开关
//    落盘、免打扰 showTimePicker、权限未开启、深链「去开启」
//  - `notify_section_platform_test.dart` —— group「Windows 端（插件不支持）」、
//    group「桌面 1280」、group「装配缺失要降级，不许红屏」
//
// 唯一的机械改名：原文件的私有 `_FakeSink` 跨库必须公开，改为 `FakeNotifySink`，
// 实现一字未动（测试本体只通过 `sink` 变量用它，没引用过类名）。
//
// 全夹具不碰数据库（本节只依赖 NotifySettingsStore / NotificationService），
// 所以不需要 `tester.runAsync`。
library;

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

class FakeNotifySink implements NotificationSink {
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

class NotifySectionHarness {
  NotifySectionHarness();

  late SharedPreferences prefs;
  late FakeNotifySink sink;
  late NotifySettingsStore store;

  /// 原 `setUp` 的 body，顺序一字未动。
  static Future<NotifySectionHarness> start() async {
    final NotifySectionHarness h = NotifySectionHarness();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    h.prefs = await SharedPreferences.getInstance();
    h.sink = FakeNotifySink();
    h.store = NotifySettingsStore(prefs: h.prefs);
    await h.store.load();
    return h;
  }

  /// 原 `tearDown` 的 body。
  void stop() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('qingdan/system'), null);
  }

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
}

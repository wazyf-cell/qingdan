// 设置树测试的共用夹具（自 `settings_page_test.dart` 拆出；非 `_test` 文件，
// flutter test 不直接执行）。
//
// 拆分后的三份文件：
//  - `settings_tree_test.dart` —— 一级七行的顺序/副文案 + 逐个点开能退回来
//    （外加 `trash.purgeDays` 落盘往返、`kAppVersion` 与 pubspec 同步两条纯模型用例）
//  - `settings_sections_test.dart` —— 外观 / 数据与同步 / 通用 / 关于四节的页内内容
//  - `settings_dialog_test.dart` —— 桌面对话框形态（左栏七项 + 640×440 尺寸）
//
// 原来两端各写一份节列表，加一节要改两处、顺序还会漂；现在两边都读
// `settings_nav.dart` 那一份，所以这几份文件同时钉住**手机与桌面的一致**。
// 双端各 pump 一次（总纲铁律 8）。夹具不碰数据库。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/settings/settings_page.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/theme/theme_mode_model.dart';

import 'chaoxing_harness.dart';

const List<String> rowKeys = <String>[
  'settings-appearance',
  'settings-notify',
  'settings-data',
  'settings-course',
  'settings-chaoxing',
  'settings-general',
  'settings-about',
];
const List<String> titles = <String>[
  '外观',
  '通知',
  '数据与同步',
  '课表',
  '学习通',
  '通用',
  '关于',
];

Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
    tester.runAsync<T?>(body);

class SettingsPageHarness {
  SettingsPageHarness();

  late SettingsModel settings;
  late NotifySettingsStore notifySettings;
  late SharedPreferences prefs;
  late ChaoxingHarness cx;

  /// 原 `setUp` 的 body，顺序一字未动。
  static Future<SettingsPageHarness> open() async {
    final SettingsPageHarness h = SettingsPageHarness();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    h.cx = ChaoxingHarness();
    await h.cx.start(tasks: <ChaoxingTask>[], loggedIn: false, seeded: false);
    h.cx.stubSeams();
    addTearDown(h.cx.restoreSeams);
    // harness 内部也会 setMockInitialValues（学习通 prefs 有自己的种子），
    // 所以**必须在其之后再取一次**：先取到的那份会被重置掉，
    // 之后「写进去再读回来」的断言就全成了 null。
    h.prefs = await SharedPreferences.getInstance();
    h.settings = SettingsModel(prefs: h.prefs);
    h.notifySettings = NotifySettingsStore(prefs: h.prefs);
    return h;
  }

  Future<void> pumpNarrow(WidgetTester tester, {double width = 411}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsModel>.value(value: settings),
        ChangeNotifierProvider<NotifySettingsStore>.value(value: notifySettings),
        ChangeNotifierProvider<ChaoxingModel>.value(value: cx.model),
        ChangeNotifierProvider<ThemeModeModel>(
            create: (_) => ThemeModeModel(ThemeMode.system)),
        Provider<SyncConfigStore>(create: (_) => SyncConfigStore()),
      ],
      // 主题必须走 AppTheme：`AppColors.of(context)` 读的是它装的扩展，
      // 裸 MaterialApp 会让每个自绘 widget 在 `!` 上炸。
      child: Consumer<ThemeModeModel>(
        builder: (BuildContext _, ThemeModeModel theme, _) => MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openRow(WidgetTester tester, String rowKey) async {
    await tester.tap(find.byKey(ValueKey<String>(rowKey)));
    await tester.pumpAndSettle();
    // 「数据与同步」里的 SyncSection 在 initState 里读配置（SharedPreferences
    // 走真异步）。runAsync 之外假时钟不会替它把 Future 跑完，页面会一直停在
    // 「读取中…」——所以开完页给一次真实延时，再回假时钟推帧。
    await io(tester, () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }
}

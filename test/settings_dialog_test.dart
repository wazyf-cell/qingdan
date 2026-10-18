// 设置 · 桌面对话框形态（自 `settings_page_test.dart` 按被测对象拆出，断言一条
// 未改）：左栏同样七项、内容区仍是 640×440 的既有范式，点「数据与同步」能出控件。
//
// 一级树在 `settings_tree_test.dart`，各二级节内容在 `settings_sections_test.dart`；
// 共用夹具在 `settings_page_harness.dart`（本份用例自己 pumpWidget，不走 pumpNarrow）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/settings/settings_dialog.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/theme/theme_mode_model.dart';

import 'chaoxing_harness.dart';
import 'settings_page_harness.dart';

void main() {
  late SettingsPageHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late SettingsModel settings;
  late NotifySettingsStore notifySettings;
  late ChaoxingHarness cx;

  setUp(() async {
    h = await SettingsPageHarness.open();
    settings = h.settings;
    notifySettings = h.notifySettings;
    cx = h.cx;
  });

  testWidgets('桌面对话框：左栏同样七项，尺寸与原来一致', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
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
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(builder: (BuildContext ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showSettingsDialog(ctx),
                  child: const Text('open-settings'),
                ),
              )),
        ),
      ),
    ));
    await tester.tap(find.text('open-settings'));
    await tester.pumpAndSettle();

    // `Dialog` 自己的 RenderBox 吃满路由约束，量它恒等于屏幕；
    // 量对话框内容区最外层那个 Row（导航 + 分隔线 + 内容）才是 640×440。
    final Size dialog = tester.getSize(find
        .descendant(of: find.byType(Dialog), matching: find.byType(Row))
        .first);
    expect(dialog, const Size(640, 440), reason: '既有范式，不该被顺手改掉');
    for (final String nav in titles) {
      expect(find.text(nav), findsWidgets, reason: '对话框左栏缺 $nav');
    }
    await tester.tap(find.text('数据与同步').first);
    await tester.pumpAndSettle();
    // 同 openRow：同步节要真异步读一次配置才出控件。
    await io(tester, () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('sync-enabled')), findsOneWidget);
    expect(find.text('回收站自动清空'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/settings/about_section.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/features/settings/settings_dialog.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/settings/settings_page.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/theme/theme_mode_model.dart';

/// 设置的两端形态（M5 定案第 13 条 + 2026-10-18 用户改的二级页）。
///
/// 窄屏：一级只有四行，点进去各自整页；节组件用 `showTitle: false`，
/// 所以**二级页里不许再出现第二个同名标题**（S1 就在设置页栽过一次重复标题）。
/// 桌面：还是那个左导航右内容的对话框，四节齐全，且「课表导入」那个
/// 永远停在 M4 的占位节必须已经删掉。
///
/// 本文件不碰数据库：设置四节只读 ThemeModeModel / SyncConfigStore / SettingsModel。
void main() {
  late SettingsModel settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = SettingsModel(prefs: await SharedPreferences.getInstance());
  });

  Future<void> pumpNarrow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsModel>.value(value: settings),
        ChangeNotifierProvider<ThemeModeModel>(
            create: (_) => ThemeModeModel(ThemeMode.system)),
        Provider<SyncConfigStore>(create: (_) => SyncConfigStore()),
      ],
      // 主题必须走 AppTheme：`AppColors.of(context)` 读的是它装的扩展，
      // 裸 MaterialApp 会让每个自绘 widget 在 `!` 上炸（第一版就是这么红的）。
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
  }

  testWidgets('窄屏一级只有四行，没有内联的节内容', (WidgetTester tester) async {
    await pumpNarrow(tester);

    for (final String key in <String>[
      'settings-appearance',
      'settings-sync',
      'settings-general',
      'settings-about',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget,
          reason: '一级缺少行 $key');
    }
    // 内容在二级页里，一级不该同时出现「启用同步」这类控件。
    expect(find.text('启用同步'), findsNothing);
    expect(find.text('主题'), findsNothing);
  });

  testWidgets('外观二级页：标题只有一份，切深色立刻生效',
      (WidgetTester tester) async {
    await pumpNarrow(tester);
    await openRow(tester, 'settings-appearance');

    expect(find.text('外观'), findsOneWidget,
        reason: '顶栏写了「外观」，内容区不得再自绘一次同名标题');
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
  });

  testWidgets('通用二级页：默认页与角标开关都落盘',
      (WidgetTester tester) async {
    await pumpNarrow(tester);
    await openRow(tester, 'settings-general');

    expect(find.text('外观'), findsNothing);
    expect(find.text('手机默认打开的页面'), findsOneWidget);
    // 「设置」不该出现在默认页选项里：它是点进来的去处，不是开屏要看的东西。
    // 本页除顶栏「通用」外不该有任何「设置」字样，出现即说明把它做成了选项。
    expect(find.text('设置'), findsNothing);

    await tester.tap(find.text('显示待办数字'));
    await tester.pumpAndSettle();
    expect(settings.showBadges, isFalse);
    expect((await SharedPreferences.getInstance())
        .getBool(SettingsModel.kShowBadgesKey), isFalse);

    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();
    expect(settings.defaultTab, ShellTab.course);
    expect((await SharedPreferences.getInstance())
        .getString(SettingsModel.kDefaultTabKey), 'course');
  });

  testWidgets('关于二级页显示版本号，且与 pubspec 一致',
      (WidgetTester tester) async {
    await pumpNarrow(tester);
    await openRow(tester, 'settings-about');

    expect(find.byKey(const ValueKey<String>('app-version')), findsOneWidget);
    expect(find.text('v$kAppVersion'), findsOneWidget);
    expect(find.textContaining('也不会自建任何服务器'), findsOneWidget);
  });

  testWidgets('桌面对话框：四节导航齐全，M4 占位节已删',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<SettingsModel>.value(value: settings),
        ChangeNotifierProvider<ThemeModeModel>(
            create: (_) => ThemeModeModel(ThemeMode.system)),
        Provider<SyncConfigStore>(create: (_) => SyncConfigStore()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
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

    expect(find.text('课表导入'), findsNothing,
        reason: '那是 M4 占位节，导入入口已挪到课表页（定案第 8、13 条）');
    for (final String nav in <String>['外观', '同步', '通用', '关于']) {
      expect(find.text(nav), findsWidgets, reason: '对话框左栏缺 $nav');
    }
    // 点「通用」→ 右栏出现通用内容。
    await tester.tap(find.text('通用').first);
    await tester.pumpAndSettle();
    expect(find.text('手机默认打开的页面'), findsOneWidget);
  });

  test('kAppVersion 必须与 pubspec.yaml 的 version 同步', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? m =
        RegExp(r'^version:\s*([0-9][\w.\-+]*)', multiLine: true)
            .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml 里找不到 version: 行');
    final String declared = m!.group(1)!.split('+').first;
    expect(kAppVersion, declared,
        reason: '改了 pubspec 版本号要同步 about_section.dart 的 kAppVersion');
  });
}

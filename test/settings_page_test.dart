import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/features/settings/about_section.dart';
import 'package:qingdan/features/settings/settings_dialog.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/settings/settings_page.dart';
import 'package:qingdan/features/shell/shell_tab.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/sync/sync_config_store.dart';
import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/theme/theme_mode_model.dart';

import 'chaoxing_harness.dart';

/// 设置树（M6-C C1）：一级七行 + 每行都能进得去、退得回来。
///
/// 原来两端各写一份节列表，加一节要改两处、顺序还会漂；现在两边都读
/// `settings_nav.dart` 那一份，所以本文件同时钉住**手机与桌面的一致**。
/// 双端各 pump 一次（总纲铁律 8）。本文件不碰数据库。
void main() {
  late SettingsModel settings;
  late NotifySettingsStore notifySettings;
  late SharedPreferences prefs;
  late ChaoxingHarness cx;

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

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    cx = ChaoxingHarness();
    await cx.start(tasks: <ChaoxingTask>[], loggedIn: false, seeded: false);
    cx.stubSeams();
    addTearDown(cx.restoreSeams);
    // harness 内部也会 setMockInitialValues（学习通 prefs 有自己的种子），
    // 所以**必须在其之后再取一次**：先取到的那份会被重置掉，
    // 之后「写进去再读回来」的断言就全成了 null。
    prefs = await SharedPreferences.getInstance();
    settings = SettingsModel(prefs: prefs);
    notifySettings = NotifySettingsStore(prefs: prefs);
  });

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

  Future<T?> io<T>(WidgetTester tester, Future<T?> Function() body) =>
      tester.runAsync<T?>(body);

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

  testWidgets('一级恰好七行，顺序与副文案齐全，且没有内联的节内容',
      (WidgetTester tester) async {
    await pumpNarrow(tester);

    for (final String key in rowKeys) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget,
          reason: '一级缺行 $key');
    }
    for (final String title in titles) {
      expect(find.text(title), findsOneWidget, reason: '一级标题 $title 重复或缺');
    }
    // 内容在二级页里：一级不该同时出现「启用同步」这类控件。
    expect(find.text('启用同步'), findsNothing);
    expect(find.text('主题'), findsNothing);
    // 每行都得有一行副文案告诉用户这节里有什么（不许留空话行）。
    for (final String key in rowKeys) {
      final ListTile row = tester.widget<ListTile>(find.byKey(ValueKey<String>(key)));
      expect(row.subtitle, isNotNull, reason: '$key 缺副文案');
    }
  });

  testWidgets('七行逐个点开：顶栏标题正确、能退回来', (WidgetTester tester) async {
    await pumpNarrow(tester);
    for (int i = 0; i < rowKeys.length; i++) {
      await openRow(tester, rowKeys[i]);
      final AppBar bar = tester.widget<AppBar>(find.widgetWithIcon(AppBar, Icons.arrow_back).first);
      expect((bar.title as Text).data, titles[i],
          reason: '${rowKeys[i]} 的二级页顶栏标题不对');
      // 顶栏写了节名，内容就不该再自绘一份同名标题。
      expect(find.text(titles[i]), findsOneWidget);
      await back(tester);
      expect(find.byKey(ValueKey<String>(rowKeys[i])), findsOneWidget,
          reason: '${titles[i]} 退不回一级');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('外观页收下了「默认页签」和「角标」（原来夹在通用里）',
      (WidgetTester tester) async {
    await pumpNarrow(tester);
    await openRow(tester, 'settings-appearance');

    expect(find.text('手机默认打开的页面'), findsOneWidget);
    // 「设置」不当默认页：它是点进来的去处，不是开屏要看的东西。
    expect(find.text('设置'), findsNothing);

    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();
    expect(settings.defaultTab, ShellTab.course);
    expect(prefs.getString(SettingsModel.kDefaultTabKey), 'course');

    await tester.tap(find.text('显示待办数字'));
    await tester.pumpAndSettle();
    expect(settings.showBadges, isFalse);
    expect(prefs.getBool(SettingsModel.kShowBadgesKey), isFalse);
  });

  testWidgets('数据与同步页：同步配置与回收站四档在同一节',
      (WidgetTester tester) async {
    await pumpNarrow(tester);
    await openRow(tester, 'settings-data');

    for (final String key in <String>[
      'sync-enabled',
      'sync-url',
      'sync-user',
      'sync-password',
      'sync-test',
      'sync-save',
      'sync-clear',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget,
          reason: '同步节缺控件 $key（原来整节零 key，测试只能靠文本定位）');
    }
    expect(find.text('回收站自动清空'), findsOneWidget);
    for (final String label in <String>['永不', '7 天', '30 天', '90 天']) {
      expect(find.text(label), findsOneWidget, reason: '回收站档位缺 $label');
    }
    await tester.tap(find.text('7 天'));
    await tester.pumpAndSettle();
    expect(settings.trashPurgeDays, 7);
    expect(prefs.getInt(SettingsModel.kTrashPurgeDaysKey), 7);
  });

  testWidgets('通用页：语言与检查更新是明说「没做」的占位，不是死行',
      (WidgetTester tester) async {
    await pumpNarrow(tester);
    await openRow(tester, 'settings-general');

    final ListTile lang =
        tester.widget<ListTile>(find.byKey(const ValueKey<String>('settings-language')));
    expect(lang.enabled, isFalse, reason: '语言没做就该看着是灰的');
    expect(find.textContaining('英文版尚未制作'), findsOneWidget);

    expect(find.textContaining('更新源尚未配置'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('settings-update')));
    await tester.pumpAndSettle();
    expect(find.textContaining('等仓库发布第一个 Release 后启用'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('update-ok')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('general-permissions')));
    await tester.pumpAndSettle();
    expect(find.text('后台与省电'), findsWidgets);
    expect(find.textContaining('本应用不在后台常驻'), findsOneWidget,
        reason: '那句诚实边界不许省（提醒为什么有时不响）');
    await back(tester);
  });

  testWidgets('关于页：版本 + 使用说明进 help-page + 开源许可',
      (WidgetTester tester) async {
    await pumpNarrow(tester);
    await openRow(tester, 'settings-about');

    expect(find.byKey(const ValueKey<String>('app-version')), findsOneWidget);
    expect(find.text('v$kAppVersion'), findsOneWidget);
    expect(find.textContaining('也不会自建任何服务器'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('settings-help')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('help-page')), findsOneWidget);
    await back(tester);

    await tester.tap(find.byKey(const ValueKey<String>('settings-licenses')));
    await tester.pumpAndSettle();
    // 项目没接 flutter_localizations（E2 定案：本批不半做 i18n），
    // showLicensePage 的默认标题是英文，所以按**类型**而不是文案认它。
    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  test('trash.purgeDays 落盘往返：存 7 读回 7，非法值回退默认 30', () async {
    await settings.setTrashPurgeDays(7);
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getInt(SettingsModel.kTrashPurgeDaysKey), 7);

    final SettingsModel reloaded = SettingsModel(prefs: p);
    await reloaded.load();
    expect(reloaded.trashPurgeDays, 7);

    await p.setInt(SettingsModel.kTrashPurgeDaysKey, 15);
    final SettingsModel bogus = SettingsModel(prefs: p);
    await bogus.load();
    expect(bogus.trashPurgeDays, SettingsModel.kTrashPurgeDaysDefault);
  });

  test('kAppVersion 必须与 pubspec.yaml 的 version 同步', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? m =
        RegExp(r'^version:\s*([0-9][\w.\-+]*)', multiLine: true)
            .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml 里找不到 version: 行');
    expect(kAppVersion, m!.group(1)!.split('+').first,
        reason: '改了 pubspec 版本号要同步 about_section.dart 的 kAppVersion');
  });
}

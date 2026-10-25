// 设置各二级节页的内容（自 `settings_page_test.dart` 按被测对象拆出，断言一条
// 未改）：外观页收下「默认页签 + 角标」、数据与同步节（同步控件 + 回收站四档）、
// 通用页的明说「没做」占位、关于页的版本/使用说明/开源许可。
//
// 一级树与进出在 `settings_tree_test.dart`，桌面对话框形态在
// `settings_dialog_test.dart`；共用夹具在 `settings_page_harness.dart`。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/settings/about_section.dart';
import 'package:qingdan/features/settings/licenses_page.dart';
import 'package:qingdan/update/install_policy.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/shell/shell_tab.dart';

import 'settings_page_harness.dart';

void main() {
  late SettingsPageHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late SettingsModel settings;
  late SharedPreferences prefs;

  setUp(() async {
    h = await SettingsPageHarness.open();
    settings = h.settings;
    prefs = h.prefs;
  });

  Future<void> pumpNarrow(WidgetTester tester, {double width = 411}) =>
      h.pumpNarrow(tester, width: width);

  Future<void> openRow(WidgetTester tester, String rowKey) =>
      h.openRow(tester, rowKey);

  Future<void> back(WidgetTester tester) => h.back(tester);

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

  testWidgets('通用页：语言仍是明说「没做」的占位，更新通道已是真控件两行',
      (WidgetTester tester) async {
    await pumpNarrow(tester);
    await openRow(tester, 'settings-general');

    final ListTile lang =
        tester.widget<ListTile>(find.byKey(const ValueKey<String>('settings-language')));
    expect(lang.enabled, isFalse, reason: '语言没做就该看着是灰的');
    // 2026-10-19：占位文案不许暗示一个没排期的未来。「英文版尚未制作 · 即将推出」
    // 让用户以为中英文是欠着的基本功能，而需求文档里根本没有多语言这一项。
    expect(find.textContaining('本应用只做简体中文'), findsOneWidget);
    expect(find.textContaining('英文版尚未制作'), findsNothing);
    expect(find.textContaining('即将推出'), findsNothing,
        reason: '没有排期的事不能写在界面上');

    // v1.0.2：检查更新从占位换成真控件，两行都在。点下去之后的行为（结论弹层、
    // 跳浏览器、失败回执）连同假 fetcher 一起放在 test/settings_update_rows_test.dart，
    // 这里不碰网络——测试环境里的 HttpClient 是被换掉的假实现。
    expect(find.textContaining('更新源尚未配置'), findsNothing);
    expect(find.text('检测更新'), findsOneWidget);
    expect(find.text('GitHub 仓库'), findsOneWidget);
    expect(find.textContaining('从 GitHub Releases 查新版本'), findsOneWidget);

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
    expect(find.byKey(const ValueKey<String>('about-disclaimer')), findsOneWidget);
    // 能不能覆盖安装的说法只此一份：关于页、检测更新弹层、发布页正文共用。
    final Text policy = tester.widget<Text>(find.byKey(
        const ValueKey<String>('about-install-policy')));
    expect(policy.data, kInstallPolicyText);

    await tester.tap(find.byKey(const ValueKey<String>('settings-help')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('help-page')), findsOneWidget);
    await back(tester);

    await tester.tap(find.byKey(const ValueKey<String>('settings-licenses')));
    await tester.pumpAndSettle();
    // 自定义许可页：先讲本应用与上游来源，再提供完整依赖许可证入口。
    expect(find.byType(LicensesPage), findsOneWidget);
    expect(find.text('GNU AGPL-3.0-or-later'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('licenses-full')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

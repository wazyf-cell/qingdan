// 设置树的一级列表与进出（M6-C C1；自 `settings_page_test.dart` 按被测对象拆出，
// 断言一条未改）。外加两条不落 UI 的模型用例：`trash.purgeDays` 落盘往返、
// `kAppVersion` 与 pubspec.yaml 同步。
//
// 各二级节页内内容在 `settings_sections_test.dart`，桌面对话框形态在
// `settings_dialog_test.dart`；共用夹具在 `settings_page_harness.dart`。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/settings/about_section.dart';
import 'package:qingdan/features/settings/settings_model.dart';

import 'settings_page_harness.dart';

void main() {
  late SettingsPageHarness h;
  // 以下本地位名只是把夹具接进本作用域，测试本体一字未改。
  late SettingsModel settings;

  setUp(() async {
    h = await SettingsPageHarness.open();
    settings = h.settings;
  });

  Future<void> pumpNarrow(WidgetTester tester, {double width = 411}) =>
      h.pumpNarrow(tester, width: width);

  Future<void> openRow(WidgetTester tester, String rowKey) =>
      h.openRow(tester, rowKey);

  Future<void> back(WidgetTester tester) => h.back(tester);

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

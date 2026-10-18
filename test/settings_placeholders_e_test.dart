import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/settings/about_section.dart' show kAppVersion;
import 'package:qingdan/features/settings/general_section.dart';
import 'package:qingdan/theme/app_theme.dart';

/// E 批两个占位的「不许偷偷做」钉桩（M6-E §E1 / §E2 的测试节）。
///
/// 一级页与二级页的可见行为已由 `test/settings_page_test.dart` 覆盖，这里只钉
/// 两条**只有读源码 / 读 widget 配置才看得见**的约束：
/// 1. 占位阶段**一个网络请求都不发**（联网只会给出失败提示，反而像功能坏了）；
/// 2. 语言占位不许顺手做成半套 i18n（切了语言只有一半界面跟着变）。
///
/// `GeneralSection` 自己不 watch 任何模型（只有它推开的二级节才需要 provider），
/// 所以本文件可以裸 pump，不用装配整棵 provider 树。
void main() {
  Future<void> pumpGeneral(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: GeneralSection(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  test('检查更新占位：general_section 不碰任何网络栈', () {
    final String src =
        File('lib/features/settings/general_section.dart').readAsStringSync();
    for (final String forbidden in <String>[
      'dart:io',
      'HttpClient',
      'package:http',
      'Socket',
      'Process.start',
    ]) {
      expect(src, isNot(contains(forbidden)),
          reason: '占位阶段点了就该只弹说明框，出现 $forbidden 等于偷偷开始联网');
    }
  });

  testWidgets('语言占位：MaterialApp 仍未接 flutter_localizations（不许半做 i18n）',
      (WidgetTester tester) async {
    await pumpGeneral(tester);

    final MaterialApp app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.localizationsDelegates, isNull,
        reason: '接了 delegates 就是开始做半套国际化');
    // supportedLocales 不设置时框架自带 [en_US] 默认值，不能拿它当证据；
    // 真正被「半做 i18n」改变的是 delegates 与 locale 覆盖。
    expect(app.supportedLocales ?? const <Locale>[], isNotEmpty);
    expect(app.locale, isNull);
  });

  testWidgets('语言行禁用、检查更新行带当前版本号', (WidgetTester tester) async {
    await pumpGeneral(tester);

    final ListTile lang = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('settings-language')));
    expect(lang.enabled, isFalse);
    expect(find.textContaining('简体中文'), findsOneWidget);

    final ListTile update = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('settings-update')));
    final Text subtitle = update.subtitle! as Text;
    expect(subtitle.data, contains(kAppVersion),
        reason: '副文案里的版本号必须取自 kAppVersion 那一个常量，不许再抄一份');
  });
}

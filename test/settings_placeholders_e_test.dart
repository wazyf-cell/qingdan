import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/settings/about_section.dart' show kAppVersion;
import 'package:qingdan/features/settings/general_section.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 两条「不许顺手做过头」的钉桩（M6-E §E2 语言占位 + v1.0.2 更新通道边界）。
///
/// 一级页与二级页的可见行为已由 `test/settings_page_test.dart` 覆盖，这里只钉
/// 两条**只有读源码 / 读 widget 配置才看得见**的约束：
/// 1. 更新通道只许「查一次 + 把人送到发布页」，不许自己下载安装包；
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

  test('更新通道的边界：只查、只跳浏览器，绝不自己下载安装包', () {
    // 为什么钉这一条：Android 覆盖安装要求签名一致，而 release 包与 debug 包
    // 签名不同 → 装上就得先卸载，卸载会清空 files/qingdan.db（任务、课表全在里面）。
    // 所以「点了就自己升级」在这个项目里是做不到的事，界面也不许偷偷往那走。
    final String src = <String>[
      'lib/update/update_checker.dart',
      'lib/features/settings/update_rows.dart',
    ].map((String p) => File(p).readAsStringSync()).join('\n');

    for (final String forbidden in <String>[
      'openWrite',
      'writeAsBytes',
      'writeAsString',
      'Process.start',
      'INSTALL_PACKAGES',
      'requestInstallPackages',
      'path_provider',
      'ApplicationDocumentsDirectory',
    ]) {
      expect(src, isNot(contains(forbidden)),
          reason: '出现 $forbidden 意味着开始往「自己下载并安装」那边走，那是做不到的事');
    }
    // 反向闸：只钉「不许做什么」的测试很容易变成永真式——把联网代码整块删掉它照样绿。
    expect(src, contains('api.github.com'),
        reason: '更新源必须是 GitHub Releases，否则这条功能就是假的');
    expect(src, contains('releases/latest'),
        reason: 'latest 才不含草稿与预发布；换成 /releases 会把彩排包推给用户');
  });

  testWidgets('语言占位：MaterialApp 仍未接 flutter_localizations（不许半做 i18n）',
      (WidgetTester tester) async {
    await pumpGeneral(tester);

    final MaterialApp app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.localizationsDelegates, isNull,
        reason: '接了 delegates 就是开始做半套国际化');
    // supportedLocales 不设置时框架给的是默认 [en_US]（非空、非 null），
    // 拿它当「有没有做 i18n」的证据会误判；真正会被改变的是 delegates 与 locale。
    expect(app.supportedLocales, isNotEmpty);
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

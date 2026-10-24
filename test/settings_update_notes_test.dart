import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/settings/about_section.dart' show kAppVersion;
import 'package:qingdan/features/settings/update_rows.dart';
import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/update/install_policy.dart';
import 'package:qingdan/update/update_checker.dart';

/// 检测更新弹层里的「这一版改了什么」：压 Markdown、去首尾空白、截断。
///
/// 从 `settings_update_rows_test.dart` 拆出来只为守住 300 行硬线；
/// 这里的弹层都来自假 fetcher，不碰网络，也不需要原生通道。
void main() {
  Future<void> pumpRows(WidgetTester tester, UpdateChecker checker) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: UpdateRows(checker: checker),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  UpdateChecker returning(Map<String, dynamic> json) =>
      UpdateChecker(fetch: (_) async => json);

  String detailOf(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('update-result-text')))
      .data!;

  Future<void> openResult(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('settings-update')));
    await tester.pumpAndSettle();
  }

  testWidgets('发布页写了说明 → 弹层里显示这一版改了什么',
      (WidgetTester tester) async {
    // 首尾空白来自 GitHub 的 body 原文，界面上不该留着。
    await pumpRows(tester, returning(<String, dynamic>{
      'tag_name': 'v9.9.9',
      'body': '  · 学习通刷新变快\n· 面板头部改成绝对时间  \n',
    }));
    await openResult(tester);

    final String text = detailOf(tester);
    expect(text, contains('这一版改了什么'));
    expect(text, contains('学习通刷新变快'));
    expect(text, contains('面板头部改成绝对时间'));
    expect(text, isNot(contains('  · 学习通')), reason: '首尾空白不该原样搬进弹层');
  });

  testWidgets('新版发布页分了段 → 只取「更新内容」，不把下载与安装说明搬进弹层',
      (WidgetTester tester) async {
    await pumpRows(tester, returning(<String, dynamic>{
      'tag_name': 'v9.9.9',
      'body': '## 更新内容\n\n'
          '- 学习通小组件改成可滚动\n'
          '- 检测更新能看见公告\n\n'
          '## 下载\n\n'
          '- 大多数手机：`qingdan-9.9.9-arm64-v8a.apk`\n\n'
          '## 覆盖安装说明\n\n'
          '- 同一把签名可以直接覆盖\n',
    }));
    await openResult(tester);

    final String text = detailOf(tester);
    expect(text, contains('学习通小组件改成可滚动'));
    expect(text, contains('检测更新能看见公告'));
    expect(text, isNot(contains('qingdan-9.9.9-arm64-v8a.apk')),
        reason: '下载段与弹层里的附件列表重复，还会把改动挤下去');
    expect(text, isNot(contains('覆盖安装说明')),
        reason: '安装说明由弹层自己的常量负责，正文里这段是重复的');
  });

  testWidgets('已是最新版 → 仍然显示最新发布这一版的公告',
      (WidgetTester tester) async {
    await pumpRows(tester, returning(<String, dynamic>{
      'tag_name': 'v$kAppVersion',
      'body': '## 更新内容\n\n- 改到期后角标立刻更新\n',
    }));
    await openResult(tester);

    final String text = detailOf(tester);
    expect(text, contains('已是最新版'));
    expect(text, contains('最新发布 v$kAppVersion 改了什么'));
    expect(text, contains('改到期后角标立刻更新'));
    expect(find.byKey(const ValueKey<String>('update-result-install')),
        findsNothing);
  });

  testWidgets('发布页没写说明 → 不出「这一版改了什么」，保持原来的版式',
      (WidgetTester tester) async {
    await pumpRows(tester, returning(<String, dynamic>{'tag_name': 'v9.9.9'}));
    await openResult(tester);

    final String text = detailOf(tester);
    expect(text, isNot(contains('这一版改了什么')));
    // 有新版时原有的两条信息一条都不能少。
    expect(text, contains('当前 v$kAppVersion → 最新 v9.9.9'));
    expect(text, contains(kInstallPolicyText));
  });

  testWidgets('发布说明是 Markdown → 压成纯文本，不把井号和星号端给用户',
      (WidgetTester tester) async {
    await pumpRows(tester, returning(<String, dynamic>{
      'tag_name': 'v9.9.9',
      'body': '## 这个版本改了什么\n\n'
          '**学习通**刷新变快，详见[仓库](https://github.com/x/y)\n'
          '- 头部改成 `22:20 更新`\n',
    }));
    await openResult(tester);

    final String text = detailOf(tester);
    expect(text, contains('这个版本改了什么'));
    expect(text, contains('学习通刷新变快'));
    expect(text, contains('· 头部改成 22:20 更新'));
    expect(text, isNot(contains('##')));
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('`')));
    expect(text, isNot(contains('https://github.com/x/y')),
        reason: 'URL 在弹层里既长又点不动，只留链接文字');
  });

  testWidgets('发布说明过长 → 截到 1200 字并以省略号收尾，弹层不被撑爆',
      (WidgetTester tester) async {
    await pumpRows(tester, returning(<String, dynamic>{
      'tag_name': 'v9.9.9',
      'body': 'A' * 2000,
    }));
    await openResult(tester);

    final String text = detailOf(tester);
    expect(text, contains('${'A' * 1200}…'));
    expect(text, isNot(contains('A' * 1201)), reason: '超出上限的部分必须真的丢掉');
  });
}

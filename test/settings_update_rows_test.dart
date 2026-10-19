import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/settings/about_section.dart' show kAppVersion;
import 'package:qingdan/features/settings/update_rows.dart';
import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/update/update_checker.dart';

/// 更新通道两行的可见行为（v1.0.2 把 M6-E 的说明占位换成真控件）。
///
/// 检查一律注入假 fetcher：测试环境里 HttpClient 是被换掉的假实现，
/// 真联网那半条只能在设备上验（变更日志里记着）。
void main() {
  const MethodChannel channel = MethodChannel('qingdan/system');
  final List<MethodCall> calls = <MethodCall>[];

  /// 装一个假原生侧：记录调用，并按 [reply] 决定「系统接不接这个链接」。
  void mockChannel(bool Function(MethodCall call) reply) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  setUp(() => mockChannel((_) => true));
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  /// 在「这台设备是 Android」下跑一段。
  ///
  /// 覆盖必须在**测试体内部**设、并在体末撤掉：binding 在测试体结束时查
  /// foundation debug 变量，而 `tearDown` 在那之后才跑（放 setUp 会让整文件全红）。
  Future<void> asAndroid(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

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

  String subtitleOf(WidgetTester tester) => tester
      .widget<Text>(
          find.byKey(const ValueKey<String>('settings-update-subtitle')))
      .data!;

  testWidgets('两行都在：检测更新带当前版本号，GitHub 行带仓库地址',
      (WidgetTester tester) async {
    await pumpRows(tester, returning(<String, dynamic>{'tag_name': 'v1.0.2'}));

    expect(find.text('检测更新'), findsOneWidget);
    expect(find.text('GitHub 仓库'), findsOneWidget);
    expect(subtitleOf(tester),
        allOf(contains(kAppVersion), contains('GitHub Releases')));
    expect(find.textContaining('更新源尚未配置'), findsNothing,
        reason: '占位文案已经换成真控件，留着就是骗人');
    expect(find.textContaining('等仓库发布第一个 Release 后启用'), findsNothing);
  });

  testWidgets('装好页面时一次都不查 GitHub —— 只有点下去才查',
      (WidgetTester tester) async {
    int hits = 0;
    await pumpRows(tester, UpdateChecker(fetch: (_) async {
      hits++;
      return <String, dynamic>{'tag_name': 'v9.9.9'};
    }));

    expect(hits, 0,
        reason: '设置页一打开就发请求 = 每次进设置都替用户去敲一次 GitHub');
    expect(find.textContaining('发现新版本'), findsNothing);
  });

  testWidgets('点检测更新 → 弹层说结论；没新版时不给「打开发布页」按钮',
      (WidgetTester tester) async {
    await pumpRows(
        tester, returning(<String, dynamic>{'tag_name': 'v$kAppVersion'}));

    await tester.tap(find.byKey(const ValueKey<String>('settings-update')));
    await tester.pumpAndSettle();

    expect(find.text('检查更新'), findsWidgets);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey<String>('update-result-text')))
            .data,
        contains('已是最新版'));
    expect(find.byKey(const ValueKey<String>('update-result-open')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('update-result-close')));
    await tester.pumpAndSettle();
    // 关掉弹层后结论留在行上，不用重新点一次才知道结果。
    expect(subtitleOf(tester), contains('已是最新版'));
  });

  testWidgets('发现新版本 → 弹层列出发布页文件，并真的把发布页地址交给系统',
      (WidgetTester tester) async {
    await asAndroid(() async {
      await pumpRows(tester, returning(<String, dynamic>{
        'tag_name': 'v9.9.9',
        'html_url': 'https://github.com/wazyf-cell/qingdan/releases/tag/v9.9.9',
        'published_at': '2026-10-19T06:00:00Z',
        'assets': <dynamic>[
          <String, dynamic>{'name': 'app-arm64-v8a-release.apk'},
        ],
      }));

      await tester.tap(find.byKey(const ValueKey<String>('settings-update')));
      await tester.pumpAndSettle();

      final String text = tester
          .widget<Text>(
              find.byKey(const ValueKey<String>('update-result-text')))
          .data!;
      expect(text, contains('9.9.9'));
      expect(text, contains('app-arm64-v8a-release.apk'));
      // 这条是整个功能的边界：不自己下载安装，因为换签名要卸载、卸载清库。
      expect(text, contains('不会自己下载'));
      expect(
          find.byKey(const ValueKey<String>('update-result-open')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('update-result-open')));
      await tester.pumpAndSettle();
      expect(calls.map((MethodCall c) => c.method), <String>['openUrl']);
      expect(
          (calls.single.arguments as Map<Object?, Object?>)['url'],
          'https://github.com/wazyf-cell/qingdan/releases/tag/v9.9.9');
    });
  });

  testWidgets('GitHub 行打开仓库主页；系统接不住时给一行本地回执',
      (WidgetTester tester) async {
    await asAndroid(() async {
      await pumpRows(
          tester, returning(<String, dynamic>{'tag_name': 'v$kAppVersion'}));

      await tester.tap(
          find.byKey(const ValueKey<String>('settings-update-github')));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'openUrl');
      expect((calls.single.arguments as Map<Object?, Object?>)['url'], kRepoUrl);
      expect(find.byKey(const ValueKey<String>('update-open-failed')),
          findsNothing);

      // 设备上没有能打开网页的应用（Android Go / 精简 ROM 真有这样）。
      // 这一半不需要 Android 覆盖也能过，但过的理由是「平台短路」而不是
      // 「系统真的没接」——所以整条都钉在 Android 下测。
      mockChannel((_) => false);
      await tester.tap(
          find.byKey(const ValueKey<String>('settings-update-github')));
      await tester.pumpAndSettle();
      final Text said = tester.widget<Text>(
          find.byKey(const ValueKey<String>('update-open-failed')));
      expect(said.data, contains('打不开'));
      expect(said.data, contains('github.com'));
    });
  });

  testWidgets('检查期间行禁用并转圈，重复点不会并发打两次请求',
      (WidgetTester tester) async {
    final Completer<Map<String, dynamic>> gate =
        Completer<Map<String, dynamic>>();
    int hits = 0;
    await pumpRows(tester, UpdateChecker(fetch: (_) {
      hits++;
      return gate.future;
    }));

    await tester.tap(find.byKey(const ValueKey<String>('settings-update')));
    await tester.pump(); // 让 setState 生效，但不放行请求
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('正在检查'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('settings-update')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('settings-update')));
    await tester.pump();
    expect(hits, 1, reason: '禁用状态下还发第二次 = 手快就并发查 GitHub');

    gate.complete(<String, dynamic>{'tag_name': 'v9.9.9'});
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('发现新版本'), findsWidgets);
  });

  testWidgets('检查失败在行上明说是失败，不伪装成「已是最新」',
      (WidgetTester tester) async {
    await pumpRows(
        tester,
        UpdateChecker(
            fetch: (_) async => throw const UpdateFetchException(
                '连不上 GitHub（这台设备当前没有网络）')));

    await tester.tap(find.byKey(const ValueKey<String>('settings-update')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已是最新版'), findsNothing);
    expect(subtitleOf(tester), contains('检查失败：连不上 GitHub'));
  });
}

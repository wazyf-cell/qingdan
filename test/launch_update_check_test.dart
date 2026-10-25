import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/update/launch_update_check.dart';
import 'package:qingdan/update/update_available_dialog.dart';
import 'package:qingdan/update/update_checker.dart';

/// 冷启动自动检测更新：只弹没关过的版本；关掉后同版本不再弹，更新的版本还会弹。
void main() {
  Map<String, dynamic> available(String version) => <String, dynamic>{
        'tag_name': 'v$version',
        'body': '## 更新内容\n\n- 修了点东西\n\n## 下载\n\n- 不用看这一段',
        'assets': <dynamic>[
          <String, dynamic>{
            'name': 'qingdan-$version-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/a.apk',
            'size': 1,
          },
        ],
      };

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return SharedPreferences.getInstance();
  }

  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(builder: (BuildContext c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    return ctx;
  }

  testWidgets('新版本弹一次；同版本关过不再弹；出现更新版本还会弹', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final SharedPreferences prefs = await freshPrefs();
      final BuildContext ctx = await host(tester);
      int shown = 0;
      Future<void> shower(BuildContext _, String _, ReleaseInfo _, UpdateChecker _) async {
        shown++;
      }

      await maybeShowUpdateOnLaunch(ctx,
          checker: UpdateChecker(fetch: (_) async => available('1.1.0')),
          currentVersion: '1.0.0',
          prefs: prefs,
          showDialogFn: shower);
      expect(shown, 1);
      expect(prefs.getStringList(kDismissedUpdateVersionsKey), <String>['1.1.0']);

      await maybeShowUpdateOnLaunch(ctx,
          checker: UpdateChecker(fetch: (_) async => available('1.1.0')),
          currentVersion: '1.0.0',
          prefs: prefs,
          showDialogFn: shower);
      expect(shown, 1, reason: '同一个版本关过之后不该再弹');

      await maybeShowUpdateOnLaunch(ctx,
          checker: UpdateChecker(fetch: (_) async => available('1.2.0')),
          currentVersion: '1.0.0',
          prefs: prefs,
          showDialogFn: shower);
      expect(shown, 2, reason: '更新的版本要重新提醒');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('首次欢迎框在前台时，等它关掉再弹更新公告', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final SharedPreferences prefs = await freshPrefs();
      final BuildContext ctx = await host(tester);
      int shown = 0;
      Future<void> shower(BuildContext _, String _, ReleaseInfo _, UpdateChecker _) async {
        shown++;
      }

      // 模拟首启欢迎框：它挡住 home 路由，自动检查不能直接放弃。
      showDialog<void>(
        context: ctx,
        builder: (BuildContext _) => const AlertDialog(title: Text('欢迎使用')),
      );
      await tester.pumpAndSettle();

      final Future<void> pending = maybeShowUpdateOnLaunch(ctx,
          checker: UpdateChecker(fetch: (_) async => available('1.1.0')),
          currentVersion: '1.0.0',
          prefs: prefs,
          showDialogFn: shower);
      await tester.pump();
      expect(shown, 0, reason: '欢迎框还在时不能叠一个更新公告');

      Navigator.of(ctx).pop();
      await tester.pumpAndSettle();
      await pending;
      expect(shown, 1, reason: '欢迎框关掉后应该补上这次更新提醒');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('已是最新版 / 检查失败都不弹', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final SharedPreferences prefs = await freshPrefs();
      final BuildContext ctx = await host(tester);
      int shown = 0;
      Future<void> shower(BuildContext _, String _, ReleaseInfo _, UpdateChecker _) async {
        shown++;
      }

      await maybeShowUpdateOnLaunch(ctx,
          checker: UpdateChecker(fetch: (_) async => available('1.0.0')),
          currentVersion: '1.0.0',
          prefs: prefs,
          showDialogFn: shower);
      expect(shown, 0);

      await maybeShowUpdateOnLaunch(ctx,
          checker: UpdateChecker(
              fetch: (_) async =>
                  throw const UpdateFetchException('连不上 GitHub')),
          currentVersion: '1.0.0',
          prefs: prefs,
          showDialogFn: shower);
      expect(shown, 0, reason: '启动路径上失败必须静默，不能甩错误框');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('公告关掉之后才记为已看过', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final SharedPreferences prefs = await freshPrefs();
      final BuildContext ctx = await host(tester);
      bool opened = false;
      final Completer<void> closed = Completer<void>();
      Future<void> shower(BuildContext _, String _, ReleaseInfo _, UpdateChecker _) {
        opened = true;
        return closed.future;
      }

      final Future<void> pending = maybeShowUpdateOnLaunch(ctx,
          checker: UpdateChecker(fetch: (_) async => available('1.1.0')),
          currentVersion: '1.0.0',
          prefs: prefs,
          showDialogFn: shower);
      await tester.pump();
      expect(opened, isTrue);
      expect(prefs.getStringList(kDismissedUpdateVersionsKey), isNull,
          reason: '弹层还开着时被杀掉，下次启动应该再提醒');

      closed.complete();
      await pending;
      expect(prefs.getStringList(kDismissedUpdateVersionsKey), <String>['1.1.0']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('公告只显示更新内容，并带「下载并安装」', (tester) async {
    final ReleaseInfo release = ReleaseInfo.fromJson(available('1.1.0'))!;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: UpdateAvailableDialog(
          currentVersion: '1.0.0',
          release: release,
        ),
      ),
    ));
    expect(find.byKey(const ValueKey<String>('update-available-dialog')),
        findsOneWidget);
    final Text notes = tester.widget<Text>(
        find.byKey(const ValueKey<String>('update-available-notes')));
    expect(notes.data, contains('修了点东西'));
    expect(notes.data, isNot(contains('不用看这一段')),
        reason: '下载段不该混进公告');
    expect(find.byKey(const ValueKey<String>('update-available-install')),
        findsOneWidget);
  });
}

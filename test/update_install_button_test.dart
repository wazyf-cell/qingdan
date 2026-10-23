import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/update/apk_download.dart';
import 'package:qingdan/update/install_policy.dart';
import 'package:qingdan/update/update_checker.dart';
import 'package:qingdan/update/update_install_button.dart';

/// 「下载并安装」按钮：权限 → 挑包 → 下载 → 校验 → 签名 → 调安装器。
///
/// 网络与平台通道都换掉（seams 与学习通面板同一套路），但**下载的文件、sha256、
/// 取消标记都是真的**——这几步正是真机上最容易出错的地方。
void main() {
  const MethodChannel ch = MethodChannel('qingdan/system');
  final List<MethodCall> calls = <MethodCall>[];
  late Directory dir;
  late Map<String, Object?> replies;

  final List<int> bytes = utf8.encode('fake apk bytes for tests');
  final String digest = sha256.convert(bytes).toString();

  ReleaseInfo release({
    String version = '9.9.9',
    bool withSums = true,
  }) =>
      ReleaseInfo(
        version: version,
        url: 'https://example.com/release',
        assets: <ReleaseAsset>[
          ReleaseAsset(
              name: 'qingdan-$version-arm64-v8a.apk',
              url: 'https://example.com/apk',
              size: bytes.length),
          ReleaseAsset(
              name: 'qingdan-$version-armeabi-v7a.apk',
              url: 'https://example.com/apk32',
              size: bytes.length),
          if (withSums)
            ReleaseAsset(
                name: 'qingdan-$version-sha256sums.txt',
                url: 'https://example.com/sums'),
        ],
      );

  setUp(() async {
    calls.clear();
    replies = <String, Object?>{
      'canInstallPackages': true,
      'deviceAbi': 'arm64-v8a',
      'packageSignature': 'a' * 64,
      'apkSignature': 'a' * 64,
      'installApk': true,
      'openInstallPermission': true,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (MethodCall call) async {
      calls.add(call);
      return replies[call.method];
    });
    dir = await Directory.systemTemp.createTemp('qingdan-update-test');
    debugDownloadDir = () => dir;
    debugTextFetcher = (Uri _) async => '$digest  qingdan-9.9.9-arm64-v8a.apk\n';
    debugApkFetcher = ({
      required Uri url,
      required File target,
      required void Function(int received, int total) onProgress,
      required bool Function() canceled,
    }) async {
      await target.writeAsBytes(bytes);
      onProgress(bytes.length, bytes.length);
    };
  });

  tearDown(() async {
    debugApkFetcher = null;
    debugTextFetcher = null;
    debugDownloadDir = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> pumpButton(WidgetTester tester,
      {ReleaseInfo? rel, UpdateChecker? checker}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: UpdateInstallButton(
            currentVersion: '1.0.3',
            release: rel,
            checker: checker,
          ),
        ),
      ),
    ));
  }

  /// 点按钮并让真实的异步链跑完（文件 IO + 通道都在这段时间里）。
  Future<void> tapAndWait(WidgetTester tester,
      {String expect = '已交给系统安装器'}) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey<String>('update-install')));
      await tester.pump();
      for (int i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.textContaining(expect).evaluate().isNotEmpty) return;
      }
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  String? message(WidgetTester tester) {
    final Finder f = find.byKey(const ValueKey<String>('update-install-message'));
    if (f.evaluate().isEmpty) return null;
    return tester.widget<Text>(f).data;
  }

  testWidgets('没开「安装未知应用」：先去系统页，不下载', (WidgetTester tester) async {
    replies['canInstallPackages'] = false;
    await pumpButton(tester, rel: release());
    await tapAndWait(tester, expect: '安装未知应用');

    expect(calls.map((MethodCall c) => c.method), contains('openInstallPermission'));
    expect(calls.map((MethodCall c) => c.method), isNot(contains('installApk')));
    expect(message(tester), contains('安装未知应用'));
    expect(Directory('${dir.path}/update').existsSync(), isFalse,
        reason: '权限都没开就别下 25MB');
  });

  testWidgets('正常路径：挑 arm64 包 → 校验 → 签名一致 → 调安装器',
      (WidgetTester tester) async {
    await pumpButton(tester, rel: release());
    await tapAndWait(tester);

    final MethodCall install =
        calls.firstWhere((MethodCall c) => c.method == 'installApk');
    final Map<Object?, Object?> args = install.arguments as Map<Object?, Object?>;
    expect(args['path'], endsWith('qingdan-9.9.9-arm64-v8a.apk'));
    expect(File(args['path']! as String).existsSync(), isTrue,
        reason: '文件要留着给系统安装器读');
    expect(message(tester), contains('已交给系统安装器'));
    expect(find.byKey(const ValueKey<String>('update-install-progress')),
        findsNothing);
  });

  testWidgets('签名不一致：根本不调安装器，直接说清要卸载', (WidgetTester tester) async {
    replies['packageSignature'] = 'b' * 64;
    await pumpButton(tester, rel: release());
    await tapAndWait(tester, expect: '另一个签名');

    expect(calls.map((MethodCall c) => c.method), isNot(contains('installApk')),
        reason: '那一步只会甩一句英文的 UPDATE_INCOMPATIBLE');
    expect(message(tester), contains('另一个签名'));
    expect(message(tester), contains(kInstallPolicyText));
  });

  testWidgets('校验和对不上：删掉包、不安装', (WidgetTester tester) async {
    debugTextFetcher = (Uri _) async =>
        '${'c' * 64}  qingdan-9.9.9-arm64-v8a.apk\n';
    await pumpButton(tester, rel: release());
    await tapAndWait(tester, expect: '校验和');

    expect(calls.map((MethodCall c) => c.method), isNot(contains('installApk')));
    expect(message(tester), contains('校验和不一致'));
    final Directory sub = Directory('${dir.path}/update');
    expect(sub.existsSync() ? sub.listSync().length : 0, 0,
        reason: '坏包必须删掉，不能留着下次误装');
  });

  testWidgets('下载中可以取消：不安装、文件清掉', (WidgetTester tester) async {
    debugApkFetcher = ({
      required Uri url,
      required File target,
      required void Function(int received, int total) onProgress,
      required bool Function() canceled,
    }) async {
      await target.writeAsBytes(bytes.sublist(0, 4));
      for (int i = 0; i < 200; i++) {
        if (canceled()) throw const DownloadCanceled();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        onProgress(i, 200);
      }
    };
    await pumpButton(tester, rel: release());

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey<String>('update-install')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('update-install-cancel')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    expect(message(tester), contains('已取消下载'));
    expect(calls.map((MethodCall c) => c.method), isNot(contains('installApk')));
  });

  testWidgets('通告弹层没有发布信息：自己查一次，已是最新版就不装',
      (WidgetTester tester) async {
    final UpdateChecker checker = UpdateChecker(
      fetch: (String _) async => <String, dynamic>{
        'tag_name': 'v1.0.2',
        'assets': <Object>[],
      },
    );
    await pumpButton(tester, checker: checker);
    await tapAndWait(tester, expect: '已经是最新版');

    expect(message(tester), contains('已经是最新版'));
    expect(calls.map((MethodCall c) => c.method), isNot(contains('installApk')));
  });
}

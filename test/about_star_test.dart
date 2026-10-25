import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/settings/about_section.dart';
import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/update/update_checker.dart' show kRepoUrl;

/// 关于页的 Star 入口（v1.0.14）：只把仓库主页交给系统浏览器。
/// 不拉 Star 数、不走 GitHub API、不申请任何授权。
void main() {
  const MethodChannel channel = MethodChannel('qingdan/system');
  final List<MethodCall> calls = <MethodCall>[];

  void mockChannel(bool Function(MethodCall call) reply) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return reply(call);
    });
  }

  setUp(() => mockChannel((_) => true));
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  /// 覆盖必须在测试体内部设、并在体末撤掉：binding 在测试体结束时查
  /// foundation debug 变量，而 tearDown 在那之后才跑。
  Future<void> asAndroid(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpAbout(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: AboutSection(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String key) async {
    final Finder row = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets('关于页有 Star 行，用克制的一问一答文案',
      (WidgetTester tester) async {
    await asAndroid(() async {
      await pumpAbout(tester);
      expect(find.byKey(const ValueKey<String>('settings-star')), findsOneWidget);
      expect(find.text('喜欢这个项目？'), findsOneWidget);
      expect(find.text('可以去 GitHub 点个 Star'), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsOneWidget);
    });
  });

  testWidgets('点 Star 行 → 系统浏览器收到仓库主页，而不是 issues 或 API',
      (WidgetTester tester) async {
    await asAndroid(() async {
      await pumpAbout(tester);
      await tapRow(tester, 'settings-star');

      expect(calls.map((MethodCall c) => c.method), <String>['openUrl']);
      expect((calls.single.arguments as Map<Object?, Object?>)['url'], kRepoUrl);
      expect(kRepoUrl, 'https://github.com/wazyf-cell/qingdan');
      expect(find.textContaining('打不开浏览器'), findsNothing);
    });
  });

  testWidgets('系统接不住 → 本地回执给出完整地址，不静默失败',
      (WidgetTester tester) async {
    await asAndroid(() async {
      mockChannel((_) => false);
      await pumpAbout(tester);
      await tapRow(tester, 'settings-star');

      expect(calls.single.method, 'openUrl');
      expect(find.text('打不开浏览器。地址是 $kRepoUrl'), findsOneWidget);
    });
  });

  testWidgets('「问题与建议」仍指向 issues，没有被 Star 行串线',
      (WidgetTester tester) async {
    await asAndroid(() async {
      await pumpAbout(tester);
      await tapRow(tester, 'settings-issues');

      expect((calls.single.arguments as Map<Object?, Object?>)['url'],
          '$kRepoUrl/issues');
    });
  });
}

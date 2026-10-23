import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/settings/about_section.dart' show kAppVersion;
import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/update/release_notes.dart';
import 'package:qingdan/update/update_checker.dart' show kRepoUrl;
import 'package:qingdan/update/update_notice.dart';

/// 「升级后首次启动弹一次」的判定与弹层本身。
///
/// 偏好一律用 `SharedPreferences.setMockInitialValues` 注入（与学习通面板同一套做法），
/// 不碰真实磁盘；弹层里的按钮直接走 MethodChannel 假原生侧，理由同
/// `settings_update_rows_test.dart`：测试环境里的 HttpClient 是假的，只能钉通道。
void main() {
  const MethodChannel channel = MethodChannel('qingdan/system');
  final List<MethodCall> calls = <MethodCall>[];

  // 返回值是 Object? 而不是 bool：installTimes 回的是两个时间戳的 Map。
  void mockChannel(Object? Function(MethodCall call) reply) {
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

  /// 装一个「点一下就跑一次入口」的宿主，再点下去。
  ///
  /// 入口要一个 MaterialApp 之下的 context（拿 Navigator 与主题），而它本身是 Future；
  /// 用按钮触发才能像 app.dart 的 post-frame 回调那样，把整个异步链留在同一个
  /// WidgetTester 里观察。
  Future<void> fire(WidgetTester tester,
      {String? version, UpdateNoticeStore? store}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (BuildContext ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                await maybeShowUpdateNotice(ctx,
                    version: version ?? kAppVersion, store: store);
              },
              child: const Text('fire'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('fire'));
    await tester.pumpAndSettle();
  }

  Future<SharedPreferences> seeded(Map<String, Object> seed) async {
    SharedPreferences.setMockInitialValues(seed);
    return SharedPreferences.getInstance();
  }

  Finder dialog() => find.byKey(const ValueKey<String>('update-notice'));

  String noticeText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('update-notice-text')))
      .data!;

  testWidgets('全新安装：不弹，只把当前版本记下（默认读写真实偏好）',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences p = await SharedPreferences.getInstance();

    // 不注入 store：顺带钉住「默认那条路读的就是 SharedPreferences」。
    // 这里的假通道对所有方法都回 true——`installTimes` 拿不到时间戳时
    // 必须按「全新安装」处理，而不是抛异常或误弹。
    await fire(tester);

    expect(dialog(), findsNothing,
        reason: '第一次打开应用的人没有「旧版」这个参照，弹更新说明只是打扰');
    expect(p.getString(kLastSeenVersionKey), kAppVersion);
  });

  testWidgets('从 1.0.2 升上来（偏好里还没那一格）→ 按系统安装时间判定为升级，照样弹',
      (WidgetTester tester) async {
    // 1.0.2 没有更新说明功能，从没写过 app.lastSeenVersion：只看偏好会把
    // 这次升级误当成全新安装，于是真正需要看说明的人永远看不到。
    const int day = 24 * 60 * 60 * 1000;
    mockChannel((MethodCall call) {
      if (call.method != 'installTimes') return true;
      return <String, int>{
        'firstInstallTime': 1000,
        'lastUpdateTime': 1000 + day,
      };
    });
    final SharedPreferences p = await seeded(<String, Object>{});

    await fire(tester, store: UpdateNoticeStore(prefs: p));

    expect(dialog(), findsOneWidget);
    expect(noticeText(tester), releaseNotesFor(kAppVersion));
    expect(p.containsKey(kLastSeenVersionKey), isFalse,
        reason: '弹层还开着时不该提前记成已看过');
  });

  testWidgets('装完立刻打开（两个时间戳同一刻）→ 仍算全新安装，不弹',
      (WidgetTester tester) async {
    mockChannel((MethodCall call) {
      if (call.method != 'installTimes') return true;
      return <String, int>{'firstInstallTime': 1000, 'lastUpdateTime': 1000};
    });
    final SharedPreferences p = await seeded(<String, Object>{});

    await fire(tester, store: UpdateNoticeStore(prefs: p));

    expect(dialog(), findsNothing);
    expect(p.getString(kLastSeenVersionKey), kAppVersion);
  });

  testWidgets('已经是看过的那一版：不弹、也不改写偏好', (WidgetTester tester) async {
    final SharedPreferences p =
        await seeded(<String, Object>{kLastSeenVersionKey: kAppVersion});

    await fire(tester, store: UpdateNoticeStore(prefs: p));

    expect(dialog(), findsNothing);
    expect(p.getString(kLastSeenVersionKey), kAppVersion);
  });

  testWidgets('版本号变了：弹出这一版的说明，点「知道了」关掉并记下新版本',
      (WidgetTester tester) async {
    final SharedPreferences p =
        await seeded(<String, Object>{kLastSeenVersionKey: '1.0.1'});

    await fire(tester, store: UpdateNoticeStore(prefs: p));

    expect(dialog(), findsOneWidget);
    expect(find.text('本次更新内容'), findsOneWidget);
    expect(find.text('v$kAppVersion'), findsOneWidget);
    // 按 kAppVersion 查表而不是写死某句文案：升版本时这条测试跟着走，
    // 钉的是「显示的是**当前版本**的说明」，不是某一句具体的话。
    expect(noticeText(tester), releaseNotesFor(kAppVersion),
        reason: '弹层要显示当前版本的说明，不是别的版本');

    await tester.tap(find.byKey(const ValueKey<String>('update-notice-ok')));
    await tester.pumpAndSettle();

    expect(dialog(), findsNothing);
    expect(p.getString(kLastSeenVersionKey), kAppVersion,
        reason: '关掉之后才记「已看过」，否则下次启动不会再提示');
    // 记上之后同一次运行里再调不会重弹。
    await tester.tap(find.text('fire'));
    await tester.pumpAndSettle();
    expect(dialog(), findsNothing);
  });

  testWidgets('点框外也能关（不必非点按钮），关掉同样算看过',
      (WidgetTester tester) async {
    final SharedPreferences p =
        await seeded(<String, Object>{kLastSeenVersionKey: '1.0.1'});
    await fire(tester, store: UpdateNoticeStore(prefs: p));
    expect(dialog(), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(dialog(), findsNothing);
    expect(p.getString(kLastSeenVersionKey), kAppVersion);
  });

  testWidgets('这一版没写说明：退到通用一句话，不是空框',
      (WidgetTester tester) async {
    final SharedPreferences p =
        await seeded(<String, Object>{kLastSeenVersionKey: '9.9.8'});

    await fire(tester, version: '9.9.9', store: UpdateNoticeStore(prefs: p));

    expect(noticeText(tester), '本次更新没有附说明');
    expect(find.text('v9.9.9'), findsOneWidget);
  });

  testWidgets('「查看发布页」把仓库地址交给系统；接不住时框里给一行回执',
      (WidgetTester tester) async {
    // 覆盖必须在测试体内部设、体末撤掉：binding 在体末查这个 debug 变量，
    // 放进 setUp/tearDown 会让整个文件红（settings_update_rows_test 里有同样的坑）。
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final SharedPreferences p =
          await seeded(<String, Object>{kLastSeenVersionKey: '1.0.1'});
      await fire(tester, store: UpdateNoticeStore(prefs: p));

      await tester.tap(find.byKey(const ValueKey<String>('update-notice-repo')));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'openUrl');
      expect((calls.single.arguments as Map<Object?, Object?>)['url'], kRepoUrl);
      expect(find.byKey(const ValueKey<String>('update-notice-open-failed')),
          findsNothing);

      // 设备上没有能打开网页的应用：留在框里说清楚，而不是静默什么都不发生。
      mockChannel((_) => false);
      await tester.tap(find.byKey(const ValueKey<String>('update-notice-repo')));
      await tester.pumpAndSettle();
      final Text said = tester.widget<Text>(find
          .byKey(const ValueKey<String>('update-notice-open-failed')));
      expect(said.data, contains('打不开'));
      expect(said.data, contains('github.com'));
      expect(dialog(), findsOneWidget, reason: '只是跳不过去，不该顺手把说明关了');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

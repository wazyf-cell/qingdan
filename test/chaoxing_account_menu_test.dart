import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_keys.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/chaoxing/chaoxing_prefs.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_harness.dart';

/// M6B §B4：⋮ 三项（重新登录 / 隐藏列表 / 退出登录，破坏性放最后）+ 两个确认框。
/// 旧代码只有两项且退出**不清 WebView cookie jar**，所以「jar 被清」那条必须红。
void main() {
  const String metaJson =
      '{"c1|h1":{"courseName":"课程甲","title":"第一次作业","dueMs":1760000000000,'
      '"hiddenAtMs":1760000000001,"dead":false}}';

  Map<String, Object> hiddenSeed() => <String, Object>{
        ChaoxingPrefs.kHiddenKey: <String>['c1|h1'],
        ChaoxingPrefs.kHiddenMetaKey: metaJson,
      };

  Future<ChaoxingHarness> openMenu(WidgetTester tester,
      {Map<String, Object> seed = const <String, Object>{}}) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(
        tasks: <ChaoxingTask>[cxHomework('1')], seed: seed);
    h.stubSeams();
    addTearDown(h.restoreSeams);
    await h.pump(tester, width: 411);
    await h.tapIo(tester, h.key(ChaoxingKeys.account));
    return h;
  }

  testWidgets('三项都在，且顺序是 重新登录 → 隐藏列表 → 退出登录',
      (WidgetTester tester) async {
    final ChaoxingHarness h = await openMenu(tester);

    expect(h.key(ChaoxingKeys.menuRelogin), findsOneWidget);
    expect(h.key(ChaoxingKeys.menuHidden), findsOneWidget);
    expect(h.key(ChaoxingKeys.menuLogout), findsOneWidget);
    final double y(String k) => tester.getTopLeft(h.key(k)).dy;
    expect(y(ChaoxingKeys.menuRelogin), lessThan(y(ChaoxingKeys.menuHidden)));
    expect(y(ChaoxingKeys.menuHidden), lessThan(y(ChaoxingKeys.menuLogout)));
  });

  testWidgets('退出登录弹三按钮框；点取消什么都没变', (WidgetTester tester) async {
    final ChaoxingHarness h = await openMenu(tester, seed: hiddenSeed());

    await h.tapIo(tester, h.key(ChaoxingKeys.menuLogout));

    expect(find.text('退出后不再抓取学习通待办，已排的到期提醒会一并取消。'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '退出并清空隐藏列表'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '退出并保留隐藏列表'), findsOneWidget);

    await h.tapIo(tester, find.widgetWithText(TextButton, '取消'));

    expect(h.model.loggedIn, isTrue);
    expect(h.store.entries.containsKey(ChaoxingModel.kCookieKey), isTrue);
    expect(h.jarClears, 0);
    expect(h.prefs.getString(ChaoxingPrefs.kHiddenMetaKey), metaJson);
  });

  testWidgets('退出并保留隐藏列表：凭据清掉、隐藏集与元数据都还在、cookie jar 被清',
      (WidgetTester tester) async {
    final ChaoxingHarness h = await openMenu(tester, seed: hiddenSeed());
    await h.tapIo(tester, h.key(ChaoxingKeys.menuLogout));

    await h.tapIo(tester, find.widgetWithText(FilledButton, '退出并保留隐藏列表'));

    expect(h.model.loggedIn, isFalse);
    expect(h.store.entries.containsKey(ChaoxingModel.kCookieKey), isFalse);
    expect(h.prefs.getStringList(ChaoxingPrefs.kHiddenKey), <String>['c1|h1']);
    expect(h.prefs.getString(ChaoxingPrefs.kHiddenMetaKey), metaJson);
    // 既有缺陷的回归点：logout 必须清 WebView 的 cookie jar。
    expect(h.jarClears, 1);
  });

  testWidgets('退出并清空隐藏列表：两个 prefs 键都被删', (WidgetTester tester) async {
    final ChaoxingHarness h = await openMenu(tester, seed: hiddenSeed());
    await h.tapIo(tester, h.key(ChaoxingKeys.menuLogout));

    await h.tapIo(tester, find.widgetWithText(TextButton, '退出并清空隐藏列表'));

    expect(h.prefs.getStringList(ChaoxingPrefs.kHiddenKey), isNull);
    expect(h.prefs.getString(ChaoxingPrefs.kHiddenMetaKey), isNull);
    expect(h.model.hiddenEntries, isEmpty);
    expect(h.jarClears, 1);
  });

  testWidgets('重新登录先弹两按钮确认框，确认后才走登录页',
      (WidgetTester tester) async {
    final ChaoxingHarness h = await openMenu(tester);

    await h.tapIo(tester, h.key(ChaoxingKeys.menuRelogin));

    expect(find.text('将打开登录页重新获取凭据，登录成功后待办会自动刷新。'), findsOneWidget);
    expect(h.loginLaunches, 0);

    await h.tapIo(tester, find.widgetWithText(FilledButton, '继续'));

    expect(h.loginLaunches, 1);
    // 假 launcher 返回 null（用户没登成）→ 不应触发刷新。
    expect(h.client.fetches, 0);
  });

  testWidgets('隐藏列表入口在菜单里（不是头部按钮）', (WidgetTester tester) async {
    final ChaoxingHarness h = await openMenu(tester, seed: hiddenSeed());

    await h.tapIo(tester, h.key(ChaoxingKeys.menuHidden));

    expect(find.text('隐藏列表'), findsOneWidget);
    expect(find.text('1 项'), findsOneWidget);
    expect(h.key(ChaoxingKeys.hiddenRestore('c1|h1')), findsOneWidget);
  });

  testWidgets('会话失效的被动路径不弹确认框（避免连弹两次）',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: <ChaoxingTask>[], seeded: false);
    h.client.failAuth = true;
    h.stubSeams();
    addTearDown(h.restoreSeams);
    await h.pump(tester, width: 411);
    // 刷新链只走 microtask（假客户端 + mock prefs），两次 pump 就落地了；
    // 不用 pumpAndSettle，免得 loading=true 那一帧的转圈把它吊住。
    await tester.pump();
    await tester.pump();

    // 自动刷新 → 401 → pendingRelogin → 直接开登录页，中间没有确认框。
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.loginLaunches, greaterThan(0));
  });
}

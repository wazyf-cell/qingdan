import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/chaoxing/chaoxing_keys.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/chaoxing/chaoxing_prefs.dart';
import 'package:qingdan/features/settings/chaoxing_section.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'chaoxing_harness.dart';

/// M6-C §C5：设置里的「学习通」节。
///
/// 三条硬要求各自有断言：① 已登录/未登录两套文案且**页面上找不到任何凭据**；
/// ② 三个动作行都在且可点；③ 点退出弹的是 B4 那个三按钮确认框（走的是同一条
/// `chaoxing_actions.dart` 路径，不是本节自己重写的一份）。
/// 双端各 pump 一次（总纲铁律 8）：411 与 1280 都跑一遍，防窄屏溢出。
void main() {
  /// 隐藏项元数据种子：课程名 / 标题都是合成值（形状取自真实页面，仓库是 public）。
  const String metaJson =
      '{"c1|h1":{"courseName":"课程甲","title":"第一次作业","dueMs":1760000000000,'
      '"hiddenAtMs":1760000000001,"dead":false}}';

  Map<String, Object> hiddenSeed() => <String, Object>{
        ChaoxingPrefs.kHiddenKey: <String>['c1|h1'],
        ChaoxingPrefs.kHiddenMetaKey: metaJson,
      };

  /// 装 harness 的模型与假 WebView 注入点，但 pump 的是**设置里的节**而非面板。
  Future<ChaoxingHarness> pumpSection(WidgetTester tester,
      {double width = 411,
      bool loggedIn = true,
      bool seeded = true,
      Map<String, Object> seed = const <String, Object>{}}) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(
      tasks: <ChaoxingTask>[cxHomework('1')],
      loggedIn: loggedIn,
      seeded: seeded,
      seed: seed,
    );
    h.stubSeams();
    addTearDown(h.restoreSeams);
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ChaoxingModel>.value(value: h.model),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: const ChaoxingSection(),
          ),
        ),
      ),
    ));
    await tester.pump();
    return h;
  }

  Finder key(String id) => find.byKey(ValueKey<String>(id));
  final Finder relogin = key(kChaoxingSectionReloginKey);
  final Finder logoutRow = key(kChaoxingSectionLogoutKey);
  final Finder hiddenRow = key(kChaoxingSectionHiddenKey);

  /// 三个动作行都在，且都不是死行（onTap 必须接上）。
  void expectThreeActions(WidgetTester tester) {
    for (final String id in <String>[
      kChaoxingSectionReloginKey,
      kChaoxingSectionHiddenKey,
      kChaoxingSectionLogoutKey,
    ]) {
      final Finder f = key(id);
      expect(f, findsOneWidget, reason: '$id 缺失');
      final ListTile tile = tester.widget<ListTile>(f);
      expect(tile.onTap, isNotNull, reason: '$id 是点了没反应的死行');
    }
    // 顺序：重新登录 → 隐藏列表 → 退出登录（破坏性放最后，与面板 ⋮ 一致）。
    double y(String k) => tester.getTopLeft(key(k)).dy;
    expect(y(kChaoxingSectionReloginKey), lessThan(y(kChaoxingSectionHiddenKey)));
    expect(y(kChaoxingSectionHiddenKey), lessThan(y(kChaoxingSectionLogoutKey)));
  }

  testWidgets('已登录：状态卡给时刻，三个动作行可点（411 与 1280 各一次）',
      (WidgetTester tester) async {
    for (final double w in <double>[411, 1280]) {
      final ChaoxingHarness h = await pumpSection(tester, width: w);
      expect(tester.takeException(), isNull, reason: '宽度 $w 出现布局异常');
      expect(find.text('已登录'), findsOneWidget);
      // kCxNow = 2026-10-18 12:00，seeded 时 fetchedAt 就是它。
      expect(find.text('最近抓取：2026-10-18 12:00'), findsOneWidget);
      expectThreeActions(tester);
      // 铁律 6：页面上任何位置都不能出现凭据片段。
      expect(find.textContaining(kFakeCookie), findsNothing);
      expect(h.store.entries.containsKey(ChaoxingModel.kCookieKey), isTrue);
    }
  });

  testWidgets('未登录：状态卡说未登录 + 从未抓取，动作行依旧在（两端各一次）',
      (WidgetTester tester) async {
    for (final double w in <double>[411, 1280]) {
      await pumpSection(tester, width: w, loggedIn: false, seeded: false);
      expect(tester.takeException(), isNull, reason: '宽度 $w 出现布局异常');
      expect(find.text('未登录'), findsOneWidget);
      expect(find.text('已登录'), findsNothing);
      expect(find.text('最近抓取：从未抓取'), findsOneWidget);
      expectThreeActions(tester);
    }
  });

  testWidgets('两段说明：刷新只有两处 + 不落库不同步', (WidgetTester tester) async {
    await pumpSection(tester);
    expect(key(kChaoxingSectionStatusKey), findsOneWidget);
    expect(find.textContaining('刷新只在两处'), findsOneWidget);
    expect(find.textContaining('不写入应用数据库、不参与设备间同步'), findsOneWidget);
    expect(find.textContaining('退出登录会清除凭据与提醒快照'), findsOneWidget);
  });

  testWidgets('隐藏列表行显示条数', (WidgetTester tester) async {
    await pumpSection(tester, seed: hiddenSeed());
    expect(find.text('1 项'), findsOneWidget);
  });

  testWidgets('点退出登录弹 B4 的三按钮确认框；取消后凭据与隐藏集都不动',
      (WidgetTester tester) async {
    final ChaoxingHarness h =
        await pumpSection(tester, seed: hiddenSeed());
    await h.tapIo(tester, logoutRow);

    expect(find.text('退出后不再抓取学习通待办，已排的到期提醒会一并取消。'),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, '退出并清空隐藏列表'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '退出并保留隐藏列表'), findsOneWidget);

    await h.tapIo(tester, find.widgetWithText(TextButton, '取消'));
    expect(h.model.loggedIn, isTrue);
    expect(h.store.entries.containsKey(ChaoxingModel.kCookieKey), isTrue);
    expect(h.jarClears, 0);
    expect(h.prefs.getString(ChaoxingPrefs.kHiddenMetaKey), metaJson);
  });

  testWidgets('确认框选「退出并保留隐藏列表」：走的是面板那条退出路径（清了 cookie jar）',
      (WidgetTester tester) async {
    final ChaoxingHarness h =
        await pumpSection(tester, seed: hiddenSeed());
    await h.tapIo(tester, logoutRow);
    await h.tapIo(tester, find.widgetWithText(FilledButton, '退出并保留隐藏列表'));

    expect(h.model.loggedIn, isFalse);
    expect(h.store.entries.containsKey(ChaoxingModel.kCookieKey), isFalse);
    expect(h.jarClears, 1);
    expect(h.prefs.getStringList(ChaoxingPrefs.kHiddenKey), <String>['c1|h1']);
    // 状态卡随之改变（同一份模型，不需要手动刷新）。
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('最近抓取：从未抓取'), findsOneWidget);
  });

  testWidgets('点重新登录：先弹两按钮确认框，确认后才打开登录页',
      (WidgetTester tester) async {
    final ChaoxingHarness h = await pumpSection(tester);
    await h.tapIo(tester, relogin);

    expect(find.text('将打开登录页重新获取凭据，登录成功后待办会自动刷新。'),
        findsOneWidget);
    expect(h.loginLaunches, 0);

    await h.tapIo(tester, find.widgetWithText(FilledButton, '继续'));
    expect(h.loginLaunches, 1);
  });

  testWidgets('点隐藏列表 push B6 的整页', (WidgetTester tester) async {
    final ChaoxingHarness h = await pumpSection(tester, seed: hiddenSeed());
    await h.tapIo(tester, hiddenRow);

    expect(
        find.byKey(ChaoxingKeys.vkey(ChaoxingKeys.hiddenRestore('c1|h1'))),
        findsOneWidget);
    expect(find.byKey(ChaoxingKeys.vkey(ChaoxingKeys.hiddenRestoreAll)),
        findsOneWidget);
  });

  testWidgets('prefs 真的被读到：隐藏集为空时计数是 0 项', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpSection(tester);
    expect(find.text('0 项'), findsOneWidget);
  });
}

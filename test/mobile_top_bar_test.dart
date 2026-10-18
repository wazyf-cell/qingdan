import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:qingdan/features/shell/mobile_top_bar.dart';
import 'package:qingdan/features/shell/sidebar/sync_slot.dart';

import 'mobile_nav_harness.dart';

/// 窄屏 56dp 顶栏（`mobile_top_bar.dart`）。
///
/// 钉的是「不许有点了没反应的死图标」这条定案：顶栏原先挂着一颗
/// `IconButton(onPressed: null, tooltip: '搜索')`。F10 搜索只有数据层
/// （`TaskDao.search`），界面一条路径都没有——清单页页头没有任何输入框，学习通
/// 那个搜索只在它自己的筛选弹层里。所以入口整颗删掉，而不是留一个「看起来能用
/// 却按不动」的放大镜，也不给一个会撒谎的 tooltip。
///
/// 删完还得确认排版没塌：标题 + 同步状态槽两样都在，411 与 1280 各 pump 一次
/// （1280 那一遍是**反向**确认：桌面形态根本不该出现 MobileTopBar）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late MobileNavHarness h;

  setUp(() async {
    h = await MobileNavHarness.open();
  });

  tearDown(() async => h.close());

  testWidgets('窄屏顶栏没有死的搜索图标，标题与同步状态槽仍在位', (tester) async {
    await h.pumpAtWidth(tester, 411);

    expect(find.byType(MobileTopBar), findsOneWidget,
        reason: '411dp 走的就是窄屏壳，顶栏得在');
    expect(find.byIcon(Icons.search), findsNothing,
        reason: '占位要么说清原因，要么别出现：没有全局搜索就不许摆一颗放大镜');
    expect(find.byTooltip('搜索'), findsNothing);
    // 排版没塌：页标题 + 同步状态槽两样照旧渲染。
    expect(topBarTitle, findsOneWidget);
    expect(titleOf(tester, topBarTitle), isNotEmpty);
    expect(find.byType(SyncSlot), findsOneWidget,
        reason: '同步状态槽是 M5 从抽屉提到顶栏的，删搜索图标不能顺手把它带走');
    expect(tester.takeException(), isNull, reason: '顶栏不得有 RenderFlex 溢出');
  });

  testWidgets('桌面 1280：整个应用同样没有任何搜索入口图标', (tester) async {
    await h.pumpAtWidth(tester, 1280);

    expect(find.byType(MobileTopBar), findsNothing,
        reason: '≥720dp 不用窄屏壳，顶栏不该出现');
    expect(find.byIcon(Icons.search), findsNothing,
        reason: '侧栏 / 图标栏那条线上也不该有点了没反应的放大镜');
    expect(tester.takeException(), isNull);
  });
}

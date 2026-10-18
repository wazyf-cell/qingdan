import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_grouping.dart';
import 'package:qingdan/features/chaoxing/chaoxing_header.dart';
import 'package:qingdan/features/chaoxing/chaoxing_keys.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/chaoxing/chaoxing_prefs.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/theme/app_colors.dart';

import 'chaoxing_harness.dart';

/// M6B §B1：面板头压到一行。前两条是「必须先看到它红」的几何断言——
/// 旧版面板头 252dp（标题行 56 + 页签 40 + 间距 8 + 工具栏 148），
/// 列表 top 会在 252 附近、且 `find.byType(ListView)` 会命中工具栏那条
/// 横向 ListView（旧代码里就有两个 ListView），两条都过不去。
void main() {
  List<ChaoxingTask> tasks() => <ChaoxingTask>[
        cxHomework('1', dueAt: kCxNow.add(const Duration(hours: 3))),
        cxHomework('2', dueAt: kCxNow.add(const Duration(days: 5))),
        cxActivity('3', clazzId: 'z3'),
      ];

  testWidgets('411dp：面板头只有一行，列表拿到剩余全部高度', (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester, width: 411, height: 915);

    // 面板自己的「学习通待办」标题删掉（壳顶栏已经写了「学习通」）。
    expect(find.text('学习通待办'), findsNothing);

    final Rect list = tester.getRect(find.byType(ListView));
    expect(list.top, lessThanOrEqualTo(ChaoxingHeader.totalHeight + 0.1));
    expect(tester.getSize(find.byType(ListView)).height / 915,
        greaterThanOrEqualTo(0.85));

    expect(h.key(ChaoxingKeys.tabHomework), findsOneWidget);
    expect(h.key(ChaoxingKeys.tabActivity), findsOneWidget);
    expect(h.key(ChaoxingKeys.stale), findsOneWidget);
    expect(h.key(ChaoxingKeys.refresh), findsOneWidget);
    expect(h.key(ChaoxingKeys.filter), findsOneWidget);
    expect(h.key(ChaoxingKeys.account), findsOneWidget);
    expect(tester.getRect(h.key(ChaoxingKeys.refresh)).bottom,
        lessThanOrEqualTo(64));

    // 搜索与排序**不在**头部（搬进筛选弹层了）。
    expect(find.byType(TextField), findsNothing);
    expect(find.text('截止最早优先'), findsNothing);
  });

  testWidgets('「N 分钟前」在刷新按钮左边（用户明确要求的相对位置）',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester);

    final Rect stale = tester.getRect(h.key(ChaoxingKeys.stale));
    final Rect refresh = tester.getRect(h.key(ChaoxingKeys.refresh));
    expect(stale.right, lessThanOrEqualTo(refresh.left));
    expect(tester.widget<Text>(h.key(ChaoxingKeys.stale)).data, '刚刚');
  });

  testWidgets('超过 15 分钟：文案追加「建议刷新」', (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester);

    // 首帧的自动刷新机会已经被「距上次 0 分钟」用掉（§B7），这里只把时间拨旧。
    h.model.fetchedAt =
        kCxNow.subtract(ChaoxingModel.kStaleAfter + const Duration(minutes: 1));
    h.model.tick();
    await tester.pump();

    expect(tester.widget<Text>(h.key(ChaoxingKeys.stale)).data,
        '16 分钟前 · 建议刷新');
  });

  testWidgets('生效筛选数 = 2 时 Badge 渲染出「2」（不断言 badge.count）',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    h.model.settings = h.model.settings
        .copyWith(onlyUnfinished: true, onlySubmittable: true);
    await h.pump(tester);

    expect(find.text('2'), findsOneWidget);
    final Badge badge = tester.widget<Badge>(find.ancestor(
        of: find.byWidget(const Icon(Icons.tune)),
        matching: find.byType(Badge)));
    // 默认底色是 colorScheme.error（红），必须被显式换成主题色（总纲陷阱表）。
    final AppColors colors =
        AppColors.of(tester.element(find.byType(Badge)));
    expect(badge.backgroundColor, colors.accent);
  });

  testWidgets('点筛选图标 → 弹层里有搜索、课程、两个开关、排序、统计与重置',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester);

    await h.tapIo(tester, h.key(ChaoxingKeys.filter));

    expect(h.key(ChaoxingKeys.filterSearch), findsOneWidget);
    expect(h.key(ChaoxingKeys.filterCourse), findsOneWidget);
    expect(h.key(ChaoxingKeys.filterUnfinished), findsOneWidget);
    expect(h.key(ChaoxingKeys.filterSubmittable), findsOneWidget);
    expect(h.key(ChaoxingKeys.filterSort), findsOneWidget);
    expect(h.key(ChaoxingKeys.filterCount), findsOneWidget);
    expect(h.key(ChaoxingKeys.filterReset), findsOneWidget);
    expect(h.key(ChaoxingKeys.filterApply), findsOneWidget);

    // 开关即时生效并落 prefs。
    await h.tapIo(tester, h.key(ChaoxingKeys.filterUnfinished));
    expect(h.model.settings.onlyUnfinished, isTrue);
    expect(h.prefs.getBool(ChaoxingPrefs.kOnlyUnfinishedKey), isTrue);

    await h.tapIo(tester, h.key(ChaoxingKeys.filterApply));
    expect(h.key(ChaoxingKeys.filterSearch), findsNothing);
  });

  testWidgets('弹层里设 2 个条件后关掉，头部筛选图标带蓝色 2',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester);
    await h.tapIo(tester, h.key(ChaoxingKeys.filter));
    await h.tapIo(tester, h.key(ChaoxingKeys.filterUnfinished));
    await h.tapIo(tester, h.key(ChaoxingKeys.sortOption(ChaoxingSortBy.name.name)));
    await h.tapIo(tester, h.key(ChaoxingKeys.filterApply));

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('点页签切到「课堂活动」：列表只剩活动条目', (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester);

    await h.tapIo(tester, h.key(ChaoxingKeys.tabActivity));

    expect(h.model.settings.tab, ChaoxingTab.activities);
    expect(h.cardOf(cxActivity('3', clazzId: 'z3')), findsOneWidget);
    expect(h.cardOf(cxHomework('1')), findsNothing);
  });

  testWidgets('1280dp 桌面形态同样只有一行头部（双端各 pump 一次）',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester, width: 1280, height: 800);

    expect(find.text('学习通待办'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(ListView)).top,
        lessThanOrEqualTo(ChaoxingHeader.totalHeight + 0.1));
    expect(h.key(ChaoxingKeys.filter), findsOneWidget);
  });
}

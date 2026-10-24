import 'dart:async';

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

  testWidgets('更新时间在刷新按钮左边，且永不出现半个省略号',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester);

    final Rect stale = tester.getRect(h.key(ChaoxingKeys.stale));
    final Rect refresh = tester.getRect(h.key(ChaoxingKeys.refresh));
    expect(stale.right, lessThanOrEqualTo(refresh.left));
    // 用户实测过「只剩一个 …」的形态。测试字体每个字都是一个 fontSize 见方的
    // 方块（宽度约为真实字形的 1.6 倍），411dp 下这一格只有 76dp，所以这里
    // **不要求显示出来**，只要求：要么整句、要么不显示，绝不留省略号。
    expect(find.textContaining('…'), findsNothing);
    // 文案本体在 `chaoxing_status_text_test.dart` 里逐条钉，位置与「不截断」
    // 留在这条端到端断言里。
    expect(
        stale.width == 0 || find.text('12:00 更新').evaluate().isNotEmpty, isTrue);
  });

  testWidgets('360dp 窄屏：刷新时间必须看得见，不能被整句吞掉',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester, width: 360, height: 780);

    // 完整句在测试字体下放不下时允许退成紧凑时间，但**不能什么都不显示**。
    final bool full = find.text('12:00 更新').evaluate().isNotEmpty;
    final bool compact = find.text('12:00').evaluate().isNotEmpty;
    expect(full || compact, isTrue,
        reason: '状态格整句被隐藏时用户看不到上次刷新时间（2026-10-24 用户报）');
    expect(find.textContaining('…'), findsNothing);
  });

  testWidgets('360dp 刷新失败：时间仍在，刷新按钮带红点', (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    h.model.error = TimeoutException('x');
    await h.pump(tester, width: 360, height: 780);

    expect(find.text('12:00'), findsOneWidget, reason: '失败时也得看得到上次成功的时间');
    final Badge dot = tester.widget<Badge>(find.descendant(
        of: h.key(ChaoxingKeys.refresh), matching: find.byType(Badge)));
    expect(dot.isLabelVisible, isTrue, reason: '窄屏只剩图标时，红点是失败唯一还看得见的信号');
  });

  testWidgets('超过 15 分钟：时间后面追加「建议刷新」（宽屏渲染）',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    await h.pump(tester, width: 600, height: 915);

    // 首帧的自动刷新机会已经被「距上次 0 分钟」用掉（§B7），这里只把时间拨旧。
    h.model.fetchedAt =
        kCxNow.subtract(ChaoxingModel.kStaleAfter + const Duration(minutes: 1));
    h.model.tick();
    await tester.pump();

    // 12:00 往前 16 分钟 = 11:44（同一天，所以不带日期）。
    expect(find.text('11:44 更新 · 建议刷新'), findsOneWidget);
  });

  testWidgets('生效筛选数 = 2 时 Badge 渲染出「2」（不断言 badge.count）',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    h.model.settings = h.model.settings
        .copyWith(onlyUnfinished: true, onlySubmittable: true);
    await h.pump(tester);

    expect(find.text('2'), findsOneWidget);
    // 用 key 定位而不是 `find.byWidget(const Icon(Icons.tune))`：后者在
    // IconButton(M3) 内部包装下匹配不到（实测 0 candidates），key 路径更稳。
    // 刷新按钮上的错误红点也是 Badge，所以这里必须限定在筛选图标下面取。
    final Finder filterBadge = find.descendant(
        of: h.key(ChaoxingKeys.filter), matching: find.byType(Badge));
    final Badge badge = tester.widget<Badge>(filterBadge);
    // 默认底色是 colorScheme.error（红），必须被显式换成主题色（总纲陷阱表）。
    final AppColors colors = AppColors.of(tester.element(filterBadge));
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
    // 排序五档在弹层自己的滚动区里，最后一档默认在视口外——用户也是滑到它才点的
    // （`ensureVisible` 对「顶部刚露出 7px」的档位在 3.47 下判成已可见，不滚）。
    await tester.dragUntilVisible(
      h.key(ChaoxingKeys.sortOption(ChaoxingSortBy.name.name)),
      h.key(ChaoxingKeys.filterSort),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
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

  testWidgets('停在「课堂活动」时点刷新：活动当场补回来，不会刷成空列表',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks());
    h.client.activities = <ChaoxingTask>[cxActivity('3', clazzId: 'z3')];
    await h.pump(tester);
    await h.tapIo(tester, h.key(ChaoxingKeys.tabActivity));
    expect(h.client.activityFetches, 1);

    // 刷新会把活动作废（它们属于上一次快照）。用户正站在这一页上按的刷新，
    // 结果列表空三秒、要切走再切回才恢复——v1.0.2 真机上就是这么难看的。
    await h.tapIo(tester, h.key(ChaoxingKeys.refresh));

    expect(h.client.activityFetches, 2, reason: '刷新后要按需重拉一次');
    expect(h.model.activitiesLoaded, isTrue);
    expect(h.cardOf(cxActivity('3', clazzId: 'z3')), findsOneWidget);
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_card.dart';
import 'package:qingdan/features/chaoxing/chaoxing_detail_page.dart';
import 'package:qingdan/features/chaoxing/chaoxing_keys.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_harness.dart';

/// M6B §B2：卡片从右往左滑，右侧揭示「详情 / 隐藏」；长按保留为隐藏的兜底。
/// 旧代码只有 `InkWell(onLongPress:)`、没有滑动容器，所以第 1、2 条必须红。
void main() {
  /// 12 条撑出可滚动的列表（「滚动时全部收回」需要列表真的能滚）。
  List<ChaoxingTask> many(int n) => <ChaoxingTask>[
        for (int i = 1; i <= n; i++) cxHomework('$i', title: '第$i次作业'),
      ];

  testWidgets('从右往左滑 → 右侧出现「详情」「隐藏」且都在可视区内',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    final List<ChaoxingTask> tasks = many(12);
    await h.start(tasks: tasks);
    await h.pump(tester, width: 411);

    await h.swipeLeft(tester, tasks[0]);

    expect(h.detailOf(tasks[0]), findsOneWidget);
    expect(h.hideOf(tasks[0]), findsOneWidget);
    // 顺序：详情在左、隐藏在右（用户裁决）。
    expect(tester.getCenter(h.detailOf(tasks[0])).dx,
        lessThan(tester.getCenter(h.hideOf(tasks[0])).dx));
    // 两个按钮都落在屏幕内。
    for (final Finder f in <Finder>[h.detailOf(tasks[0]), h.hideOf(tasks[0])]) {
      final Rect r = tester.getRect(f);
      expect(r.right, lessThanOrEqualTo(411));
      expect(r.left, greaterThanOrEqualTo(0));
    }
    // 卡片主体向左让位（-144dp：两个 72dp 按钮的宽度）。
    expect(tester.getRect(find.byType(ChaoxingCard).first).left, lessThan(0));
  });

  testWidgets('点「隐藏」→ 卡片从列表消失（无截止 → 不弹确认）',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    final List<ChaoxingTask> tasks = many(12);
    await h.start(tasks: tasks);
    await h.pump(tester, width: 411);
    await h.swipeLeft(tester, tasks[0]);

    await h.tapIo(tester, h.hideOf(tasks[0]));

    expect(h.cardOf(tasks[0]), findsNothing);
    expect(h.model.settings.hidden, contains(tasks[0].key));
    expect(find.text('已隐藏 · 可在 ⋮ → 隐藏列表 里恢复'), findsOneWidget);
  });

  testWidgets('纵向拖卡片 → 列表滚动，不揭示按钮', (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    final List<ChaoxingTask> tasks = many(12);
    await h.start(tasks: tasks);
    await h.pump(tester, width: 411);

    await tester.drag(h.cardOf(tasks[0]), const Offset(0, -60));
    await tester.pumpAndSettle();

    expect(h.detailOf(tasks.first), findsNothing);
    expect(h.model.settings.hidden, isEmpty);
  });

  testWidgets('打开 A 再打开 B → A 自动收回（同时只允许一张）',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    final List<ChaoxingTask> tasks = many(12);
    await h.start(tasks: tasks);
    await h.pump(tester, width: 411);

    await h.swipeLeft(tester, tasks[0]);
    expect(h.detailOf(tasks[0]), findsOneWidget);

    await h.swipeLeft(tester, tasks[1]);

    expect(h.detailOf(tasks[0]), findsNothing);
    expect(h.detailOf(tasks[1]), findsOneWidget);
  });

  testWidgets('列表滚动 → 打开着的卡片全部收回', (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    final List<ChaoxingTask> tasks = many(12);
    await h.start(tasks: tasks);
    await h.pump(tester, width: 411);
    await h.swipeLeft(tester, tasks[0]);

    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(h.detailOf(tasks[0]), findsNothing);
  });

  testWidgets('长按仍然隐藏（保留兜底手势）', (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    final List<ChaoxingTask> tasks = many(12);
    await h.start(tasks: tasks);
    await h.pump(tester, width: 411);

    await tester.runAsync(() async {
      await tester.longPress(h.cardOf(tasks[0]));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();

    expect(h.cardOf(tasks[0]), findsNothing);
    expect(h.model.settings.hidden, contains(tasks[0].key));
  });

  testWidgets('打开态下点卡片主体 = 收回，不触发详情', (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    final List<ChaoxingTask> tasks = many(12);
    await h.start(tasks: tasks);
    h.stubSeams();
    addTearDown(h.restoreSeams);
    await h.pump(tester, width: 411);
    await h.swipeLeft(tester, tasks[0]);

    await h.tapIo(tester, find.byType(ChaoxingCard).first);

    expect(h.detailOf(tasks[0]), findsNothing);
    expect(h.detailLaunches, 0);
  });

  group('详情按钮（§B3：应用内 WebView 看真实题目）', () {
    testWidgets('作业卡片点详情 → 路由被 push，页面标题是课程名',
        (WidgetTester tester) async {
      final ChaoxingHarness h = ChaoxingHarness();
      final List<ChaoxingTask> tasks = <ChaoxingTask>[
        cxHomework('1', clazzId: 'z1', course: '课程乙'),
      ];
      await h.start(tasks: tasks);
      int launches = 0;
      // 真实详情页会 build `InAppWebView`（测试环境没有平台实现），
      // 所以只替换 WebView，路由与页面本身走真代码。
      chaoxingDetailLauncher = (BuildContext context, ChaoxingTask task) {
        launches++;
        showChaoxingDetail(context, task,
            webView: (BuildContext _, String url, ValueChanged<Uri?> _) =>
                Center(child: Text('WebView:$url')));
      };
      addTearDown(h.restoreSeams);
      await h.pump(tester, width: 411);
      await h.swipeLeft(tester, tasks[0]);

      await h.tapIo(tester, h.detailOf(tasks[0]));

      expect(find.byType(ChaoxingDetailPage), findsOneWidget);
      expect(find.text('课程乙'), findsOneWidget);
      expect(launches, 1);
      // URL 来自 clazzId（缺它就只会走降级页）。
      expect(find.textContaining('clazzid=z1'), findsOneWidget);
    });

    testWidgets('拼不出 URL（课堂活动）→ 详情页如实降级，不白屏',
        (WidgetTester tester) async {
      final ChaoxingHarness h = ChaoxingHarness();
      final List<ChaoxingTask> tasks = <ChaoxingTask>[
        cxActivity('9', clazzId: 'z9'),
      ];
      await h.start(tasks: tasks);
      await h.pump(tester, width: 411);
      await h.swipeLeft(tester, tasks[0]);

      await h.tapIo(tester, h.detailOf(tasks[0]));

      expect(find.byType(ChaoxingDetailPage), findsOneWidget);
      expect(find.text('该类型暂不支持查看详情'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_keys.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_harness.dart';

/// M6B §B7：刷新只剩两处——进程首次进入（自动一次，距上次 <15 分钟则跳过）
/// 与头部 ⟳。下拉刷新已取消；登录成功那次保留。
/// 「切走再切回不再刷」这条在旧代码上必须红（旧 initState 每次都 refresh）。
void main() {
  List<ChaoxingTask> fetched() => <ChaoxingTask>[cxHomework('1')];

  testWidgets('首次进入自动刷一次；切走再切回来仍然是 1 次',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: fetched(), seeded: false);
    await h.pump(tester, width: 411);
    await tester.pump();
    await tester.pump();

    expect(h.client.fetches, 1);
    expect(h.model.tasks.length, 1);

    // 切到别的页签（面板被卸载）再切回来。
    await h.pump(tester, width: 411, visible: false);
    await h.pump(tester, width: 411, visible: true);
    await tester.pump();
    await tester.pump();

    expect(h.client.fetches, 1);
    expect(h.model.autoRefreshedThisLaunch, isTrue);
  });

  testWidgets('距上次不足 15 分钟：这次自动刷新机会直接跳过',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: fetched()); // seeded = 刚刚拉过
    await h.pump(tester, width: 411);
    await tester.pump();
    await tester.pump();

    expect(h.client.fetches, 0);
    expect(h.model.autoRefreshedThisLaunch, isTrue);
  });

  testWidgets('新进程（新模型实例）+ 上次拉取 20 分钟前 → 自动刷一次',
      (WidgetTester tester) async {
    final ChaoxingHarness old = ChaoxingHarness();
    await old.start(tasks: fetched());
    expect(old.client.fetches, 0);

    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: fetched(), seeded: false);
    h.model.fetchedAt =
        kCxNow.subtract(ChaoxingModel.kStaleAfter + const Duration(minutes: 5));
    await h.pump(tester, width: 411);
    await tester.pump();
    await tester.pump();

    expect(h.client.fetches, 1);
  });

  testWidgets('点头部 ⟳ 再刷一次；一分钟一次的 ticker 不发请求',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: fetched());
    await h.pump(tester, width: 411);
    expect(h.client.fetches, 0);

    await h.tapIo(tester, h.key(ChaoxingKeys.refresh));
    expect(h.client.fetches, 1);

    // 倒计时的周期定时器只推进时间基准，不能变成第三个刷新入口。
    await tester.pump(const Duration(minutes: 1));
    expect(h.client.fetches, 1);
  });

  testWidgets('没有下拉刷新：RefreshIndicator 不存在，向下拉列表不产生请求',
      (WidgetTester tester) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(
        tasks: <ChaoxingTask>[
          for (int i = 1; i <= 12; i++) cxHomework('$i'),
        ]);
    await h.pump(tester, width: 411);
    expect(find.byType(RefreshIndicator), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 160));
    await tester.pump();
    await tester.pump();

    expect(h.client.fetches, 0);
  });

  test('登录成功那次刷新保留（saveCookie → refresh）', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(loggedIn: false, seeded: false);
    expect(h.client.fetches, 0);

    await h.model.saveCookie(kFakeCookie);

    expect(h.client.fetches, 1);
    expect(h.model.loggedIn, isTrue);
    expect(h.store.entries[ChaoxingModel.kCookieKey], kFakeCookie);
  });

  test('刷新失败也算「这次机会用掉了」，不会每次切页签都重打超星', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(seeded: false);
    h.client.failAuth = true;
    await h.model.autoRefreshOnce();
    expect(h.client.fetches, 1);
    expect(h.model.pendingRelogin, isTrue);

    h.client.failAuth = false;
    await h.model.autoRefreshOnce();
    expect(h.client.fetches, 1, reason: '第二次不该再发请求');
  });
}

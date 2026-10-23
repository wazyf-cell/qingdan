import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/import/chaoxing/chaoxing_client.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_harness.dart';

/// 刷新的三件事（v1.0.3）：作业先上屏、活动改成按需、失败不能伪装成空列表。
void main() {
  test('作业一到就上屏，那时整次刷新还没结束、时间也不写（D1）', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: <ChaoxingTask>[cxHomework('1'), cxHomework('2')]);
    h.client.waveGate = Completer<void>();

    final Future<void> refreshing = h.model.refresh();
    // 让 refresh 走完「读凭据 → 调 fetchEager → 第一波回调」这几跳。
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(h.model.tasks, isNotEmpty, reason: '作业那一段到了就该显示');
    expect(h.model.loading, isTrue);
    expect(h.model.statusText, '更新中…',
        reason: '考试还没到，这时候写时间是骗人的');

    h.client.waveGate!.complete();
    await refreshing;
    expect(h.model.loading, isFalse);
    expect(h.model.statusText, endsWith('更新'));
  });

  test('刷新失败：旧列表与旧时间都留着，只多一条失败原因（F1）', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start();
    final List<Object> before = List<Object>.of(h.model.tasks);
    final DateTime? at = h.model.fetchedAt;

    h.client.failAuth = true;
    await h.model.refresh();

    expect(h.model.tasks, before, reason: '清空列表会让「连不上」长得像「今天没作业」');
    expect(h.model.fetchedAt, at, reason: '时间代表上次成功，失败时不动它');
    expect(h.model.error, isA<ChaoxingAuthException>());
    expect(h.model.statusIsError, isTrue);
    expect(h.model.statusText, startsWith('刷新失败：会话已失效'));
    expect(h.model.statusText, contains('· 12:00'), reason: '要能看出正看着的是几点的数据');
    expect(h.model.loggedIn, isFalse);
    expect(h.model.pendingRelogin, isTrue);
  });

  test('失败之后再成功：失败原因清掉，时间跟着更新', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start();
    h.client.failAuth = true;
    await h.model.refresh();
    expect(h.model.error, isNotNull);

    h.client.failAuth = false;
    await h.model.refresh();
    expect(h.model.error, isNull);
    expect(h.model.statusIsError, isFalse);
    expect(h.model.statusText, '12:00 更新');
  });

  test('课堂活动按需：刷新不拉，切到页签拉一次，再切不重复拉', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start();

    await h.model.refresh();
    expect(h.client.activityFetches, 0, reason: '刷新不该再顺带抓活动（它占 3 秒）');

    await h.model.ensureActivitiesLoaded();
    expect(h.client.activityFetches, 1);

    await h.model.ensureActivitiesLoaded();
    expect(h.client.activityFetches, 1, reason: '已经拉过就别再敲超星');
  });

  test('下一次刷新把活动作废，切回页签会重拉（活动属于那一次快照）', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start();
    await h.model.refresh();
    await h.model.ensureActivitiesLoaded();
    expect(h.client.activityFetches, 1);

    await h.model.refresh();
    expect(h.model.activitiesLoaded, isFalse);
    await h.model.ensureActivitiesLoaded();
    expect(h.client.activityFetches, 2);
  });

  test('拉活动失败也走同一条失败行，不静默', () async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start();
    await h.model.refresh();
    h.client.failActivities = true;

    await h.model.ensureActivitiesLoaded();
    expect(h.model.error, isNotNull);
    expect(h.model.statusIsError, isTrue);
    expect(h.model.activitiesLoading, isFalse);
  });
}

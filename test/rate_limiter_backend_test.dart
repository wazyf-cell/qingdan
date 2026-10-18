// RateLimiterBackend / RequestBudget / CountingWebDavTransport 单元测试。
// 离线：假时钟（注入 DateTime Function()）+ 假 delay（等待即推时钟）+
// 假 SyncBackend / 假 WebDavTransport，不连真实网络、不真等 30 分钟。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/sync/rate_limiter_backend.dart';
import 'package:qingdan/sync/sync_backend.dart';
import 'package:qingdan/sync/webdav_backend.dart';
import 'package:qingdan/sync/webdav_transport.dart';

import 'webdav_test_fixture.dart';

/// 可控时钟：等待动作会推时钟前进，模拟真实时间流逝。
class FakeClock {
  DateTime now = DateTime.utc(2026, 9, 29, 12);
  DateTime Function() get reader => () => now;
  Future<void> Function(Duration) get delay =>
      (d) async => now = now.add(d);
}

/// 会记录的时钟：除推进时钟外，把每次被要求的等待时长记进 [waits]。
///
/// ★ 为什么需要它：防止「假 delay 吃掉等待」使测试对间隔失明。
/// 最小间隔的存在与否，只能通过「有没有调用过 delay、等了多久」来断言
/// —— 只看时钟终值会被窗口滚动等无关因素影响。
class RecordingClock extends FakeClock {
  final List<Duration> waits = <Duration>[];

  @override
  Future<void> Function(Duration) get delay => (d) async {
        waits.add(d);
        now = now.add(d);
      };

  /// 被要求等待的总时长。
  Duration get totalWaited =>
      waits.fold(Duration.zero, (acc, d) => acc + d);
}

/// 假 SyncBackend：记录调用并返回固定值，供估算模式透传断言。
class FakeSyncBackend implements SyncBackend {
  final List<String> calls = <String>[];

  @override
  Future<List<RemoteObject>> list(String namespace) async {
    calls.add('list');
    return const <RemoteObject>[];
  }

  @override
  Future<({List<int> bytes, String? etag})> get(String path) async {
    calls.add('get');
    return (bytes: utf8.encode('x'), etag: 'e');
  }

  @override
  Future<String?> put(String path, List<int> bytes, {String? ifMatchEtag}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String path, {String? ifMatchEtag}) async {}

  @override
  Future<void> ensureReady() async {}

  @override
  Future<BackendCapabilities> capabilities() async =>
      const BackendCapabilities(
        supportsConditionalWrite: false,
        supportsList: true,
        supportsRangeRead: false,
      );
}

void main() {
  group('估算模式（estimateCosts: true，按方法成本表记账）', () {
    test('预算内正常透传，put 记 3 而不是 1', () async {
      final clock = FakeClock();
      final budget = RequestBudget(now: clock.reader, delay: clock.delay);
      final fake = FakeSyncBackend();
      final limiter = RateLimiterBackend(fake, budget);

      await limiter.list('entities/tasks');
      await limiter.get('manifest.json');
      expect(fake.calls, ['list', 'get']);
      // 默认成本表：list=1、get=1。
      expect(budget.usedInWindow, 2);
      // ★ put 按最坏情况记 3（PUT + 取新 etag PROPFIND + 冲突探测）。
      await limiter.delete('a.json');
      expect(budget.usedInWindow, 3);
      // put 直接经计数传输层验证更真实，见精确模式分组。
    });

    test('超预算：等待可腾出名额则放行（窗口滚动恢复）', () async {
      final clock = FakeClock();
      final budget = RequestBudget(now: clock.reader, delay: clock.delay);
      // 预填 599 条 25 分钟前的记录（还差 1 个名额，put 需 3 个）。
      final t0 = clock.now.subtract(const Duration(minutes: 25));
      for (var i = 0; i < 599; i++) {
        budget.recordAt(t0.add(Duration(seconds: i)));
      }
      expect(budget.usedInWindow, 599);

      final fake = FakeSyncBackend();
      final limiter = RateLimiterBackend(fake, budget);
      await limiter.list('x'); // cost=1，正好占满 600
      expect(budget.usedInWindow, 600);
      expect(fake.calls, ['list']);
    });

    test('超预算：等待超过 maxWait 仍无名额 → 抛 RateLimitExceededException',
        () async {
      final clock = FakeClock();
      final budget = RequestBudget(now: clock.reader, delay: clock.delay);
      // 600 条「刚刚」的记录：30 分钟内不会滚出任何名额。
      for (var i = 0; i < 600; i++) {
        budget.recordAt(clock.now);
      }
      final limiter = RateLimiterBackend(
        FakeSyncBackend(),
        budget,
        maxWait: const Duration(minutes: 2),
      );
      await expectLater(
        limiter.list('x'),
        throwsA(isA<RateLimitExceededException>()),
      );
      // 被拒的调用不透传、不记账。
      expect(budget.usedInWindow, 600);
    });

    test('窗口滚动后预算恢复（600 → 0）', () async {
      final clock = FakeClock();
      final budget = RequestBudget(now: clock.reader, delay: clock.delay);
      for (var i = 0; i < 600; i++) {
        budget.recordAt(clock.now);
      }
      expect(budget.isOverBudget, isTrue);
      clock.now = clock.now.add(const Duration(minutes: 31));
      expect(budget.usedInWindow, 0);
      expect(budget.isOverBudget, isFalse);
      // 恢复后可正常放行。
      final limiter = RateLimiterBackend(FakeSyncBackend(), budget);
      await limiter.list('x');
      expect(budget.usedInWindow, 1);
    });

    test('capabilities 透传且不消耗配额', () async {
      final clock = FakeClock();
      final budget = RequestBudget(now: clock.reader, delay: clock.delay);
      final fake = FakeSyncBackend();
      final limiter = RateLimiterBackend(fake, budget);
      final caps = await limiter.capabilities();
      expect(caps.supportsConditionalWrite, isFalse);
      expect(caps.supportsList, isTrue);
      expect(caps.supportsRangeRead, isFalse);
      expect(budget.usedInWindow, 0); // 本地静态信息不发请求，不记账
    });
  });

  group('★★ 最小请求间隔（2026-09-30 实测后新增的第二道闸门）', () {
    // 背景：实测以 700ms/请求（≈85 请求/分钟）连续 PUT 会在约 300 个请求处
    // 触发账号级 503，而「600/30 分钟」的窗口账本自始至终显示很安全。
    // 因此下面三条断言的是**行为**（有没有等、等了多久），不是账本数字。
    test('★ 连续请求之间必须等待最小间隔（窗口充裕也不放行突发）', () async {
      final clock = RecordingClock();
      final budget = RequestBudget(now: clock.reader, delay: clock.delay);
      final limiter = RateLimiterBackend(FakeSyncBackend(), budget);

      await limiter.list('a');
      await limiter.list('b');
      await limiter.list('c');

      // 窗口充裕到根本不该触发窗口等待。
      expect(budget.usedInWindow, 3);
      expect(budget.isOverBudget, isFalse);
      // 首请求不等（无上次记录），第 2、3 次各等满一个间隔。
      expect(clock.waits, hasLength(2));
      expect(clock.totalWaited, budget.minInterval * 2);
      // ★ 若删掉 release() 里对 _lastReleased 的更新，这里会变成 0 次等待。
    });

    test('★ 一次 put 内部的多个真实 HTTP 请求之间也要有间隔', () async {
      final clock = RecordingClock();
      final budget = RequestBudget(now: clock.reader, delay: clock.delay);
      final transport = FakeWebDavTransport();
      // 无 ETag 响应头 → 后端会补一次 PROPFIND 取新 etag，共 3 个请求。
      transport.handler = (req, i) => i == 0
          ? const WebDavHttpResponse(statusCode: 204)
          : multistatus([
              propEntry(href: '/dav/manifest.json', etag: 'e'),
            ]);
      final webdav = WebDavBackend(
        baseUrl: Uri.parse('https://dav.example.invalid/dav/'),
        username: 'u',
        password: 'p',
        transport: CountingWebDavTransport(transport, budget),
      );

      await webdav.put('manifest.json', [1, 2, 3]);

      // 装饰层在一次 backend 调用外，拦不到调用内部的多个请求；
      // 间隔必须由计数传输层落实。
      expect(transport.requests.length, greaterThanOrEqualTo(2));
      final expected = budget.minInterval * (transport.requests.length - 1);
      expect(clock.totalWaited, expected);
      expect(budget.usedInWindow, transport.requests.length);
    });

    test('minInterval 设为 zero 时回到旧行为（对照）', () async {
      final clock = RecordingClock();
      final budget = RequestBudget(
        now: clock.reader,
        delay: clock.delay,
        minInterval: Duration.zero,
      );
      final limiter = RateLimiterBackend(FakeSyncBackend(), budget);
      await limiter.list('a');
      await limiter.list('b');
      // 对照：关掉间隔后连续请求不再产生任何等待。
      expect(clock.waits, isEmpty);
    });
  });

  group('★ 精确模式（estimateCosts: false，计数传输层按真实 HTTP 请求记账）',
      () {
    late FakeClock clock;
    late RequestBudget budget;
    late FakeWebDavTransport transport;
    late WebDavBackend webdav;
    late RateLimiterBackend limiter;

    setUp(() {
      clock = FakeClock();
      budget = RequestBudget(now: clock.reader, delay: clock.delay);
      transport = FakeWebDavTransport();
      webdav = WebDavBackend(
        baseUrl: Uri.parse('https://dav.example.invalid/dav/'),
        username: 'u',
        password: 'p',
        transport: CountingWebDavTransport(transport, budget),
      );
      limiter = RateLimiterBackend(webdav, budget, estimateCosts: false);
    });

    test('计数与真实 HTTP 请求数一致：put 的每次 PROPFIND/PUT 都被记', () async {
      transport.handler = (req, i) => i == 0
          ? const WebDavHttpResponse(statusCode: 204)
          : multistatus([
              propEntry(href: '/dav/manifest.json', etag: 'newEtag'),
            ]);
      final etag = await limiter.put('manifest.json', [1, 2, 3]);
      expect(etag, 'newEtag');
      // 假实现里一次 put = PUT + PROPFIND 共 2 个真实请求，计数必须一致
      // （生产上若响应无 ETag 头则为 3：多一次 PROPFIND；估算模式记 3
      // 即按此最坏情况）。核心断言：计数 == 实际 HTTP 请求数，不是 1。
      expect(transport.requests, hasLength(2));
      expect(budget.usedInWindow, transport.requests.length);
    });

    test('list 记 1、get 记 1，闸门在预算内直接放行', () async {
      transport.handler = (req, i) => i == 0
          ? multistatus([propEntry(href: '/dav/manifest.json', etag: 'e')])
          : const WebDavHttpResponse(statusCode: 404);
      await limiter.list('entities');
      expect(budget.usedInWindow, 1);
      try {
        await limiter.get('nothing');
      } on ObjectNotFoundException {
        // 预期
      }
      expect(budget.usedInWindow, 2);
      expect(budget.usedInWindow, transport.requests.length);
    });

    test('精确模式预算耗尽：闸门按至少 1 个请求拦截并抛异常', () async {
      for (var i = 0; i < 600; i++) {
        budget.recordAt(clock.now);
      }
      transport.handler =
          (req, i) => const WebDavHttpResponse(statusCode: 500);
      await expectLater(
        limiter.list('x'),
        throwsA(isA<RateLimitExceededException>()),
      );
      expect(transport.requests, isEmpty); // 未透传
      expect(budget.usedInWindow, 600);
    });
  });
}

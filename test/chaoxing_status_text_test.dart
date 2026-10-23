import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/chaoxing/chaoxing_counts.dart';
import 'package:qingdan/import/chaoxing/chaoxing_client.dart';

/// 头部那一句状态的纯逻辑（v1.0.3 把相对时间换成绝对时间，并加了失败行）。
///
/// 为什么要单独测：渲染那一层在测试字体下宽度约为真实字形的 1.6 倍，411dp 上
/// 这一格放不下任何一条文案，所以「显示什么字」只能在这一层钉死，布局那层只钉
/// 「要么整句、要么不显示」。
void main() {
  final DateTime now = DateTime(2026, 10, 23, 22, 30);

  group('更新时间', () {
    test('同一天：只给时分', () {
      expect(
          fetchedLabel(
              fetchedAt: DateTime(2026, 10, 23, 22, 20),
              now: now,
              loading: false,
              stale: false),
          '22:20 更新');
    });

    test('不是今天：带上月日（用户要能跟截止时间对上）', () {
      expect(
          fetchedLabel(
              fetchedAt: DateTime(2026, 10, 19, 7, 5),
              now: now,
              loading: false,
              stale: false),
          '10-19 07:05 更新');
    });

    test('跨年：带年份，避免把去年的数据看成今年的', () {
      expect(
          fetchedLabel(
              fetchedAt: DateTime(2025, 12, 31, 23, 59),
              now: now,
              loading: false,
              stale: false),
          '2025-12-31 23:59 更新');
    });

    test('过期：后面缀「建议刷新」', () {
      expect(
          fetchedLabel(
              fetchedAt: DateTime(2026, 10, 23, 22, 0),
              now: now,
              loading: false,
              stale: true),
          '22:00 更新 · 建议刷新');
    });

    test('刷新中：一律「更新中…」，不拿作业那份时间冒充整批（D1）', () {
      // 作业先到、考试后到；这时候写时间对考试那一栏是假的。
      expect(
          fetchedLabel(
              fetchedAt: DateTime(2026, 10, 23, 22, 20),
              now: now,
              loading: true,
              stale: false),
          '更新中…');
    });

    test('从没刷新过', () {
      expect(
          fetchedLabel(
              fetchedAt: null, now: now, loading: false, stale: false),
          '未刷新');
    });
  });

  group('失败原因', () {
    test('会话失效要说「重新登录」，不能只说「刷新失败」', () {
      expect(refreshErrorText(ChaoxingAuthException()), '会话已失效，请重新登录');
    });

    test('超时与网络不通分开说', () {
      expect(refreshErrorText(TimeoutException('x')), '连不上学习通（超时）');
      expect(refreshErrorText(const SocketException('x')), '连不上学习通（网络不通）');
    });

    test('没预料到的异常只露类型，不把异常原文（常含 URL）甩到界面', () {
      expect(refreshErrorText(StateError('http://mooc1.example/x?cookie=1')),
          '刷新失败（StateError）');
    });

    test('没有失败时返回 null', () {
      expect(refreshErrorText(null), isNull);
    });
  });
}

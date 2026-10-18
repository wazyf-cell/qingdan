import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/import/chaoxing/chaoxing_time.dart';

import 'chaoxing_harness.dart';

/// M6B §B5：只有「仍在生效期且未完成」（卡片带红/黄/绿底）的项在隐藏时问一次；
/// 已过期 / 已完成 / 无截止 → 直接隐藏。判定与卡片着色共用 `showsUrgencyTint`。
void main() {
  /// 起面板并把这张卡片滑开（返回 harness，调用方自己握着那条 task）。
  Future<ChaoxingHarness> swipeOpen(WidgetTester tester, ChaoxingTask task) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: <ChaoxingTask>[task]);
    h.stubSeams();
    addTearDown(h.restoreSeams);
    await h.pump(tester, width: 411);
    await h.swipeLeft(tester, task);
    return h;
  }

  testWidgets('三小时内截止（红底）→ 隐藏前先弹确认，文案含标题与截止',
      (WidgetTester tester) async {
    final ChaoxingTask t =
        cxHomework('1', title: '第四章', dueAt: kCxNow.add(const Duration(hours: 3)));
    final ChaoxingHarness h = await swipeOpen(tester, t);

    await h.tapIo(tester, h.hideOf(t));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('「第四章1」还没截止'), findsOneWidget);
    // 截止行文本在卡片本体也出现过一次（对话框后面那张卡），必须限定在对话框里找。
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('10-18 15:00 截止（剩3小时0分）')),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '仍然隐藏'), findsOneWidget);

    // 取消 → 卡片还在。
    await h.tapIo(tester, find.widgetWithText(TextButton, '取消'));
    expect(h.cardOf(t), findsOneWidget);
    expect(h.model.settings.hidden, isEmpty);

    // 仍然隐藏 → 卡片消失 + 提示去隐藏列表恢复。
    await h.swipeLeft(tester, t);
    await h.tapIo(tester, h.hideOf(t));
    await h.tapIo(tester, find.widgetWithText(FilledButton, '仍然隐藏'));
    expect(h.cardOf(t), findsNothing);
    expect(find.text('已隐藏 · 可在 ⋮ → 隐藏列表 里恢复'), findsOneWidget);
  });

  testWidgets('已过期 → 不问，直接隐藏', (WidgetTester tester) async {
    final ChaoxingTask t =
        cxHomework('2', dueAt: kCxNow.subtract(const Duration(hours: 1)));
    final ChaoxingHarness h = await swipeOpen(tester, t);

    await h.tapIo(tester, h.hideOf(t));

    expect(find.byType(AlertDialog), findsNothing);
    expect(h.cardOf(t), findsNothing);
  });

  testWidgets('服务端已完成 → 不问，直接隐藏', (WidgetTester tester) async {
    final ChaoxingTask t = cxHomework('3',
        dueAt: kCxNow.add(const Duration(hours: 3)),
        serverDone: true,
        status: '已完成');
    final ChaoxingHarness h = await swipeOpen(tester, t);

    await h.tapIo(tester, h.hideOf(t));

    expect(find.byType(AlertDialog), findsNothing);
    expect(h.cardOf(t), findsNothing);
  });

  testWidgets('无截止时间 → 不问，直接隐藏', (WidgetTester tester) async {
    final ChaoxingTask t = cxHomework('4');
    final ChaoxingHarness h = await swipeOpen(tester, t);

    await h.tapIo(tester, h.hideOf(t));

    expect(find.byType(AlertDialog), findsNothing);
    expect(h.cardOf(t), findsNothing);
  });

  group('showsUrgencyTint 真值表（四档 urgency × 是否待办）', () {
    bool tint(DateTime? due,
            {bool ongoing = true, bool done = false, DateTime? startAt}) =>
        showsUrgencyTint(
            ChaoxingTask(
                id: 'x',
                courseId: 'c',
                courseName: 'k',
                title: 't',
                kind: '作业',
                ongoing: ongoing,
                startAt: startAt,
                dueAt: due,
                serverDone: done),
            kCxNow);

    test('urgent（<24h）/ soon（<72h）/ calm（≥72h）三档都算生效期', () {
      expect(urgencyOf(kCxNow.add(const Duration(hours: 3)), kCxNow),
          ChaoxingUrgency.urgent);
      expect(tint(kCxNow.add(const Duration(hours: 3))), isTrue);
      expect(tint(kCxNow.add(const Duration(hours: 48))), isTrue);
      expect(tint(kCxNow.add(const Duration(hours: 120))), isTrue);
    });

    test('overdue 档不算（状态已是已结束）', () {
      expect(urgencyOf(kCxNow.subtract(const Duration(hours: 1)), kCxNow),
          ChaoxingUrgency.overdue);
      expect(tint(kCxNow.subtract(const Duration(hours: 1))), isFalse);
    });

    test('none 档（无截止）不算', () => expect(tint(null), isFalse));

    test('已完成 / 已结束 / 未开始都不算', () {
      final DateTime due = kCxNow.add(const Duration(hours: 3));
      expect(tint(due, done: true), isFalse);
      expect(tint(due, ongoing: false), isFalse);
      expect(tint(due, startAt: kCxNow.add(const Duration(hours: 1))), isFalse);
    });
  });

  test('判定只看「仍是待办 + 有截止」，与 urgencyOf 的档位互不重复实现', () {
    // 钉住「卡片着色与隐藏确认共用一个函数」这条约定：任何一处再写一套阈值
    // 就会在这里对不上（卡片用的是同一个 showsUrgencyTint）。
    final ChaoxingTask urgent = cxHomework('9', dueAt: kCxNow);
    expect(showsUrgencyTint(urgent, kCxNow), isTrue);
    expect(showsUrgencyTint(cxHomework('8'), kCxNow), isFalse);
  });
}

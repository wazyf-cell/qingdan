import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_harness.dart';

/// 用户报的缺陷：点「隐藏」后底部提示条（带「全部恢复」动作）永远不消失，
/// 代码里明明写了 `duration: Duration(seconds: 4)`。
///
/// 根因不在倒计时定时器：Flutter 3.47.5 起 `SnackBar.persist` 的缺省值是
/// `action != null`（snack_bar.dart:303），`ScaffoldMessengerState.build()` 挂的
/// 那个定时器到点先看 `if (snackBar.persist) return`（scaffold.dart:622）就退出，
/// 于是**凡是带 action 的 SnackBar 都不再自动收起**。修法见 `hideChaoxingTask`。
void main() {
  /// 把提示条从「刚出现」推到「越过 4 秒 duration 并走完退场动画」。
  Future<void> agePastDuration(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  SnackBar theBar() =>
      (find.byType(SnackBar).evaluate().single.widget as SnackBar);

  Future<ChaoxingHarness> paneWith(
      WidgetTester tester, List<ChaoxingTask> tasks) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks);
    h.stubSeams();
    addTearDown(h.restoreSeams);
    await h.pump(tester, width: 411);
    return h;
  }

  testWidgets('无截止（不问直接隐藏）→ 提示条 4 秒后自动消失',
      (WidgetTester tester) async {
    final ChaoxingTask t = cxHomework('1', courseId: '240000001');
    final ChaoxingHarness h = await paneWith(tester, <ChaoxingTask>[t]);
    await h.swipeLeft(tester, t);

    await h.tapIo(tester, h.hideOf(t));

    expect(find.text('已隐藏 · 可在 ⋮ → 隐藏列表 里恢复'), findsOneWidget);
    expect(theBar().persist, isFalse,
        reason: '带 action 时 SnackBar.persist 缺省为 true，会让 duration 失效');

    await agePastDuration(tester);

    expect(find.text('已隐藏 · 可在 ⋮ → 隐藏列表 里恢复'), findsNothing);
  });

  testWidgets('生效期（弹确认后「仍然隐藏」）→ 提示条同样自动消失',
      (WidgetTester tester) async {
    final ChaoxingTask t = cxHomework('2',
        courseId: '240000002', dueAt: kCxNow.add(const Duration(hours: 3)));
    final ChaoxingHarness h = await paneWith(tester, <ChaoxingTask>[t]);
    await h.swipeLeft(tester, t);

    await h.tapIo(tester, h.hideOf(t));
    await h.tapIo(tester, find.widgetWithText(FilledButton, '仍然隐藏'));

    expect(find.text('已隐藏 · 可在 ⋮ → 隐藏列表 里恢复'), findsOneWidget);

    await agePastDuration(tester);

    expect(find.text('已隐藏 · 可在 ⋮ → 隐藏列表 里恢复'), findsNothing);
    // 隐藏本身照样生效（这条用例只测提示条的生命周期，不能把功能改坏）。
    expect(h.model.settings.hidden, contains(t.key));
  });

  testWidgets('点「全部恢复」仍可立即收起提示条', (WidgetTester tester) async {
    final ChaoxingTask t = cxHomework('3', courseId: '240000003');
    final ChaoxingHarness h = await paneWith(tester, <ChaoxingTask>[t]);
    await h.swipeLeft(tester, t);

    await h.tapIo(tester, h.hideOf(t));
    // 这里不能用 `tapIo`：它把点击包在 `runAsync` 里，退场动画的 `.then` 会拖到
    // 测试树已 dispose 之后才跑，撞 scaffold.dart:451 的 `assert(mounted)`。
    await tester.tap(find.text('全部恢复'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('已隐藏 · 可在 ⋮ → 隐藏列表 里恢复'), findsNothing);
    expect(h.model.settings.hidden, isEmpty);
  });
}

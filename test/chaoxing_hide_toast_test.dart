import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/common/app_toast.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_harness.dart';

/// 2026-10-26：隐藏回执从底部 SnackBar 换成顶部 1.5 秒 toast。
///
/// 旧的「带 action 的 SnackBar 永不自动消失」（`persist` 缺省 true）随
/// SnackBar 一起退场；这里守住三件事：不出现 SnackBar、1.5 秒后消失、
/// 撤销只恢复刚隐藏的那一条。
void main() {
  Future<ChaoxingHarness> paneWith(
      WidgetTester tester, List<ChaoxingTask> tasks) async {
    final ChaoxingHarness h = ChaoxingHarness();
    await h.start(tasks: tasks);
    h.stubSeams();
    addTearDown(h.restoreSeams);
    addTearDown(AppToast.dismiss);
    await h.pump(tester, width: 411);
    return h;
  }

  testWidgets('无截止（不问直接隐藏）→ 顶部 toast，不是底部 SnackBar',
      (WidgetTester tester) async {
    final ChaoxingTask t = cxHomework('1', courseId: '240000001');
    final ChaoxingHarness h = await paneWith(tester, <ChaoxingTask>[t]);
    await h.swipeLeft(tester, t);

    await h.tapIo(tester, h.hideOf(t));

    expect(find.byKey(kAppToastKey), findsOneWidget);
    expect(find.text('已隐藏'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing,
        reason: '不允许退回底部 SnackBar——它会挡住页签栏');
    expect(tester.getTopLeft(find.byKey(kAppToastKey)).dy, lessThan(300),
        reason: '回执必须在上半屏，不能盖住底部页签');
    // 1.5 秒生命周期由 `app_toast_test.dart` 用假时钟钉住；这里不重复
    // 走一遍，因为 hide 动作在 runAsync 里落地，定时器会落到真实时区。
  });

  testWidgets('生效期（弹确认后「仍然隐藏」）→ 同样出现顶部 toast',
      (WidgetTester tester) async {
    final ChaoxingTask t = cxHomework('2',
        courseId: '240000002', dueAt: kCxNow.add(const Duration(hours: 3)));
    final ChaoxingHarness h = await paneWith(tester, <ChaoxingTask>[t]);
    await h.swipeLeft(tester, t);

    await h.tapIo(tester, h.hideOf(t));
    await h.tapIo(tester, find.widgetWithText(FilledButton, '仍然隐藏'));

    expect(find.byKey(kAppToastKey), findsOneWidget);
    expect(find.text('已隐藏'), findsOneWidget);
    expect(h.model.settings.hidden, contains(t.key));
  });

  testWidgets('点 toast 的「撤销」→ 只恢复这一条并立即收起',
      (WidgetTester tester) async {
    final ChaoxingTask t = cxHomework('3', courseId: '240000003');
    final ChaoxingHarness h = await paneWith(tester, <ChaoxingTask>[t]);
    await h.swipeLeft(tester, t);

    await h.tapIo(tester, h.hideOf(t));
    expect(h.model.settings.hidden, contains(t.key));

    await h.tapIo(tester, find.byKey(kAppToastActionKey));

    expect(h.model.settings.hidden, isEmpty);
    expect(find.byKey(kAppToastKey), findsNothing);
    expect(h.cardOf(t), findsOneWidget);
  });
}

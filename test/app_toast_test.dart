import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/common/app_toast.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 2026-10-26 定案：已删除 / 已隐藏 / 已复制的回执改成顶部浮层，
/// 1.5 秒自动消失，带可选撤销；不再使用底部 SnackBar。
void main() {
  tearDown(AppToast.dismiss);

  Future<void> pumpHost(
    WidgetTester tester, {
    String message = '已删除「任务」',
    String? actionLabel,
    VoidCallback? onAction,
  }) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        appBar: AppBar(title: const Text('清单')),
        body: Builder(
          builder: (BuildContext ctx) => Center(
            child: TextButton(
              onPressed: () => AppToast.show(
                ctx,
                message: message,
                actionLabel: actionLabel,
                onAction: onAction,
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('浮在顶栏位置、1.5 秒后消失，且没有 SnackBar',
      (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(kAppToastFade);

    expect(find.byKey(kAppToastKey), findsOneWidget);
    expect(find.text('已删除「任务」'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing,
        reason: '旧实现会挡在底部页签栏上方');

    final double top = tester.getTopLeft(find.byKey(kAppToastKey)).dy;
    expect(top, lessThan(kToolbarHeight),
        reason: '只占顶栏那一条，别把下方工具栏/列表也盖住');
    expect(tester.getBottomRight(find.byKey(kAppToastKey)).dy,
        lessThanOrEqualTo(kToolbarHeight),
        reason: '回执必须完全落在 56dp 顶栏内');

    // 进场 150ms + 再走 1200ms = 1.35s，仍在树里（刚开始淡出）。
    await tester.pump(
        kAppToastLifetime - const Duration(milliseconds: 300));
    expect(find.byKey(kAppToastKey), findsOneWidget,
        reason: '1.5 秒前不许提前消失');

    // 再 200ms 越过 1.5 秒，淡出完成并被摘掉。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byKey(kAppToastKey), findsNothing);
  });

  testWidgets('点「撤销」→ 回调只跑一次，回执立即收起',
      (WidgetTester tester) async {
    int taps = 0;
    await pumpHost(tester,
        actionLabel: '撤销', onAction: () => taps++);
    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(kAppToastFade);
    expect(find.byKey(kAppToastActionKey), findsOneWidget);

    await tester.tap(find.byKey(kAppToastActionKey));
    await tester.pump();

    expect(taps, 1);
    expect(find.byKey(kAppToastKey), findsNothing);
  });

  testWidgets('新回执替换旧回执，不会叠两条',
      (WidgetTester tester) async {
    await pumpHost(tester);
    // 直接借 host 的 context 连续 show 两次。
    final BuildContext ctx = tester.element(find.text('show'));
    AppToast.show(ctx, message: '第一条');
    await tester.pump();
    AppToast.show(ctx, message: '第二条');
    await tester.pump();

    expect(find.byKey(kAppToastKey), findsOneWidget);
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
  });
}

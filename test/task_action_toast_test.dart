import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/features/common/app_toast.dart';

import 'tasks_harness.dart';

/// 2026-10-26：清单页的「已删除 / 已复制」从底部 SnackBar 换成顶部 toast。
/// 这两个动作与学习通隐藏共用 `AppToast`；这里用真库确认调用点真的接上了。
void main() {
  TasksHarness.boot();

  late TasksHarness h;
  setUp(() async {
    h = TasksHarness();
    await h.start();
  });
  tearDown(() => h.stop());

  Future<void> openRowMenu(WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await tester.longPress(find.text('买牛奶'));
    await tester.pumpAndSettle();
  }

  testWidgets('删除任务：顶部 toast 带撤销，撤销后任务回来',
      (WidgetTester tester) async {
    await openRowMenu(tester);

    await h.tapIo(tester, find.text('删除'));

    expect(find.byKey(kAppToastKey), findsOneWidget);
    expect(find.textContaining('已删除「买牛奶」'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'SnackBar 会挡在底部页签栏上方');
    expect(tester.getTopLeft(find.byKey(kAppToastKey)).dy, lessThan(300));

    await h.tapIo(tester, find.byKey(kAppToastActionKey));

    expect(find.byKey(kAppToastKey), findsNothing);
    expect(find.text('买牛奶'), findsOneWidget);
  });

  testWidgets('复制为文本：顶部短回执「已复制」', (WidgetTester tester) async {
    await openRowMenu(tester);

    await h.tapIo(tester, find.text('复制为文本'));

    expect(find.byKey(kAppToastKey), findsOneWidget);
    expect(find.text('已复制'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}

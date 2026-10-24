import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';

import 'tasks_harness.dart';

/// v1.0.8 用户报：改到期时间后列表立刻变了，但侧栏「今天」角标与
/// 「今天 N」chip 停在旧值，要切页签或重启才更新。
///
/// 从 `mobile_tasks_page_test.dart` 单独成文件（行数红线），仍在同一套真库夹具上跑。
void main() {
  TasksHarness.boot();

  late TasksHarness h;
  setUp(() async {
    h = TasksHarness();
    await h.start();
  });
  tearDown(() => h.stop());

  testWidgets('改到期时间后「今天」计数立刻变（v1.0.8 用户报）',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    expect(h.textOf(tester, 'chip:today'), '今天 1');

    // 「交开题」没有到期日；把它改成今天，列表与计数都该立刻变成 2。
    final Task target = (await h.io(tester, () => h.taskUseCase.findAllActive()))!
        .firstWhere((Task t) => t.title == '交开题');
    await h.io(tester, () => h.paneModel.setDueDate(target, DateTime.now()));
    await tester.pumpAndSettle();

    expect(h.sidebar.todayCount, 2, reason: '侧栏计数（底部角标读它）必须跟着到期时间变');
    expect(h.textOf(tester, 'chip:today'), '今天 2',
        reason: '列表已显示 2 条，chips 还停在 1 就是用户报的那个不一致');
  });

  testWidgets('刷新计数不能顺手关掉正在编辑的详情面板', (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await h.tapIo(tester, h.key('chip:all'));
    await h.tapIo(tester, find.text('交开题'));
    expect(find.byKey(const ValueKey<String>('detail-due')), findsOneWidget);

    final Task target = (await h.io(tester, () => h.taskUseCase.findAllActive()))!
        .firstWhere((Task t) => t.title == '交开题');
    await h.io(tester, () => h.paneModel.setDueDate(target, DateTime.now()));
    await tester.pumpAndSettle();

    expect(h.paneModel.detailTaskId, target.id,
        reason: '侧栏计数刷新不是「切视图」，不该清空选中与详情');
    expect(find.byKey(const ValueKey<String>('detail-due')), findsOneWidget);
  });
}

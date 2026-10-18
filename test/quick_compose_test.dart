import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';

import 'tasks_harness.dart';

/// 清单页右下角「＋」的快捷添加抽屉（2026-10-18 用户第二轮定案）。
///
/// 与顶部快速添加框的分工：输入框 = 一行文本 + 自然语言日期；抽屉 = 能显式挑
/// 到期 / 开始 / 优先级 / 清单。两条入口共用 `TaskPaneModel.createQuickAdd`，
/// 所以这里必须验到**真落库**（不是只验界面）。
void main() {
  TasksHarness.boot();

  late TasksHarness h;
  setUp(() async {
    h = TasksHarness();
    await h.start();
  });
  tearDown(() => h.stop());

  Future<void> open(WidgetTester tester) =>
      h.tapIo(tester, h.key('add-task'));

  testWidgets('填标题 + 挑优先级和清单 → 落库、抽屉关掉、列表立刻看得见',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await open(tester);

    await tester.enterText(h.key('compose-title'), '交实验报告');
    await tester.pump();
    await h.tapIo(tester, h.key('compose-priority'));
    await h.tapIo(tester, find.text('高'));
    await h.tapIo(tester, h.key('compose-list'));
    await h.tapIo(tester, find.text('毕设'));
    await h.tapIo(tester, h.key('compose-save'));

    final List<Task>? active =
        await h.io(tester, () => h.taskUseCase.findAllActive());
    final Task made =
        active!.firstWhere((Task t) => t.title == '交实验报告');
    expect(made.priority, TaskPriority.high);
    expect(made.listId, h.gradId);
    expect(h.key('compose-title'), findsNothing, reason: '添加完应自动收起抽屉');
    // 建任务不改当前视图（还在「今天」）；切到「所有」应当立刻看得见这一行。
    expect(h.sidebar.selectedId, kSmartToday);
    await h.tapIo(tester, h.key('chip:all'));
    expect(find.text('交实验报告'), findsOneWidget);
  });

  testWidgets('到期日期：日历里选一天写进任务，✕ 能清空',
      (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await open(tester);

    expect(find.textContaining('设置日期', findRichText: true), findsNWidgets(2),
        reason: '开始与到期两行都该是未设置');

    await tester.tap(h.key('compose-due'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    // 日历里点 15 号再确认。Material 内置按钮文案当前是英文（未接
    // flutter_localizations），哪天接了中文，这条会红——那是提醒不是误报。
    await tester.tap(find.descendant(
        of: find.byType(DatePickerDialog), matching: find.text('15')));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/15'), findsOneWidget);
    await h.tapIo(tester, h.key('compose-due-clear'));
    expect(find.textContaining('设置日期', findRichText: true), findsNWidgets(2));
  });

  testWidgets('标题为空时「添加」是死的，填了才可点', (WidgetTester tester) async {
    await h.pumpAtWidth(tester, 411);
    await open(tester);

    expect(tester.widget<FilledButton>(h.key('compose-save')).onPressed, isNull);
    await tester.enterText(h.key('compose-title'), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(h.key('compose-save')).onPressed, isNull,
        reason: '只敲空格也算空标题');

    await tester.enterText(h.key('compose-title'), '买电池');
    await tester.pump();
    expect(tester.widget<FilledButton>(h.key('compose-save')).onPressed,
        isNotNull);
    // 抽屉里不选清单时，落点是收集箱（当前视图是智能清单「今天」）。
    expect(find.text('收集箱'), findsWidgets);
    await h.tapIo(tester, h.key('compose-save'));
    final List<Task>? active =
        await h.io(tester, () => h.taskUseCase.findAllActive());
    expect(active!.any((Task t) => t.title == '买电池' && t.listId == null), isTrue);
  });
}

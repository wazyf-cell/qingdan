import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/application/task_list_use_case.dart';
import 'package:qingdan/domain/task.dart';

import 'tasks_harness.dart';

/// 计数与列表同一口径：开始或截止任一命中；无日期只进所有；已完成不进。
void main() {
  TasksHarness.boot();

  test('今天/7天计数包含开始型任务', () async {
    final TasksHarness h = TasksHarness();
    await h.start();
    addTearDown(h.stop);

    final DateTime now = DateTime(2026, 10, 26, 12);
    await h.taskUseCase
        .create(title: '开始今天', startDate: DateTime(2026, 10, 26, 7));
    await h.taskUseCase
        .create(title: '截止今天', dueDate: DateTime(2026, 10, 26, 18));
    await h.taskUseCase
        .create(title: '开始昨天', startDate: DateTime(2026, 10, 25, 7));
    await h.taskUseCase
        .create(title: '开始8天后', startDate: DateTime(2026, 11, 3, 7));
    await h.taskUseCase.create(title: '无日期');
    final Task done = await h.taskUseCase.create(
        title: '已完成', startDate: DateTime(2026, 10, 26, 7));
    await h.taskUseCase.setCompleted(done, true);

    final SidebarSnapshot snap = await h.listUseCase.loadSidebar(now: now);
    expect(snap.todayCount, 3, reason: '开始今天 + 截止今天 + 开始昨天');
    expect(snap.next7Count, 3);
    expect(snap.allCount, 7,
        reason: '夹具预置 2 条 + 本轮未完成 5 条；已完成不计');
    expect(snap.completedCount, 1);
  });

  test('createQuickAdd 只写 startDate 时 dueDate 仍为空', () async {
    final TasksHarness h = TasksHarness();
    await h.start();
    addTearDown(h.stop);

    await h.paneModel
        .createQuickAdd(title: '开始型', startDate: DateTime(2026, 10, 26, 7));
    final List<Task> tasks = await h.taskUseCase.findAllActive();
    final Task created =
        tasks.firstWhere((Task t) => t.title == '开始型');
    expect(created.startDate, isNotNull);
    expect(created.dueDate, isNull);
    final DateTime start = created.startDate!.toLocal();
    expect(<int>[start.hour, start.minute], <int>[7, 0]);
  });
}

// 任务日期/时刻：详情面板的三行（自 `task_date_time_test.dart` 按被测对象拆出，
// 断言一条未改）——「到期」行没有外部回调也经既有用例路径落库、窄屏全屏详情页
// 开始/结束/到期三行齐全并显示已存时分（411）、桌面详情面板三行齐全且不溢出（1280）。
//
// 纯函数与日期行在 `task_date_time_format_row_test.dart`，抽屉两条在
// `task_date_time_compose_test.dart`；共用夹具在 `task_date_time_harness.dart`。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/tasks/detail_attributes.dart';
import 'package:qingdan/features/tasks/due_format.dart';

import 'task_date_time_harness.dart';
import 'tasks_harness.dart';

void main() {
  TasksHarness.boot();

  late TasksHarness h;
  setUp(() async {
    h = TasksHarness();
    await h.start();
  });
  tearDown(() => h.stop());

  testWidgets('详情「到期」行：没有外部回调也经既有用例路径落库', (tester) async {
    final List<Task>? all =
        await h.io(tester, () => h.taskUseCase.findAllActive());
    final Task target =
        all!.firstWhere((Task t) => t.title == '交开题'); // 这条没有到期日
    expect(target.dueDate, isNull);

    await pumpHost(
      tester,
      h,
      411,
      DetailAttributes(
        task: target,
        lists: h.paneModel.lists,
        onPickList: (_) {},
        onPickPriority: (_) {},
        onPickStartDate: (_) {},
        onPickEndDate: (_) {},
        // 不传 onPickDueDate：走 detail_attributes 内部那条兜底写路径。
        pickDate: pickDateTo(DateTime(2026, 10, 18, 14, 30)),
      ),
    );
    expect(rowValueText(tester, 'detail-due'), '未设置');
    expect(find.byKey(const ValueKey<String>('detail-due-clear')), findsNothing,
        reason: '详情面板写不回 null，所以不给假能点的 ✕');

    await h.tapIo(tester, h.key('detail-due'));
    final Task saved = await taskInDb(tester, h, '交开题');
    expect(saved.dueDate!.toLocal().hour, 14);
    expect(saved.dueDate!.toLocal().minute, 30);
  });

  testWidgets('窄屏全屏详情页：开始 / 结束 / 到期三行齐全（411）',
      (tester) async {
    await h.pumpAtWidth(tester, 411);
    await h.tapIo(tester, find.text('买牛奶'));
    for (final String key in <String>[
      'detail-start',
      'detail-end',
      'detail-due',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: '缺 $key');
    }
    // 买牛奶的到期日是 `DateTime.now()` 建的（带时刻），这一行必须把时分显示出来。
    final Task milk = await taskInDb(tester, h, '买牛奶');
    final DateTime local = milk.dueDate!.toLocal();
    expect(
        rowValueText(tester, 'detail-due'),
        '${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}',
        reason: '详情「到期」行要把已存的时分显示出来');
  });

  testWidgets('桌面详情面板：三行齐全且不溢出（1280）', (tester) async {
    await h.pumpAtWidth(tester, 1280);
    await h.tapIo(tester, find.text('买牛奶'));
    for (final String key in <String>[
      'detail-start',
      'detail-end',
      'detail-due',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: '缺 $key');
    }
  });
}

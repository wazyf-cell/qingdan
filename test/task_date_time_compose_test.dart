// 任务日期/时刻：快捷添加抽屉的两行落库（自 `task_date_time_test.dart` 按被测
// 对象拆出，断言一条未改）——「到期」带时分真的进库、411 移动壳；「开始」带时刻
// 并支持 ✕ 清除、1280 桌面壳。
//
// 纯函数与日期行在 `task_date_time_format_row_test.dart`，详情面板三条在
// `task_date_time_detail_test.dart`；共用夹具在 `task_date_time_harness.dart`
// （选择器仍走行组件的接缝注入假结果，写路径与库都是真的）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/tasks/quick_compose_sheet.dart';

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

  testWidgets('抽屉「到期」：日期 + 14:30 真的落库（411 移动壳）',
      (tester) async {
    await pumpHost(
      tester,
      h,
      411,
      QuickComposeSheet(
        pickDate: pickDateTo(DateTime(2026, 10, 18)),
        pickTime: pickTimeTo(const TimeOfDay(hour: 14, minute: 30)),
      ),
    );
    await tester.enterText(h.key('compose-title'), '交实验报告');
    await tester.pump();

    await h.tapIo(tester, h.key('compose-due'));
    expect(rowValueText(tester, 'compose-due'), '10-18');
    await h.tapIo(tester, h.key('compose-due-time'));
    expect(rowValueText(tester, 'compose-due'), '10-18 14:30');

    await h.tapIo(tester, h.key('compose-save'));

    final Task made = await taskInDb(tester, h, '交实验报告');
    // 库里存 UTC 毫秒，读回来是 UTC → 断言走 toLocal()。
    // 直接看 `made.dueDate!.hour` 在本机（UTC+8）会得到 6，那是时区不是精度丢失。
    expect(made.dueDate, isNotNull);
    expect(made.dueDate!.toLocal().hour, 14);
    expect(made.dueDate!.toLocal().minute, 30);
    expect(made.dueDate!.toLocal(), DateTime(2026, 10, 18, 14, 30));
  });

  testWidgets('抽屉「开始」带时刻并支持清除（1280 桌面壳）', (tester) async {
    await pumpHost(
      tester,
      h,
      1280,
      QuickComposeSheet(
        pickDate: pickDateTo(DateTime(2026, 11, 2)),
        pickTime: pickTimeTo(const TimeOfDay(hour: 8, minute: 5)),
      ),
    );
    await tester.enterText(h.key('compose-title'), '桌面用例');
    await tester.pump();

    await h.tapIo(tester, h.key('compose-start'));
    expect(rowValueText(tester, 'compose-start'), '11-02');
    await h.tapIo(tester, h.key('compose-start-time'));
    expect(rowValueText(tester, 'compose-start'), '11-02 08:05');
    await h.tapIo(tester, h.key('compose-start-clear'));
    expect(rowValueText(tester, 'compose-start'), '未设置');

    await h.tapIo(tester, h.key('compose-save'));
    final Task made = await taskInDb(tester, h, '桌面用例');
    expect(made.startDate, isNull, reason: '✕ 清掉后不该把日期又写回去');
    expect(made.dueDate, isNull);
  });
}

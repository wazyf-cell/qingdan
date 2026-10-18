// 任务日期/时刻测试的共用夹具（自 `task_date_time_test.dart` 拆出；非 `_test`
// 文件，flutter test 不直接执行）。
//
// 拆分后的三份文件：
//  - `task_date_time_format_row_test.dart` —— `formatTaskDate`/`applyTime`/
//    `preserveTime` 纯函数 + 日期行三态与时刻钮/✕ 的 key 行为
//  - `task_date_time_compose_test.dart` —— 快捷添加抽屉的「到期」「开始」两行落库
//  - `task_date_time_detail_test.dart` —— 详情面板的到期写链与三行齐全（411/1280）
//
// 唯一的机械处理：原文件的私有 widget `_RowHost` 只被「日期行」那一条用例用到，
// 就让它留在 `task_date_time_format_row_test.dart` 里保持私有原名，本夹具不动它。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/compose_date_time_row.dart';
import 'package:qingdan/features/tasks/date_time_pick.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'tasks_harness.dart';

/// 注入：点日期行直接得到 [d]。
DateFieldPicker pickDateTo(DateTime d) =>
    (_, _) async => d;

/// 注入：点时刻钮就按生产同款纯函数 [applyTime] 把 [t] 合到当前值上。
DateFieldPicker pickTimeTo(TimeOfDay t) =>
    (BuildContext _, DateTime? current) async {
      final DateTime? v = current;
      return v == null ? null : applyTime(v, t);
    };

/// 把待测界面**推进导航栈**，而不是当根路由：抽屉点「添加」最后会 `Navigator.pop()`，
/// 根路由被 pop 会让 Navigator 变空，之后的断言就没了落点。
Future<void> pumpHost(
    WidgetTester tester, TasksHarness h, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SidebarModel>.value(value: h.sidebar),
        ChangeNotifierProvider<TaskPaneModel>.value(value: h.paneModel),
      ],
      // 裸 MaterialApp 会让 AppColors.of(context) 抛（主题扩展只由 AppTheme 装）。
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => TextButton(
              key: const ValueKey<String>('host-push'),
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                  // 必须给一个 Material 祖先：行组件用的是 InkWell，裸路由会让它
                  // 直接断言失败（生产里抽屉/弹层都自带 Material，所以只有测试会踩）。
                  builder: (_) => Material(child: child))),
              child: const Text('进入被测界面'),
            ),
          ),
        ),
      ),
    ),
  );
  await h.tapIo(tester, find.byKey(const ValueKey<String>('host-push')));
}

/// 取某一行当前显示的值文案。
String rowValueText(WidgetTester tester, String rowKey) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(ValueKey<String>(rowKey)), matching: find.byType(Text)))
    .data ??
    '';

/// 读库里那条标题对应的任务。
Future<Task> taskInDb(WidgetTester tester, TasksHarness h, String title) async {
  final List<Task>? all =
      await h.io(tester, () => h.taskUseCase.findAllActive());
  return all!.firstWhere((Task t) => t.title == title);
}

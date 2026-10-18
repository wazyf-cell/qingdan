import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/chaoxing/chaoxing_due_banner.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/task_list_pane.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/features/tasks/tasks_bar.dart';
import 'package:qingdan/features/tasks/trash_pane.dart';

/// 清单页（M5 定案第 4 条，仅窄屏形态使用）。
///
/// 抽屉下线后，原来一屏侧栏里的东西被拆成三处：页头两行（`tasks_bar.dart`：
/// 三个图标按钮 + 时间视图 chips，M6-A2）、半屏清单面板（`list_sheet.dart`）、
/// 任务列表本体。`TaskListPane` 本体逻辑一行不动，只是不再自绘标题行
/// （`showHeader: false`），避免页标题 + 同步图标在顶栏与页内各来一遍。
class TasksPage extends StatelessWidget {
  const TasksPage({super.key, this.onOpenDetailPage});

  final VoidCallback? onOpenDetailPage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const TasksBar(),
        Consumer<TaskPaneModel>(
          builder: (BuildContext _, TaskPaneModel model, _) =>
              model.viewId == kSmartToday
                  ? const ChaoxingDueBanner()
                  : const SizedBox.shrink(),
        ),
        Expanded(
          child: Consumer<TaskPaneModel>(
            builder: (BuildContext _, TaskPaneModel model, _) =>
                model.viewId == kTrash
                    ? const TrashPane()
                    : TaskListPane(
                        showHeader: false,
                        onOpenDetailPage: onOpenDetailPage),
          ),
        ),
      ],
    );
  }
}

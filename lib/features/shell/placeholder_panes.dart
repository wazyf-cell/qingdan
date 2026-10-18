import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/chaoxing/chaoxing_pane.dart';
import 'package:qingdan/features/course/course_pane.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/detail_pane.dart';
import 'package:qingdan/features/tasks/task_list_pane.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/features/tasks/trash_pane.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 列表区宿主（surface 底）：回收站渲染 [TrashPane]、课表渲染 [CoursePane]，
/// 其余视图渲染 [TaskListPane]。[onReopenDetail] 非空时在右上角显示
/// 「展开详情面板」按钮（详情收起状态下的重新打开入口）。
/// [onOpenDetailPage] 非空时，点击任务行在 `model.openDetail()` 之后再调它——
/// 窄屏形态详情不是内嵌面板，必须显式推全屏页（需求规格书 :172 两级页面）。
class ListPaneHost extends StatelessWidget {
  const ListPaneHost(
      {super.key, this.onReopenDetail, this.onOpenDetailPage});

  final VoidCallback? onReopenDetail;
  final VoidCallback? onOpenDetailPage;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      color: colors.surface,
      child: Stack(
        children: <Widget>[
          Consumer<TaskPaneModel>(
            builder: (BuildContext context, TaskPaneModel model, _) =>
                switch (model.viewId) {
                  kTrash => const TrashPane(),
                  kCourseWeek => const CoursePane(),
                  kChaoxing => const ChaoxingPane(),
                  _ => TaskListPane(onOpenDetailPage: onOpenDetailPage),
                },
          ),
          if (onReopenDetail != null)
            Positioned(
              top: AppDimens.s8,
              right: AppDimens.s8,
              child: IconButton(
                tooltip: '展开详情面板',
                icon: const Icon(Icons.chevron_left),
                color: colors.textSecondary,
                onPressed: onReopenDetail,
              ),
            ),
        ],
      ),
    );
  }
}

/// 详情面板宿主（surface 底，左缘 1dp 分隔线由外层栏位绘制）。
/// [onCollapse] 非空时显示「整栏收起」按钮（§1.7：收起后列表区变宽）。
class DetailPaneHost extends StatelessWidget {
  const DetailPaneHost({super.key, this.onCollapse, this.twoColumns = false});

  final VoidCallback? onCollapse;
  final bool twoColumns;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (onCollapse != null)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '收起详情面板',
                icon: const Icon(Icons.chevron_right),
                color: colors.textSecondary,
                onPressed: onCollapse,
              ),
            ),
          Expanded(
            child: DetailPane(twoColumns: twoColumns),
          ),
        ],
      ),
    );
  }
}

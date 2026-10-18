import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_block_sheet.dart';
import 'course_edit_panel.dart';

/// 课程编辑弹层的**外壳**（桌面 Dialog / 移动底部抽屉双端分发）。
///
/// 从 `course_setup.dart` 拆出来：那边是「学期与作息」设置卡，这里是「一门课」的
/// 弹层装配，两者本来就只有「都用 provider」这一点相同；合在一起写满了 300 行。
/// `course_setup.dart` 里保留 `export` 指令，老调用方（含向导步 4）的 import 不用动。
///
/// [totalWeeks] / [maxSection] 由调用方给——导入向导的校正界面没有
/// `CoursePaneModel`，不该为了弹层去伪造一个。
///
/// [onDelete] 传了才在底部渲染「删除课程」（A6：只有已落库的课才谈得上删）。
/// 顺序是「确认 → 先关编辑器 → 再让调用方落库」：编辑器是模态弹层，删除回执
/// 只能由课表页顶部那行行内回执给（总纲陷阱表第 1 条）。
Future<Course?> showCourseEditor(BuildContext context,
    {Course? course,
    required bool isMobile,
    required int totalWeeks,
    required int maxSection,
    Future<void> Function()? onDelete}) async {
  final bool canDelete = course != null && onDelete != null;

  Widget deleteButton(BuildContext sheetContext) {
    final AppColors colors = AppColors.of(sheetContext);
    final NavigatorState nav = Navigator.of(sheetContext);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey<String>('field-delete'),
        onPressed: () async {
          if (!await confirmCourseDelete(sheetContext, course: course!)) return;
          if (nav.mounted) nav.pop<Course>(); // 没改任何东西地关掉
          await onDelete!.call();
        },
        icon: Icon(Icons.delete_outline, size: 18, color: colors.overdue),
        label: Text('删除课程', style: TextStyle(color: colors.overdue)),
      ),
    );
  }

  if (isMobile) {
    return showModalBottomSheet<Course>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => Padding(
        // 键盘避让：不垫 viewInsets 时「保存」会被 IME 整个盖住（真机 411dp
        // 实测点不到，只能靠收起键盘再点）。与 [showCourseSetup] 同一处理。
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom, top: AppDimens.s8),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          builder: (BuildContext ctx, ScrollController controller) => Column(
            children: <Widget>[
              Expanded(
                child: CourseEditPanel(
                  totalWeeks: totalWeeks,
                  maxSection: maxSection,
                  initial: course,
                  isMobile: true,
                  scrollController: controller,
                  onSave: (Course c) => Navigator.of(ctx).pop(c),
                ),
              ),
              if (canDelete) deleteButton(ctx),
            ],
          ),
        ),
      ),
    );
  }
  return showDialog<Course>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(course == null ? '添加课程' : '编辑课程'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Flexible(loose) 而不是 Expanded：面板自己会滚，剩下的空间要先留给
            // 删除那一行，否则 Column 分完高度就报溢出。
            Flexible(
              child: CourseEditPanel(
                totalWeeks: totalWeeks,
                maxSection: maxSection,
                initial: course,
                onSave: (Course c) => Navigator.of(ctx).pop(c),
              ),
            ),
            if (canDelete) deleteButton(ctx),
          ],
        ),
      ),
    ),
  );
}

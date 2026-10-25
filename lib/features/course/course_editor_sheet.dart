import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/theme/app_colors.dart';

import 'course_block_sheet.dart' show confirmCourseDelete;
import 'course_edit_page.dart';
import 'course_edit_panel.dart';

/// 课程编辑器的外壳分发：手机 = 整页（v1.0.10 起），宽屏 = 居中对话框。
///
/// [totalWeeks] / [maxSection] 由调用方给——导入向导的校正界面没有
/// `CoursePaneModel`，不该为了编辑器去伪造一个。
///
/// [onDelete] 传了才在底部渲染「删除课程」（A6：只有已落库的课才谈得上删）。
/// 删除顺序是「确认 → 先关编辑器 → 再让调用方落库」：删除回执只能由课表页
/// 顶部那行行内回执给（总纲陷阱表第 1 条）。
Future<Course?> showCourseEditor(BuildContext context,
    {Course? course,
    required bool isMobile,
    required int totalWeeks,
    required int maxSection,
    Future<void> Function()? onDelete}) async {
  if (isMobile) {
    return openCourseEditPage(context,
        course: course,
        totalWeeks: totalWeeks,
        maxSection: maxSection,
        onDelete: onDelete);
  }
  final bool canDelete = course != null && onDelete != null;
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
            if (canDelete) _deleteRow(ctx, course, onDelete),
          ],
        ),
      ),
    ),
  );
}

Widget _deleteRow(BuildContext sheetContext, Course course,
    Future<void> Function() onDelete) {
  final AppColors colors = AppColors.of(sheetContext);
  final NavigatorState nav = Navigator.of(sheetContext);
  return Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      key: const ValueKey<String>('field-delete'),
      onPressed: () async {
        if (!await confirmCourseDelete(sheetContext, course: course)) return;
        if (nav.mounted) nav.pop<Course>();
        await onDelete();
      },
      icon: Icon(Icons.delete_outline, size: 18, color: colors.overdue),
      label: Text('删除课程', style: TextStyle(color: colors.overdue)),
    ),
  );
}

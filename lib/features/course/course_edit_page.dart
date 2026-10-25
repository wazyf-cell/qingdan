import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_block_sheet.dart' show confirmCourseDelete;
import 'course_edit_panel.dart';
import 'course_page_scaffold.dart';

/// 添加 / 编辑课程的整页形态（手机端）。宽屏仍走 `showCourseEditor` 的对话框。
///
/// 返回给调用方的契约与弹层完全一致：保存 → 带回 [Course]；返回/删除 → null。
/// 删除先关页再落库，回执由调用方（课表页行内提示）负责。
Future<Course?> openCourseEditPage(
  BuildContext context, {
  Course? course,
  required int totalWeeks,
  required int maxSection,
  Future<void> Function()? onDelete,
}) =>
    Navigator.of(context).push<Course>(MaterialPageRoute<Course>(
      builder: (BuildContext _) => CourseEditPage(
        course: course,
        totalWeeks: totalWeeks,
        maxSection: maxSection,
        onDelete: onDelete,
      ),
    ));

class CourseEditPage extends StatefulWidget {
  const CourseEditPage({
    super.key,
    this.course,
    required this.totalWeeks,
    required this.maxSection,
    this.onDelete,
  });

  final Course? course;
  final int totalWeeks;
  final int maxSection;
  final Future<void> Function()? onDelete;

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends State<CourseEditPage> {
  bool _dirty = false;
  VoidCallback? _submit;

  bool get _canDelete => widget.course != null && widget.onDelete != null;

  Future<void> _tryDiscard() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('返回后这次修改不会保存。'),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('course-discard-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            key: const ValueKey<String>('course-discard-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    _dirty = false;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final Course course = widget.course!;
    if (!await confirmCourseDelete(context, course: course)) return;
    if (!mounted) return;
    final Future<void> Function()? remove = widget.onDelete;
    _dirty = false;
    Navigator.of(context).pop();
    if (remove != null) await remove();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return PopScope<Course?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Course? result) {
        if (!didPop) _tryDiscard();
      },
      child: CoursePageScaffold(
        title: widget.course == null ? '添加课程' : '编辑课程',
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('course-page-save'),
            onPressed: () => _submit?.call(),
            child: const Text('保存'),
          ),
        ],
        child: Column(
          children: <Widget>[
            Expanded(
              child: CourseEditPanel(
                totalWeeks: widget.totalWeeks,
                maxSection: widget.maxSection,
                initial: widget.course,
                isMobile: true,
                showSaveButton: false,
                onDirty: () => setState(() => _dirty = true),
                onSaveHandle: (VoidCallback save) => _submit = save,
                onSave: (Course c) {
                  _dirty = false;
                  Navigator.of(context).pop(c);
                },
              ),
            ),
            if (_canDelete)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppDimens.s16, 0, AppDimens.s16, AppDimens.s8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey<String>('field-delete'),
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: colors.overdue),
                      label: Text('删除课程',
                          style: TextStyle(color: colors.overdue)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

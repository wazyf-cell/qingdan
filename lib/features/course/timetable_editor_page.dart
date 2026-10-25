import 'package:flutter/material.dart';

import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_page_scaffold.dart';
import 'timetable_editor.dart';

/// 作息逐节编辑的整页形态（手机端）。宽屏的模板编辑器仍走原对话框。
///
/// 返回保存后的节次列表；直接返回 = null，调用方什么都不写。
Future<List<TimeDetail>?> openTimetableEditorPage(
  BuildContext context, {
  required String title,
  required List<TimeDetail> initial,
}) =>
    Navigator.of(context).push<List<TimeDetail>>(MaterialPageRoute<List<TimeDetail>>(
      builder: (BuildContext _) =>
          TimetableEditorPage(title: title, initial: initial),
    ));

class TimetableEditorPage extends StatefulWidget {
  const TimetableEditorPage({
    super.key,
    required this.title,
    required this.initial,
  });

  final String title;
  final List<TimeDetail> initial;

  @override
  State<TimetableEditorPage> createState() => _TimetableEditorPageState();
}

class _TimetableEditorPageState extends State<TimetableEditorPage> {
  bool _dirty = false;
  VoidCallback? _submit;

  Future<void> _tryDiscard() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('返回后这次对作息时间的修改不会保存。'),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('timetable-discard-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            key: const ValueKey<String>('timetable-discard-confirm'),
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

  @override
  Widget build(BuildContext context) {
    return PopScope<List<TimeDetail>?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, List<TimeDetail>? result) {
        if (!didPop) _tryDiscard();
      },
      child: CoursePageScaffold(
        title: widget.title,
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('tt-page-save'),
            onPressed: () => _submit?.call(),
            child: const Text('保存'),
          ),
        ],
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimens.panelPadding),
          child: TimetableEditPanel(
            initialDetails: widget.initial,
            isMobile: true,
            showSaveButton: false,
            onDirty: () => setState(() => _dirty = true),
            onSaveHandle: (VoidCallback save) => _submit = save,
            onSave: (List<TimeDetail> draft) {
              _dirty = false;
              Navigator.of(context).pop(draft);
            },
          ),
        ),
      ),
    );
  }
}

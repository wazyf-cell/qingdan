import 'package:flutter/material.dart';

import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_page_scaffold.dart';
import 'timetable_editor.dart';
import 'timetable_library_model.dart';

/// 时间表模板编辑器（手机端整页）。宽屏仍由模板库的对话框承载同一个 body。
///
/// 返回后由模板库自己 `load()`；页面只负责收集名称与节次，落库仍在 model。
Future<void> openTimetableTemplateEditorPage(
  BuildContext context, {
  required TimetableLibraryModel model,
  required TemplateRow? row,
  required List<TimeDetail> initial,
  String seedName = '',
}) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext _) => TimetableTemplateEditorPage(
        model: model,
        row: row,
        initial: initial,
        seedName: seedName,
      ),
    ));

class TimetableTemplateEditorPage extends StatefulWidget {
  const TimetableTemplateEditorPage({
    super.key,
    required this.model,
    required this.row,
    required this.initial,
    this.seedName = '',
  });

  final TimetableLibraryModel model;
  final TemplateRow? row;
  final List<TimeDetail> initial;
  final String seedName;

  @override
  State<TimetableTemplateEditorPage> createState() =>
      _TimetableTemplateEditorPageState();
}

class _TimetableTemplateEditorPageState
    extends State<TimetableTemplateEditorPage> {
  bool _dirty = false;

  Future<void> _tryDiscard() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('返回后这次对模板的修改不会保存。'),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('template-discard-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            key: const ValueKey<String>('template-discard-confirm'),
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
    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, void result) {
        if (!didPop) _tryDiscard();
      },
      child: CoursePageScaffold(
        title: widget.row == null ? '新建时间表' : '编辑时间表',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimens.panelPadding),
          child: TimetableTemplateEditorBody(
            model: widget.model,
            row: widget.row,
            initial: widget.initial,
            seedName: widget.seedName,
            onDirty: () => setState(() => _dirty = true),
            onSaved: () => Navigator.of(context).pop(),
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

/// 名称 + 逐节表格 + 保存回执；整页和宽屏弹窗共用。
class TimetableTemplateEditorBody extends StatefulWidget {
  const TimetableTemplateEditorBody({
    super.key,
    required this.model,
    required this.row,
    required this.initial,
    this.seedName = '',
    this.onDirty,
    this.onSaved,
    this.onClose,
  });

  final TimetableLibraryModel model;
  final TemplateRow? row;
  final List<TimeDetail> initial;
  final String seedName;
  final VoidCallback? onDirty;
  final VoidCallback? onSaved;
  final VoidCallback? onClose;

  @override
  State<TimetableTemplateEditorBody> createState() =>
      _TimetableTemplateEditorBodyState();
}

class _TimetableTemplateEditorBodyState
    extends State<TimetableTemplateEditorBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.seedName);
  String? _said;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(List<TimeDetail> draft) async {
    final bool ok = await widget.model.save(widget.row, _name.text, draft);
    if (!mounted) return;
    if (ok) {
      widget.onSaved?.call();
    } else {
      setState(() => _said = widget.model.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final TimeTable? table = widget.row?.table;
    return Column(
      key: ValueKey<String>(
          table == null ? 'tpl-editor-new' : 'tpl-editor-${table.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('tpl-name'),
          controller: _name,
          enabled: table == null || !table.isBuiltin,
          onChanged: (_) => widget.onDirty?.call(),
          decoration: InputDecoration(
            labelText: '模板名称',
            isDense: true,
            helperText: table?.isBuiltin == true ? '内置模板不可改名' : null,
          ),
        ),
        const SizedBox(height: AppDimens.s8),
        TimetableEditPanel(
          initialDetails: widget.initial,
          isMobile: MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow,
          onDirty: widget.onDirty,
          onSave: _save,
        ),
        if (_said != null)
          Text(_said!,
              key: const ValueKey<String>('tpl-edit-said'),
              style: AppTypography.meta.copyWith(color: colors.overdue)),
        if (table != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: ValueKey<String>('tpl-default-${table.id}'),
              onPressed: () {
                widget.model.setDefault(table.id);
                widget.onClose?.call();
              },
              child: const Text('设为默认模板'),
            ),
          ),
      ],
    );
  }
}

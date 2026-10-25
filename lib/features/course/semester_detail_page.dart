import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_page_scaffold.dart';
import 'course_pane_model.dart';
import 'semester_editor.dart';
import 'timetable_editor_page.dart';

/// 「学期与作息」详情整页（v1.0.10）。从课表设置或课表管理的学期卡片进入。
///
/// 学期列表只在「课表管理」出现一次，这里只处理**一个学期**：改三个字段、
/// 看这套作息、进整页改作息，或从模板库复制一套。
Future<void> openSemesterDetailPage(
  BuildContext context, {
  required Semester semester,
}) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext _) => SemesterDetailPage(semester: semester),
    ));

class SemesterDetailPage extends StatefulWidget {
  const SemesterDetailPage({super.key, required this.semester});

  final Semester semester;

  @override
  State<SemesterDetailPage> createState() => _SemesterDetailPageState();
}

class _SemesterDetailPageState extends State<SemesterDetailPage> {
  late Semester _semester = widget.semester;
  List<TimeDetail> _details = const <TimeDetail>[];
  bool _dirty = false;
  String? _said;
  bool _saidError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadDetails());
  }

  Future<void> _reloadDetails() async {
    final List<TimeDetail> details = await context
        .read<SemesterUseCase>()
        .loadDetailsForSemester(_semester.id);
    if (!mounted) return;
    setState(() => _details = details);
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _said = text;
      _saidError = error;
    });
  }

  Future<void> _saveSemester({
    required String name,
    required DateTime firstWeekDate,
    required int totalWeeks,
  }) async {
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final Semester saved = await semesters.saveSemester(_semester,
        name: name, firstWeekDate: firstWeekDate, totalWeeks: totalWeeks);
    if (!mounted) return;
    setState(() {
      _semester = saved;
      _dirty = false;
    });
    if (saved.isActive) await context.read<CoursePaneModel>().load();
    _say('学期已保存 · ${saved.name} 共 ${saved.totalWeeks} 周');
  }

  Future<void> _editTimetable() async {
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final CoursePaneModel model = context.read<CoursePaneModel>();
    final List<TimeDetail>? draft = await openTimetableEditorPage(
      context,
      title: '编辑作息',
      initial: _details,
    );
    if (draft == null || !mounted) return;
    final String? error =
        await semesters.saveDetailsForSemester(_semester.id, draft);
    if (!mounted) return;
    if (error != null) {
      _say('保存被拒绝：$error', error: true);
      return;
    }
    await _reloadDetails();
    if (_semester.isActive) await model.load();
    _say('作息已保存 · ${draft.length} 节');
  }

  Future<void> _applyTemplate() async {
    final TimetableUseCase? templates = context.read<TimetableUseCase?>();
    final CoursePaneModel model = context.read<CoursePaneModel>();
    if (templates == null) {
      _say('模板库未装配，先返回课表页再试', error: true);
      return;
    }
    final List<TimeTable> all = await templates.templates();
    if (!mounted) return;
    if (all.isEmpty) {
      _say('模板库是空的', error: true);
      return;
    }
    final String? id = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: const Text('从模板生成'),
        children: <Widget>[
          for (final TimeTable t in all)
            SimpleDialogOption(
              key: ValueKey<String>('semester-template-${t.id}'),
              onPressed: () => Navigator.of(ctx).pop(t.id),
              child: Text(t.name),
            ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    try {
      await templates.applyTemplateToSemester(
          semesterId: _semester.id, templateId: id);
    } catch (e) {
      _say('套用模板失败：$e', error: true);
      return;
    }
    await _reloadDetails();
    if (_semester.isActive) await model.load();
    _say('已套用模板');
  }

  Future<void> _tryDiscard() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('返回后这次对学期字段的修改不会保存。'),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('semester-discard-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            key: const ValueKey<String>('semester-discard-confirm'),
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
    final AppColors colors = AppColors.of(context);
    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, void result) {
        if (!didPop) _tryDiscard();
      },
      child: CoursePageScaffold(
        title: _semester.isActive ? '${_semester.name} · 当前' : _semester.name,
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.panelPadding),
          children: <Widget>[
            Text('学期信息',
                style: AppTypography.panelTitle
                    .copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppDimens.s8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.s12),
                child: SemesterEditPanel(
                  initial: _semester,
                  onDirty: () => setState(() => _dirty = true),
                  onSave: _saveSemester,
                ),
              ),
            ),
            if (_said != null)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.s4),
                child: Text(_said!,
                    key: const ValueKey<String>('semester-detail-said'),
                    style: AppTypography.meta.copyWith(
                        color: _saidError ? colors.overdue : colors.textSecondary)),
              ),
            const SizedBox(height: AppDimens.s16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('作息',
                      style: AppTypography.panelTitle
                          .copyWith(color: colors.textPrimary)),
                ),
                TextButton.icon(
                  key: const ValueKey<String>('semester-edit-timetable'),
                  onPressed: _editTimetable,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑作息'),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.s4),
            if (_details.isEmpty)
              Text('还没有作息，点「编辑作息」新建一套',
                  style: AppTypography.meta.copyWith(color: colors.textFaint))
            else
              Card(
                child: Column(
                  children: <Widget>[
                    for (final TimeDetail d in _details)
                      ListTile(
                        dense: true,
                        title: Text('第 ${d.section} 节',
                            style: AppTypography.body),
                        trailing: Text(
                          '${formatMinutes(d.startMinutes)}–'
                          '${formatMinutes(d.endMinutes)}',
                          style: AppTypography.meta,
                        ),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey<String>('semester-apply-template'),
                onPressed: _applyTemplate,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('从模板生成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
import 'timetable_library_model.dart';
import 'timetable_template_editor.dart';

/// 时间表管理（模板库）。手机端=整页；宽屏=居中对话框（v1.0.10 定案）。
Future<void> showTimetableLibrary(BuildContext context, {required bool isMobile}) {
  final TimetableUseCase templates = context.read<TimetableUseCase>();
  final SemesterUseCase semesters = context.read<SemesterUseCase>();
  if (isMobile) {
    return Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext _) => ChangeNotifierProvider<TimetableLibraryModel>(
        create: (_) => TimetableLibraryModel(
            templates: templates, semesters: semesters)..load(),
        child: const CoursePageScaffold(
          title: '时间表管理',
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppDimens.panelPadding),
            child: TimetableLibraryPage(showTitle: false),
          ),
        ),
      ),
    ));
  }
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) => ChangeNotifierProvider<TimetableLibraryModel>(
      create: (_) => TimetableLibraryModel(
          templates: templates, semesters: semesters)..load(),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(AppDimens.s32),
        content: const SizedBox(
          width: 660,
          child: SingleChildScrollView(child: TimetableLibraryPage()),
        ),
      ),
    ),
  );
}

class TimetableLibraryPage extends StatelessWidget {
  const TimetableLibraryPage({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final TimetableLibraryModel m = context.watch<TimetableLibraryModel>();
    final AppColors colors = AppColors.of(context);
    return Column(
      key: const ValueKey<String>('timetable-library'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(children: <Widget>[
          if (showTitle)
            Expanded(child: Text('时间表管理', style: AppTypography.panelTitle))
          else
            const Spacer(),
          TextButton.icon(
            key: const ValueKey<String>('tpl-create'),
            onPressed: () => _create(context, m),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建时间表'),
          ),
        ]),
        if (m.message != null)
          Text(m.message!,
              key: const ValueKey<String>('lib-said'),
              style: AppTypography.meta.copyWith(
                  color: m.messageIsError ? colors.overdue : colors.textSecondary)),
        for (final TemplateRow r in m.rows) _tile(context, m, r, colors),
      ],
    );
  }

  Widget _tile(BuildContext context, TimetableLibraryModel m, TemplateRow r,
          AppColors colors) =>
      ListTile(
        key: ValueKey<String>('tpl-row-${r.table.id}'),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
        title: Row(children: <Widget>[
          Expanded(
              child: Text(r.table.name, overflow: TextOverflow.ellipsis)),
          if (r.table.isBuiltin) _chip('默认', colors.accent, false),
          if (m.defaultTemplateId == r.table.id) _chip('当前默认', colors.accent, true),
        ]),
        subtitle: Text(r.summary, style: AppTypography.meta),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          IconButton(
              key: ValueKey<String>('tpl-use-${r.table.id}'),
              tooltip: '使用',
              icon: const Icon(Icons.check_circle_outline, size: 20),
              onPressed: () => _use(context, m, r)),
          IconButton(
              key: ValueKey<String>('tpl-del-${r.table.id}'),
              tooltip: r.table.isBuiltin ? '内置模板不可删除' : '删除',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed:
                  r.table.isBuiltin ? null : () => _del(context, m, r)),
        ]),
        onTap: () => _edit(context, m, row: r, initial: r.details),
      );

  Widget _chip(String text, Color accent, bool filled) => Container(
      margin: const EdgeInsets.only(left: AppDimens.s4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
          border: Border.all(color: accent),
          color: filled ? accent : null,
          borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, color: filled ? Colors.white : accent)));

  /// ＋ 新建时间表 → 三选一：空白 / 快速生成 / 复制现有。三条都落到逐节编辑器。
  Future<void> _create(BuildContext context, TimetableLibraryModel m) async {
    final int? pick = await showDialog<int>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
            title: const Text('新建时间表'),
            content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              ListTile(
                  key: const ValueKey<String>('tpl-new-blank'),
                  title: const Text('从空白建'),
                  onTap: () => Navigator.pop(c, 0)),
              ListTile(
                  key: const ValueKey<String>('tpl-new-gen'),
                  title: const Text('快速生成…'),
                  onTap: () => Navigator.pop(c, 1)),
              for (int i = 0; i < m.rows.length; i++)
                ListTile(
                    key: ValueKey<String>('tpl-new-copy-${m.rows[i].table.id}'),
                    title: Text('复制现有：${m.rows[i].table.name}'),
                    onTap: () => Navigator.pop(c, 2 + i)),
            ])));
    if (pick == null || !context.mounted) return;
    final List<TimeDetail> initial = switch (pick) {
      0 => const <TimeDetail>[],
      1 => generateTimeDetails(
          timetableId: '',
          firstStartMinutes: 480,
          lessonMinutes: 45,
          breakMinutes: 10,
          sectionCount: 12),
      _ => [for (final TimeDetail d in m.rows[pick - 2].details) d.copyWith()],
    };
    await _edit(context, m,
        initial: initial,
        seedName: pick >= 2 ? '${m.rows[pick - 2].table.name} 副本' : '');
  }

  /// 使用：弹「应用到哪个学期？」（下拉默认当前学期）→ 复制快照 → 面板内回执。
  Future<void> _use(BuildContext context, TimetableLibraryModel m, TemplateRow row) {
    String? sid = m.activeSemesterId;
    return showDialog<void>(context: context,
        builder: (BuildContext c) => StatefulBuilder(
            builder: (BuildContext c, StateSetter setSt) => AlertDialog(
                title: const Text('应用到哪个学期？'),
                content: SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                        key: const ValueKey<String>('tpl-apply-semester'),
                        isExpanded: true,
                        initialValue: sid,
                        items: <DropdownMenuItem<String>>[
                          for (final Semester s in m.semesters)
                            DropdownMenuItem<String>(
                                value: s.id,
                                child: Text('${s.name}${s.isActive ? '（当前）' : ''}'))
                        ],
                        onChanged: (String? v) => setSt(() => sid = v))),
                actions: <Widget>[
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('取消')),
                  FilledButton(
                      key: const ValueKey<String>('tpl-apply-confirm'),
                      onPressed: sid == null
                          ? null
                          : () {
                              Navigator.pop(c);
                              m.use(row.table.id, sid!);
                            },
                      child: const Text('应用')),
                ])));
  }

  Future<void> _del(BuildContext context, TimetableLibraryModel m, TemplateRow r) async {
    final bool? yes = await showDialog<bool>(context: context,
        builder: (BuildContext c) => AlertDialog(
            content: Text('删除模板「${r.table.name}」及其 ${r.details.length} 节？'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消')),
              FilledButton(
                  key: const ValueKey<String>('tpl-del-confirm'),
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('删除')),
            ]));
    if (yes == true) await m.remove(r.table.id);
  }

  Future<void> _edit(BuildContext context, TimetableLibraryModel m,
      {TemplateRow? row, required List<TimeDetail> initial, String seedName = ''}) {
    final bool isMobile =
        MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow;
    if (isMobile) {
      return openTimetableTemplateEditorPage(context,
          model: m, row: row, initial: initial, seedName: seedName);
    }
    return _dialog(
        context,
        TimetableTemplateEditorBody(
          model: m,
          row: row,
          initial: initial,
          seedName: seedName,
          onSaved: () => Navigator.pop(context),
          onClose: () => Navigator.pop(context),
        ));
  }

  Future<void> _dialog(BuildContext context, Widget child) => showDialog<void>(
      context: context,
      builder: (BuildContext _) => AlertDialog(
          insetPadding: const EdgeInsets.all(AppDimens.s32),
          content: SizedBox(width: 660, child: SingleChildScrollView(child: child))));
}

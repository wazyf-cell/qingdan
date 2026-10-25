import 'package:flutter/material.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_pane_model.dart';
import 'semester_create_sheet.dart';
import 'semester_detail_page.dart';
import 'week_picker_sheet.dart' show weekMondayText;

/// 课表管理页的学期卡片列表（v1.0.10）。
///
/// 与旧的 `SemesterListView`（弹层里那套）分开：这里是「点卡片看详情 / 使用是
/// 独立按钮」，不再用一行文字承担切换与查看两种意思。
class SemesterCards extends StatefulWidget {
  const SemesterCards({
    super.key,
    required this.model,
    required this.semesters,
    required this.isMobile,
    this.templates,
  });

  final CoursePaneModel model;
  final SemesterUseCase semesters;
  final bool isMobile;
  final TimetableUseCase? templates;

  @override
  State<SemesterCards> createState() => _SemesterCardsState();
}

class _SemesterCardsState extends State<SemesterCards> {
  List<Semester> _items = const <Semester>[];
  String? _said;
  bool _saidError = false;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant SemesterCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.removeListener(_refresh);
      widget.model.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final List<Semester> all = await widget.semesters.allSemesters();
    if (!mounted) return;
    setState(() => _items = all);
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _said = text;
      _saidError = error;
    });
  }

  Future<void> _use(Semester s) async {
    await widget.model.switchSemester(s.id);
    await _refresh();
    _say('已切换到「${s.name}」');
  }

  Future<void> _open(Semester s) async {
    await openSemesterDetailPage(context, semester: s);
    if (!mounted) return;
    await _refresh();
    await widget.model.load();
  }

  Future<void> _calibrate(Semester s) async {
    final int n = widget.model.week.clamp(1, s.totalWeeks);
    if (!s.isActive) await widget.model.switchSemester(s.id);
    final DateTime? monday = await widget.model.calibrateThisWeekTo(n);
    await _refresh();
    if (monday == null) {
      _say('校准没生效：第 $n 周不在可填范围内', error: true);
      return;
    }
    _say('已把「${s.name}」的第 $n 周设为本周'
        '（开学第一周 ${weekMondayText(monday)}）');
  }

  Future<void> _delete(Semester s) async {
    final int n = await widget.semesters.courseCountForDeletion(s.id);
    if (!mounted) return;
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删除学期「${s.name}」？'),
        content: SizedBox(
          width: 320,
          child: Text('删除学期「${s.name}」会同时删除其中 $n 门课程与作息，'
              '且不进回收站、无法撤销（回收站只管待办任务）。确定？'),
        ),
        actions: <Widget>[
          TextButton(
              key: const ValueKey<String>('semester-del-cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          TextButton(
              key: const ValueKey<String>('semester-del-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.semesters.deleteSemester(s.id);
    } on StateError catch (e) {
      _say(e.message, error: true);
      return;
    }
    await widget.model.load();
    await _refresh();
    _say('已删除「${s.name}」');
  }

  Future<void> _create() async {
    final Semester? created = await showSemesterCreateSheet(context,
        model: widget.model,
        semesters: widget.semesters,
        templates: widget.templates,
        isMobile: widget.isMobile);
    if (!mounted || created == null) return;
    await _refresh();
    _say('已加入「${created.name}」');
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final bool canDelete = _items.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final Semester s in _items) _card(context, s, colors, canDelete),
        if (_said != null)
          Text(_said!,
              key: const ValueKey<String>('semester-said'),
              style: AppTypography.meta.copyWith(
                  color: _saidError ? colors.overdue : colors.textSecondary)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey<String>('semester-create'),
            onPressed: _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建学期'),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, Semester s, AppColors colors, bool canDelete) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppDimens.s8),
      child: InkWell(
        key: ValueKey<String>('semester-card-${s.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(s),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppDimens.s12, AppDimens.s8, AppDimens.s4, AppDimens.s8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(children: <Widget>[
                      Flexible(
                        child: Text(s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(
                                color: s.isActive ? colors.accent : colors.textPrimary)),
                      ),
                      if (s.isActive)
                        Icon(Icons.check,
                            key: ValueKey<String>('semester-check-${s.id}'),
                            size: 16,
                            color: colors.accent),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      '开学 ${_ymd(s.firstWeekMonday)} · 共 ${s.totalWeeks} 周',
                      style: AppTypography.meta,
                    ),
                  ],
                ),
              ),
              if (!s.isActive)
                TextButton(
                  key: ValueKey<String>('semester-use-${s.id}'),
                  onPressed: () => _use(s),
                  child: const Text('使用'),
                ),
              PopupMenuButton<String>(
                key: ValueKey<String>('semester-menu-${s.id}'),
                tooltip: '更多操作',
                onSelected: (String v) {
                  if (v == 'edit') {
                    _open(s);
                  } else if (v == 'week') {
                    _calibrate(s);
                  } else {
                    _delete(s);
                  }
                },
                itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                      value: 'edit', child: Text('查看学期与作息')),
                  PopupMenuItem<String>(
                      value: 'week',
                      child: Text('把第 ${widget.model.week} 周设为本周')),
                  PopupMenuItem<String>(
                    key: ValueKey<String>('semester-del-${s.id}'),
                    value: 'delete',
                    enabled: canDelete,
                    child: Tooltip(
                      message: canDelete ? '删除这个学期' : '至少保留一个学期',
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

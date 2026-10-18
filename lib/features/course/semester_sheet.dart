import 'package:flutter/material.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'semester_create_sheet.dart';
import 'semester_switcher.dart' show showSemesterSheetShell;
import 'semester_editor.dart';
import 'week_picker_sheet.dart' show weekMondayText;

/// 学期面板（M6-D §7.1）。返回**该交给课表页行内回执**的那句话（切换 / 校准），
/// null = 用户直接关：面板一关它自己那行回执就跟着没了，而「切过去了没有」必须
/// 让用户看得见，又不许用 SnackBar（总纲陷阱表第 1 条）。
Future<String?> showSemesterSheet(
  BuildContext context, {
  required CoursePaneModel model,
  required SemesterUseCase semesters,
  TimetableUseCase? templates,
  required bool isMobile,
}) =>
    showSemesterSheetShell<String>(context,
        isMobile: isMobile,
        height: 420,
        body: (BuildContext ctx) => SemesterListView(
            model: model,
            semesters: semesters,
            templates: templates,
            isMobile: isMobile,
            // 切换 / 校准之后把回执交给外壳的 pop 值：面板一关，它自己那行字
            // 就跟着没了，而课表页顶部的行内回执看得见。
            onCloseWithReceipt: (String text) => Navigator.of(ctx).pop(text)));

/// 学期列表本体。**内容独立成 widget**：§7.4 的「课表管理」整页要复用同一个
/// 列表，所以它不能长在弹层里（弹层只管外壳）。
class SemesterListView extends StatefulWidget {
  const SemesterListView({
    super.key,
    required this.model,
    required this.semesters,
    required this.isMobile,
    this.templates,
    this.onCloseWithReceipt,
  });

  final CoursePaneModel model;
  final SemesterUseCase semesters;

  /// 模板库用例：只有「新建学期」选模板时用得到（§7.2）。
  final TimetableUseCase? templates;
  final bool isMobile;

  /// 弹层用：切换 / 校准后把一句话交给外层（外层关面板 + 行内回执）。
  /// 整页形态（§7.4）不传，回执就只显示在本列表里。
  final ValueChanged<String>? onCloseWithReceipt;

  @override
  State<SemesterListView> createState() => _SemesterListViewState();
}

class _SemesterListViewState extends State<SemesterListView> {
  List<Semester> _items = const <Semester>[];
  String? _said;
  bool _saidError = false;

  @override
  void initState() {
    super.initState();
    // 首帧后再读库：构造期间同步 setState 等于在 build 里改状态。
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
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

  /// 点一行 = 切当前学期 + 重载周视图 + 回执；关面板由外层做（§7.1）。
  Future<void> _choose(Semester s) async {
    await widget.model.switchSemester(s.id);
    await _refresh();
    final String text = '已切换到「${s.name}」';
    final ValueChanged<String>? close = widget.onCloseWithReceipt;
    if (close == null) {
      _say(text); // 整页形态（§7.4）不关面板，回执就留在列表里
    } else {
      close(text);
    }
  }

  /// 重命名 / 改开学日期与总周数：整个复用 [SemesterEditPanel]（§7.1）。
  Future<void> _edit(Semester s) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('编辑学期「${s.name}」'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: SemesterEditPanel(
              initial: s,
              // 三个字段一次写完：拆三次写各自拿同一份旧快照整行写回，
              // 后一次盖掉前一次（2026-10-18 用户报的「点了没反应」）。
              onSave: ({
                required String name,
                required DateTime firstWeekDate,
                required int totalWeeks,
              }) async {
                await widget.semesters.saveSemester(s,
                    name: name,
                    firstWeekDate: firstWeekDate,
                    totalWeeks: totalWeeks);
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    await _refresh();
    if (widget.model.semester?.id == s.id) await widget.model.load();
    _say('学期已保存 · ${s.name}');
  }

  /// 把这一周设为本周（A5 的长按校准逻辑）。**得先进入该学期**，否则改的是
  /// 当前学期的开学日期，等于替别的学期背锅。
  Future<void> _setThisWeek(Semester s) async {
    // 目标学期可能比现在看的周次短，先夹到它自己的范围内。
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

  /// 删除：确认框必须写连带数量与「不进回收站、无法撤销」（§6.1 原文）。
  Future<void> _delete(Semester s) async {
    final int n = await widget.semesters.courseCountForDeletion(s.id);
    if (!mounted) return; // 查数量那趟回来时面板可能已经关了
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
      // 用例层是最后一道闸（只剩一个学期时拒删）：UI 拦了也要接得住，
      // 不然点一下就是红屏。
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
    if (!mounted) return;
    if (created == null) return;
    await _refresh();
    _say('已加入「${created.name}」');
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    // 只剩一个学期时拒删：删光了 findActive() 返回 null，整个课表页空白
    // 且无从恢复（§6.1）。
    final bool canDelete = _items.length > 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('学期', style: AppTypography.panelTitle),
        const SizedBox(height: AppDimens.s8),
        // Flexible(loose) 而非 Expanded：整页形态（§7.4）把本列表嵌在无界
        // 高度的滚动区里，Expanded 在无界约束下直接 assert 失败。
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final Semester s in _items) _row(s, colors, canDelete),
              ],
            ),
          ),
        ),
        if (_said != null)
          Text(_said!,
              key: const ValueKey<String>('semester-said'),
              style: AppTypography.meta.copyWith(
                  color: _saidError ? colors.overdue : colors.textSecondary)),
        TextButton.icon(
          key: const ValueKey<String>('semester-create'),
          onPressed: _create,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建学期'),
        ),
      ],
    );
  }

  Widget _row(Semester s, AppColors colors, bool canDelete) => ListTile(
        key: ValueKey<String>('semester-row-${s.id}'),
        dense: true,
        title: Text(s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: s.isActive
                ? AppTypography.body.copyWith(color: colors.accent)
                : AppTypography.body),
        onTap: () => _choose(s),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (s.isActive)
              Icon(Icons.check,
                  key: ValueKey<String>('semester-check-${s.id}'),
                  size: 18,
                  color: colors.accent),
            PopupMenuButton<String>(
              key: ValueKey<String>('semester-menu-${s.id}'),
              tooltip: '更多操作',
              onSelected: (String v) {
                if (v == 'edit') {
                  _edit(s);
                } else if (v == 'week') {
                  _setThisWeek(s);
                } else {
                  _delete(s);
                }
              },
              itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                    value: 'edit', child: Text('重命名 / 改开学日期与总周数')),
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
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';
import 'package:qingdan/features/tasks/task_pane_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'compose_date_time_row.dart';
import 'quick_compose_rows.dart';

/// 快捷添加抽屉（2026-10-18 用户第二轮定案，取代原「＋ = 聚焦顶部输入框」）。
///
/// 与顶部那个快速添加框**不是一回事**：输入框是「一行文本 + 自然语言日期」的快建，
/// 这个抽屉是能显式挑**到期 / 开始 / 优先级 / 清单**的表单。
/// 两条入口最后都走 [TaskPaneModel.createQuickAdd]，写路径仍然只有一条。
Future<void> showQuickCompose(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // 键盘避让：不垫 viewInsets 时「添加」会被 IME 整个盖住（M4a S4b 真机教训）。
    builder: (BuildContext ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: const SafeArea(top: false, child: QuickComposeSheet()),
    ),
  );
}

class QuickComposeSheet extends StatefulWidget {
  const QuickComposeSheet({super.key, this.pickDate, this.pickTime});

  /// 日期/时刻选择器接缝，默认真选择器；widget 测试注入假结果（见
  /// `compose_date_time_row.dart` 的 [DateFieldPicker] 注释）。
  final DateFieldPicker? pickDate;
  final DateFieldPicker? pickTime;

  @override
  State<QuickComposeSheet> createState() => _QuickComposeSheetState();
}

class _QuickComposeSheetState extends State<QuickComposeSheet> {
  final TextEditingController _title = TextEditingController();
  DateTime? _due;
  DateTime? _start;
  TaskPriority _priority = TaskPriority.none;
  String? _listId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 落点默认 = 当前正在看的清单；看的是智能视图时落收集箱（与顶部输入框同规则）。
    final TaskPaneModel model = context.read<TaskPaneModel>();
    _listId = model.isUserList ? model.viewId : null;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String title = _title.text.trim();
    if (title.isEmpty || _busy) return;
    final TaskPaneModel model = context.read<TaskPaneModel>();
    final NavigatorState nav = Navigator.of(context);
    _busy = true;
    await model.createQuickAdd(
        title: title,
        listId: _listId,
        dueDate: _due,
        startDate: _start,
        priority: _priority);
    if (!mounted) return;
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final List<TaskList> lists = context.watch<SidebarModel>().lists;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s16, 0, AppDimens.s16, AppDimens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('添加待办',
              style:
                  AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
          TextField(
            key: const ValueKey<String>('compose-title'),
            controller: _title,
            autofocus: true,
            textInputAction: TextInputAction.done,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
                hintText: '要做什么？', border: InputBorder.none),
            onSubmitted: (String _) => _submit(),
            onChanged: (String _) => setState(() {}),
          ),
          Divider(color: colors.divider),
          ComposeListRow(lists: lists, value: _listId, onChanged: _setList),
          ComposePriorityRow(value: _priority, onChanged: _setPriority),
          ComposeDateTimeRow(
              rowKey: 'compose-start',
              label: '开始',
              helpText: '开始日期',
              value: _start,
              pickDate: widget.pickDate,
              pickTime: widget.pickTime,
              onChanged: (DateTime? v) => setState(() => _start = v)),
          ComposeDateTimeRow(
              rowKey: 'compose-due',
              label: '到期',
              helpText: '到期日期',
              value: _due,
              pickDate: widget.pickDate,
              pickTime: widget.pickTime,
              onChanged: (DateTime? v) => setState(() => _due = v)),
          const SizedBox(height: AppDimens.s12),
          FilledButton(
            key: const ValueKey<String>('compose-save'),
            onPressed: _title.text.trim().isEmpty ? null : _submit,
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _setList(String? id) => setState(() => _listId = id);

  void _setPriority(TaskPriority p) => setState(() => _priority = p);
}

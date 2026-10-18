import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/due_date_parser.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'task_pane_model.dart';

/// 快速添加（F1，§2.2）：36dp 输入框 + 实时解析反馈行。
///
/// - 输入框：surfaceHigh 底、6dp 圆角、无描边；聚焦 1.5dp 主色描边。
/// - 反馈行：28dp，1dp 分隔线 + surface 底 + 8dp 阴影、圆角 6dp，
///   悬浮于列表之上；识别到日期短语显示「🕐 明天(12/24) 10:00 ✕ → 将创建到
///   「工作」」，无日期短语显示「→ 收集箱」；输入为空即消失。
/// - 回车保存：剔除日期短语后的剩余文本为标题（解析器给出匹配区间）。
///   点 ✕ 直接把日期短语从输入框剔除，任务落收集箱（§2.2）。
class QuickAddField extends StatefulWidget {
  const QuickAddField({super.key, required this.model});

  final TaskPaneModel model;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final TextEditingController _controller = TextEditingController();
  ParsedDue? _parsed;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {
      _parsed = parseDuePhrase(_controller.text, DateTime.now());
    });
  }

  /// 点 ✕：把日期短语从输入框剔除（剩余文本保留），任务落收集箱（§2.2）。
  void _clearDate() {
    final ParsedDue p = _parsed!;
    final String text = _controller.text;
    final String rest =
        (text.substring(0, p.start).trimRight() +
                (p.end < text.length ? ' ${text.substring(p.end).trim()}' : ''))
            .trim();
    _controller.value = TextEditingValue(
      text: rest,
      selection: TextSelection.collapsed(offset: rest.length),
    );
    _onChanged();
  }

  Future<void> _save() async {
    final String raw = _controller.text.trim();
    if (raw.isEmpty) return;
    final ParsedDue? parsed = _parsed;
    _controller.clear();

    // 落点清单：M1 不解析 #清单，用当前视图（智能清单/收集箱落 null）。
    String? listId = widget.model.viewId;
    if (widget.model.isSmartView) listId = null;

    // 标题 = 剔除日期短语后的剩余文本。
    String title = raw;
    if (parsed != null && parsed.end > parsed.start) {
      final String stripped =
          (raw.substring(0, parsed.start).trimRight() +
                  (parsed.end < raw.length
                      ? ' ${raw.substring(parsed.end).trim()}'
                      : ''))
              .trim();
      if (stripped.isNotEmpty) title = stripped;
    }
    await widget.model.createQuickAdd(
      title: title,
      listId: listId,
      dueDate: parsed?.due.toUtc(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final bool hasText = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.listPanePaddingH, vertical: AppDimens.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _controller,
            focusNode: widget.model.quickAddFocus,
            style: AppTypography.body,
            textInputAction: TextInputAction.done,
            onSubmitted: (String _) => _save(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.s12, vertical: 9),
              filled: true,
              fillColor: colors.surfaceHigh,
              hintText: '添加任务，回车保存，Shift+回车换行',
              hintStyle:
                  AppTypography.body.copyWith(color: colors.textFaint),
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppDimens.radiusDesktop),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppDimens.radiusDesktop),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppDimens.radiusDesktop),
                borderSide: BorderSide(color: colors.accent, width: 1.5),
              ),
            ),
          ),
          if (hasText) _FeedbackRow(parsed: _parsed, onClearDate: _clearDate),
        ],
      ),
    );
  }
}

/// 解析反馈行（28dp，悬浮提示；§2.2）。
class _FeedbackRow extends StatelessWidget {
  const _FeedbackRow({required this.parsed, required this.onClearDate});

  final ParsedDue? parsed;
  final VoidCallback onClearDate;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final TaskPaneModel model = context.watch<TaskPaneModel>();
    final String target = model.currentViewName;
    return Container(
      margin: const EdgeInsets.only(top: AppDimens.s4),
      height: AppDimens.syncSlotHeight,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
        border: Border.all(color: colors.divider),
        boxShadow: AppDimens.overlayShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.s8),
      child: Row(
        children: <Widget>[
          Icon(Icons.schedule,
              size: 14,
              color: parsed != null ? colors.accent : colors.textFaint),
          const SizedBox(width: AppDimens.s4),
          Expanded(
            child: parsed != null
                ? Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text:
                              '${parsed!.label} ${parsed!.due.hour.toString().padLeft(2, '0')}:${parsed!.due.minute.toString().padLeft(2, '0')}',
                          style: AppTypography.meta
                              .copyWith(color: colors.accent),
                        ),
                        const TextSpan(text: '  '),
                        TextSpan(
                          text: '→ 将创建到「$target」',
                          style: AppTypography.meta
                              .copyWith(color: colors.textFaint),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    '→ $target',
                    style: AppTypography.meta
                        .copyWith(color: colors.textSecondary),
                    maxLines: 1,
                  ),
          ),
          if (parsed != null)
            GestureDetector(
              onTap: onClearDate,
              child: Icon(Icons.close, size: 14, color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

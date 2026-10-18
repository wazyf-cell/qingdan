import 'package:flutter/material.dart';

import 'package:qingdan/domain/tag.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 标签与备注区（自 detail_sections.dart 拆出，§2.3）。

/// 标签区（§2.3）：chip 流式排列 24dp 高 + 「+ 添加」chip。
class DetailTags extends StatelessWidget {
  const DetailTags({
    super.key,
    required this.tags,
    required this.onAdd,
    required this.onRemove,
  });

  final List<Tag> tags;
  final VoidCallback onAdd;
  final ValueChanged<Tag> onRemove;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Wrap(
      spacing: AppDimens.s8,
      runSpacing: AppDimens.s8,
      children: <Widget>[
        for (final Tag tag in tags)
          Container(
            height: 24,
            padding: const EdgeInsets.only(left: AppDimens.s8),
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(tag.name,
                    style: TextStyle(fontSize: 12, color: colors.textPrimary)),
                GestureDetector(
                  onTap: () => onRemove(tag),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.close, size: 12, color: colors.textFaint),
                  ),
                ),
              ],
            ),
          ),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.s8),
            decoration: BoxDecoration(
              border: Border.all(color: colors.divider),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.add, size: 12, color: colors.textSecondary),
                const SizedBox(width: 2),
                Text('添加',
                    style:
                        TextStyle(fontSize: 12, color: colors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 备注区（§2.3）：最小 84dp、上限 400dp 内部滚动；工具行仅 加粗/列表/代码。
class DetailNotes extends StatefulWidget {
  const DetailNotes({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  State<DetailNotes> createState() => _DetailNotesState();
}

class _DetailNotesState extends State<DetailNotes> {
  void _wrapSelection(String prefix, String suffix) {
    final TextSelection sel = widget.controller.selection;
    final String text = widget.controller.text;
    if (!sel.isValid) return;
    final String selected =
        text.substring(sel.start, sel.end);
    final String replaced = '$prefix$selected$suffix';
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, replaced),
      selection: TextSelection.collapsed(
          offset: sel.start + prefix.length + selected.length),
    );
    widget.onChanged();
  }

  void _prefixLines(String prefix) {
    final TextSelection sel = widget.controller.selection;
    final String text = widget.controller.text;
    if (!sel.isValid) return;
    final int start = text.lastIndexOf('\n', sel.start - 1) + 1;
    int end = text.indexOf('\n', sel.end);
    if (end < 0) end = text.length;
    final List<String> lines =
        text.substring(start, end).split('\n');
    final String replaced =
        lines.map((String l) => l.startsWith(prefix) ? l : '$prefix$l').join('\n');
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, end, replaced),
      selection: TextSelection.collapsed(offset: start + replaced.length),
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          _ToolButton(
              icon: Icons.format_bold,
              onTap: () => _wrapSelection('**', '**')),
          const SizedBox(width: AppDimens.s4),
          _ToolButton(
              icon: Icons.format_list_bulleted, onTap: () => _prefixLines('- ')),
          const SizedBox(width: AppDimens.s4),
          _ToolButton(icon: Icons.code, onTap: () => _wrapSelection('`', '`')),
        ]),
        const SizedBox(height: AppDimens.s4),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 84,
            maxHeight: 400,
          ),
          child: TextField(
            controller: widget.controller,
            onChanged: (_) => widget.onChanged(),
            maxLines: null,
            style: const TextStyle(fontSize: 14, height: 1.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: '添加备注…',
              hintStyle: TextStyle(color: colors.textFaint, fontSize: 14),
              contentPadding: const EdgeInsets.all(AppDimens.s8),
              filled: true,
              fillColor: colors.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
                borderSide: BorderSide(color: colors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
                borderSide: BorderSide(color: colors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
                borderSide: BorderSide(color: colors.accent, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.s4),
        child: Icon(icon, size: 16, color: colors.textSecondary),
      ),
    );
  }
}

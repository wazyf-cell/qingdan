import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_dimens.dart';

import 'week_chip_picker.dart';

/// 课程编辑器的「周次」区：chip 选择 + 文本重建。
///
/// 从 `course_edit_panel.dart` 拆出（加入整页/返回拦截后该文件触 300 行红线）。
class CourseWeeksSection extends StatelessWidget {
  const CourseWeeksSection({
    super.key,
    required this.totalWeeks,
    required this.selected,
    required this.isMobile,
    required this.onChanged,
    required this.weeksController,
    required this.weeksTextError,
    required this.onRebuild,
  });

  final int totalWeeks;
  final List<int> selected;
  final bool isMobile;
  final ValueChanged<List<int>> onChanged;
  final TextEditingController weeksController;
  final String? weeksTextError;
  final VoidCallback onRebuild;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('周次', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppDimens.s8),
        WeekChipPicker(
          totalWeeks: totalWeeks,
          selected: selected,
          isMobile: isMobile,
          onChanged: onChanged,
        ),
        if (selected.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppDimens.s4),
            child: Text('至少选一个周次',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: AppDimens.s8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey<String>('field-weeks-text'),
                controller: weeksController,
                decoration: InputDecoration(
                  labelText: '从文本重建（如 1-5、7-11单）',
                  errorText: weeksTextError,
                ),
              ),
            ),
            const SizedBox(width: AppDimens.s8),
            TextButton(
              key: const ValueKey<String>('btn-rebuild'),
              onPressed: onRebuild,
              child: const Text('重建'),
            ),
          ],
        ),
      ],
    );
  }
}

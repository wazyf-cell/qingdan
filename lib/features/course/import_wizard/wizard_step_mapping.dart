// 步 2：列映射确认（§3.2）。自动猜 + 手动改，猜不出且表头无匹配就停在本步。
//
// 三条硬规则照原文实现：每个目标字段**只能被映射一次**（冲突时自动把对方改成
// 「忽略」并提示）；课名/星期等必需字段缺失 → 下一步禁用并说明；置信三档
// ✓ 绿 / ⚠ 黄 / ✗ 红。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/import/course/column_mapping.dart';
import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'import_wizard_model.dart';

class WizardStepMapping extends StatefulWidget {
  const WizardStepMapping({super.key});

  @override
  State<WizardStepMapping> createState() => _WizardStepMappingState();
}

class _WizardStepMappingState extends State<WizardStepMapping> {
  /// 冲突提示只给一次（用户改下一列时清掉，不留常驻噪音）。
  String? _notice;

  @override
  Widget build(BuildContext context) {
    final ImportWizardModel model = context.watch<ImportWizardModel>();
    final AppColors colors = AppColors.of(context);
    final ColumnMapping? mapping = model.mapping;
    final ScheduleTable? table = model.table;
    if (mapping == null || table == null) {
      return const SizedBox.shrink();
    }
    final List<String> missing = <String>[
      for (final CourseField f in mapping.missingRequired()) describeField(f),
    ];
    return Padding(
      padding: const EdgeInsets.all(AppDimens.panelPadding),
      child: ListView(
        children: <Widget>[
          Text('检测到 ${table.rows.first.length} 列、${table.dataRowCount} 行数据。'
              '请确认每列对应的内容：',
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          const SizedBox(height: AppDimens.s12),
          for (final ColumnAssignment c in mapping.columns)
            _MappingRow(
              assignment: c,
              headerCell: _headerOf(table, c.index),
              onChanged: (CourseField f) => setState(() {
                _notice = model.assignColumn(c.index, f);
              }),
            ),
          if (_notice != null) ...<Widget>[
            const SizedBox(height: AppDimens.s8),
            Text(_notice!, style: TextStyle(color: colors.priorityMedium)),
          ],
          if (missing.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppDimens.s12),
            Text('缺少必需列：${missing.join('、')} —— 补齐后才能继续',
                key: const ValueKey<String>('mapping-missing'),
                style: TextStyle(color: colors.overdue, fontSize: 13)),
          ],
          const SizedBox(height: AppDimens.s16),
          Text('数据预览（按当前映射解释前 3 行）',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppDimens.s8),
          _Preview(table: table, mapping: mapping),
        ],
      ),
    );
  }

  static String _headerOf(ScheduleTable table, int index) {
    final List<String> header = table.rows.first;
    if (index >= header.length) return '第 ${index + 1} 列';
    final String text = header[index].trim();
    return text.isEmpty ? '第 ${index + 1} 列' : text;
  }
}

class _MappingRow extends StatelessWidget {
  const _MappingRow(
      {required this.assignment, required this.headerCell, required this.onChanged});

  final ColumnAssignment assignment;
  final String headerCell;
  final ValueChanged<CourseField> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.s4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(headerCell,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ),
          Icon(Icons.arrow_forward, size: 14, color: colors.textFaint),
          const SizedBox(width: AppDimens.s8),
          Expanded(
            child: DropdownButtonFormField<CourseField>(
              key: ValueKey<String>('map-${assignment.index}'),
              initialValue: assignment.field,
              // isExpanded：长字段名（「老师 (可选)」）在窄栏里会撑爆 Dropdown
              // 的内部 Row，它才能让条目走 Expanded + 省略号。
              isExpanded: true,
              menuMaxHeight: 320,
              decoration: const InputDecoration(isDense: true),
              items: <DropdownMenuItem<CourseField>>[
                for (final CourseField f in CourseField.values)
                  DropdownMenuItem<CourseField>(
                      value: f, child: Text(describeField(f))),
              ],
              onChanged: (CourseField? f) {
                if (f != null) onChanged(f);
              },
            ),
          ),
          const SizedBox(width: AppDimens.s8),
          _ConfidenceBadge(confidence: assignment.confidence),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});

  final GuessConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return switch (confidence) {
      GuessConfidence.header => Icon(Icons.check_circle_outline,
          size: 16,
          color: colors.success,
          key: const ValueKey<String>('conf-ok')),
      GuessConfidence.content => Icon(Icons.error_outline,
          size: 16, color: colors.priorityMedium),
      GuessConfidence.none => Icon(Icons.cancel,
          size: 16, color: colors.overdue),
    };
  }
}

/// 前 3 行按当前映射渲染成一行摘要，让用户「看见映射的结果」而不是看见字段名。
class _Preview extends StatelessWidget {
  const _Preview({required this.table, required this.mapping});

  final ScheduleTable table;
  final ColumnMapping mapping;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final List<Widget> lines = <Widget>[];
    for (int i = 1; i < table.rows.length && lines.length < 3; i++) {
      final List<String> cells = table.rows[i];
      final List<String> parts = <String>[
        for (final CourseField f in ColumnMapping.required)
          _cellOf(cells, f),
      ];
      if (parts.every((String p) => p.isEmpty)) continue;
      lines.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(parts.join(' · '),
            style: TextStyle(fontSize: 12, color: colors.textSecondary)),
      ));
    }
    if (lines.isEmpty) {
      return Text('当前映射下没有可显示的数据',
          style: TextStyle(fontSize: 12, color: colors.textFaint));
    }
    return Column(
      key: const ValueKey<String>('mapping-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  String _cellOf(List<String> cells, CourseField field) {
    final int? index = mapping.indexOf(field);
    if (index == null || index >= cells.length) return '';
    return cells[index].trim();
  }
}

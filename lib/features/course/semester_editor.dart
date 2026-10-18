import 'package:flutter/material.dart';

import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 学期编辑面板（§4.2 步骤 3 的「学期卡」，也用于平时的学期设置）。
///
/// 日期选择器上写「选择开学第一周的**任意一天**」——文件里没有任何日期信息，
/// 只能由用户给，应用再归一化到该周的周一（§2.1）。
class SemesterEditPanel extends StatefulWidget {
  const SemesterEditPanel({
    super.key,
    this.initial,
    this.onSave,
  });

  final Semester? initial;

  /// 保存回调：[firstWeekDate] 是用户选的原始日期，归一化由用例层负责。
  final void Function({
    required String name,
    required DateTime firstWeekDate,
    required int totalWeeks,
  })? onSave;

  @override
  State<SemesterEditPanel> createState() => _SemesterEditPanelState();
}

class _SemesterEditPanelState extends State<SemesterEditPanel> {
  late final TextEditingController _name;
  late DateTime _firstWeek;
  late int _totalWeeks;

  @override
  void initState() {
    super.initState();
    final Semester? s = widget.initial;
    _name = TextEditingController(
        text: s?.name ?? _suggestedName(DateTime.now()));
    _firstWeek = s?.firstWeekMonday ?? DateTime.now();
    _totalWeeks = s?.totalWeeks ?? Semester.defaultTotalWeeks;
  }

  /// 默认名「2025-2026-1」式：按开学年份推学年，9 月起算第一学期。
  static String _suggestedName(DateTime date) {
    final int year = date.year;
    final int startYear = date.month >= 9 ? year : year - 1;
    final int term = date.month >= 9 ? 1 : 2;
    return '$startYear-${startYear + 1}-$term';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ok => _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('semester-name'),
          controller: _name,
          decoration: InputDecoration(
            labelText: '学期名称',
            errorText: _ok ? null : '不能为空',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppDimens.s12),
        InkWell(
          key: const ValueKey<String>('semester-date'),
          onTap: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: _firstWeek,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _firstWeek = picked);
          },
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: '开学第一周的任意一天',
              border: OutlineInputBorder(),
            ),
            child: Text(_dateText(_firstWeek)),
          ),
        ),
        const SizedBox(height: AppDimens.s12),
        Row(
          children: <Widget>[
            const Text('总周数'),
            const Spacer(),
            IconButton(
              key: const ValueKey<String>('semester-weeks-minus'),
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: _totalWeeks > Semester.minTotalWeeks
                  ? () => setState(() => _totalWeeks--)
                  : null,
            ),
            SizedBox(
              width: 40,
              child: Text('$_totalWeeks',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
            ),
            IconButton(
              key: const ValueKey<String>('semester-weeks-plus'),
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: _totalWeeks < Semester.maxTotalWeeks
                  ? () => setState(() => _totalWeeks++)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: AppDimens.s16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey<String>('semester-save'),
            onPressed: _ok
                ? () => widget.onSave?.call(
                      name: _name.text.trim(),
                      firstWeekDate: _firstWeek,
                      totalWeeks: _totalWeeks,
                    )
                : null,
            child: Text(widget.initial == null ? '创建学期' : '保存'),
          ),
        ),
      ],
    );
  }

  static String _dateText(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

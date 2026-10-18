import 'package:flutter/material.dart';

import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_steppers.dart';
import 'timetable_generate_form.dart';

/// 作息时间表编辑面板（§2.3）：预设 → 参数 → 生成预览 → 逐节微调 → 保存。
///
/// 三条设计稿要求都落在这里：**用户确认前不落库**；改某节开始时间后该节之后
/// 整体顺移、之前不动；删除中间一节后节次号补位重排。
class TimetableEditPanel extends StatefulWidget {
  const TimetableEditPanel({
    super.key,
    required this.initialDetails,
    this.onSave,
    this.isMobile = false,
  });

  final List<TimeDetail> initialDetails;
  final void Function(List<TimeDetail> draft)? onSave;
  final bool isMobile;

  @override
  State<TimetableEditPanel> createState() => _TimetableEditPanelState();
}

class _TimetableEditPanelState extends State<TimetableEditPanel> {
  late List<TimeDetail> _draft;
  String? _error;
  int _breakMinutes = 10;

  @override
  void initState() {
    super.initState();
    _draft = <TimeDetail>[...widget.initialDetails];
  }

  void _generate(GenerateParams p) {
    _breakMinutes = p.breakMinutes;
    setState(() {
      _error = null;
      _draft = generateTimeDetails(
        timetableId: '',
        firstStartMinutes: p.firstStartMinutes,
        lessonMinutes: p.lessonMinutes,
        breakMinutes: p.breakMinutes,
        sectionCount: p.sectionCount,
        lunchAfterSection: p.lunchAfterSection == 0
            ? null
            : p.lunchAfterSection,
        lunchMinutes: p.lunchMinutes,
      );
    });
  }

  void _addSection() {
    if (_draft.isEmpty) return;
    final TimeDetail last = _draft.last;
    final int length = last.endMinutes - last.startMinutes;
    setState(() => _draft = <TimeDetail>[
          ..._draft,
          TimeDetail(
            id: '',
            timetableId: '',
            section: last.section + 1,
            startMinutes: last.endMinutes + _breakMinutes,
            endMinutes: last.endMinutes + _breakMinutes + length,
          ),
        ]);
  }

  void _deleteSection(TimeDetail target) {
    setState(() {
      // 删中间一节后节次号补位重排（节次本质是序号，不是 ID）。
      _draft = renumber(<TimeDetail>[
        ..._draft.where((TimeDetail d) => d.section != target.section),
      ]);
    });
  }

  /// 改某节开始时间 → 该节之后整体顺移同样分钟数（§2.3 最常见诉求）。
  void _changeStart(TimeDetail target, int? minutes) {
    if (minutes == null) {
      setState(() => _error = '时间格式应为 HH:MM');
      return;
    }
    final int delta = minutes - target.startMinutes;
    if (delta == 0) return;
    setState(() {
      _error = null;
      final int length = target.endMinutes - target.startMinutes;
      _draft = shiftSectionsAfter(
        <TimeDetail>[
          for (final TimeDetail d in _draft)
            d.section == target.section
                ? d.copyWith(
                    startMinutes: minutes, endMinutes: minutes + length)
                : d,
        ],
        target.section,
        delta,
      );
    });
  }

  void _changeEnd(TimeDetail target, int? minutes) {
    if (minutes == null) {
      setState(() => _error = '时间格式应为 HH:MM');
      return;
    }
    if (minutes <= target.startMinutes) {
      setState(() => _error = '结束时间必须晚于开始时间');
      return;
    }
    setState(() {
      _error = null;
      _draft = <TimeDetail>[
        for (final TimeDetail d in _draft)
          d.section == target.section ? d.copyWith(endMinutes: minutes) : d,
      ];
    });
  }

  void _save() {
    final String? invalid = validateTimeDetails(_draft);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() => _error = null);
    widget.onSave?.call(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TimetableGenerateForm(
          onGenerate: _generate,
          initialFirstStart:
              _draft.isNotEmpty ? _draft.first.startMinutes : 480,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.s4),
            child: Text(_error!,
                style: TextStyle(fontSize: 12, color: colors.overdue)),
          ),
        const SizedBox(height: AppDimens.s8),
        Row(
          children: const <Widget>[
            Expanded(child: Text('节')),
            Expanded(child: Text('开始')),
            Expanded(child: Text('结束')),
            SizedBox(width: 48),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.builder(
            key: const ValueKey<String>('tt-rows'),
            shrinkWrap: true,
            itemCount: _draft.length,
            itemBuilder: (BuildContext context, int i) {
              final TimeDetail d = _draft[i];
              return Row(
                key: ValueKey<String>('tt-row-${d.section}'),
                children: <Widget>[
                  Expanded(child: Text('${d.section}')),
                  Expanded(
                    child: CourseTimeCell(
                      section: d.section,
                      tag: 'start',
                      minutes: d.startMinutes,
                      onSubmitted: (int? m) => _changeStart(d, m),
                    ),
                  ),
                  Expanded(
                    child: CourseTimeCell(
                      section: d.section,
                      tag: 'end',
                      minutes: d.endMinutes,
                      onSubmitted: (int? m) => _changeEnd(d, m),
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>('tt-del-${d.section}'),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: _draft.isEmpty ? null : () => _deleteSection(d),
                  ),
                ],
              );
            },
          ),
        ),
        Row(
          children: <Widget>[
            TextButton(
              key: const ValueKey<String>('tt-add'),
              onPressed: _draft.isEmpty ? null : _addSection,
              child: const Text('＋ 添加一节'),
            ),
            const Spacer(),
            FilledButton(
              key: const ValueKey<String>('tt-save'),
              onPressed: _draft.isEmpty ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
      ],
    );
  }
}

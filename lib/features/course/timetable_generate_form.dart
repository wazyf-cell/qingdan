import 'package:flutter/material.dart';

import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// 快速生成参数（§2.3 的表单产物）。
class GenerateParams {
  const GenerateParams({
    required this.firstStartMinutes,
    required this.lessonMinutes,
    required this.breakMinutes,
    required this.sectionCount,
    required this.lunchAfterSection,
    required this.lunchMinutes,
  });

  final int firstStartMinutes;
  final int lessonMinutes;
  final int breakMinutes;
  final int sectionCount;

  /// 0 = 无午休。
  final int lunchAfterSection;
  final int lunchMinutes;
}

/// 作息表「快速生成」表单（§2.3）：预设下拉 + 四个参数 + 可选午休 + 生成预览。
///
/// 只产出参数，不直接改草稿表——预览与保存由 [TimetableEditPanel] 管理，
/// 保证「用户确认前不落库」。
class TimetableGenerateForm extends StatefulWidget {
  const TimetableGenerateForm({
    super.key,
    required this.onGenerate,
    this.initialFirstStart = 480,
  });

  final void Function(GenerateParams params) onGenerate;
  final int initialFirstStart;

  @override
  State<TimetableGenerateForm> createState() => _TimetableGenerateFormState();
}

class _TimetableGenerateFormState extends State<TimetableGenerateForm> {
  /// 单个字段的固定宽：够放下「第一节开始」这类五字浮动标签 + 输入框。
  /// 半栏卡片里四个字段各分不到 90dp，用 Expanded 会让 InputDecorator 横向
  /// 溢出（实测 25px），所以改成 Wrap + 定宽。
  static const double _fieldWidth = 122;

  /// 预设名 → (每节时长, 课间, 每天节数)。
  static const Map<String, (int, int, int)> presets =
      <String, (int, int, int)>{
    '大学默认（45 分钟 / 课间 10）': (45, 10, 12),
    '大学紧凑（40 分钟 / 课间 5）': (40, 5, 12),
    '中学（45 分钟 / 课间 10 / 8 节）': (45, 10, 8),
  };

  late final TextEditingController _firstStart =
      TextEditingController(text: formatMinutes(widget.initialFirstStart));
  final TextEditingController _lesson = TextEditingController(text: '45');
  final TextEditingController _break = TextEditingController(text: '10');
  final TextEditingController _count = TextEditingController(text: '12');
  final TextEditingController _lunchMinutes =
      TextEditingController(text: '90');

  String _preset = '大学默认（45 分钟 / 课间 10）';
  int _lunchAfterSection = 0;
  String? _error;

  @override
  void dispose() {
    _firstStart.dispose();
    _lesson.dispose();
    _break.dispose();
    _count.dispose();
    _lunchMinutes.dispose();
    super.dispose();
  }

  int _intOf(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  void _applyPreset(String? name) {
    if (name == null) return;
    final (int lesson, int gap, int count) = presets[name]!;
    setState(() {
      _preset = name;
      _lesson.text = '$lesson';
      _break.text = '$gap';
      _count.text = '$count';
    });
  }

  void _submit() {
    final int? first = parseMinutes(_firstStart.text);
    if (first == null) {
      setState(() => _error = '第一节开始时间格式应为 HH:MM');
      return;
    }
    setState(() => _error = null);
    widget.onGenerate(GenerateParams(
      firstStartMinutes: first,
      lessonMinutes: _intOf(_lesson, 45),
      breakMinutes: _intOf(_break, 10),
      sectionCount: _intOf(_count, 12),
      lunchAfterSection: _lunchAfterSection,
      lunchMinutes: _intOf(_lunchMinutes, 90),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: const ValueKey<String>('tt-preset'),
          // isExpanded：DropdownButton 在 dense 模式下不给条目套 Expanded，
          // 「大学默认（45 分钟 / 课间 10）」这种长值会把内部 Row 撑爆（实测 25px）。
          isExpanded: true,
          initialValue: _preset,
          decoration: const InputDecoration(labelText: '快速生成'),
          items: <DropdownMenuItem<String>>[
            for (final String name in presets.keys)
              DropdownMenuItem<String>(value: name, child: Text(name)),
          ],
          onChanged: _applyPreset,
        ),
        const SizedBox(height: AppDimens.s8),
        // Wrap + 定宽：卡片被压到半栏宽时四个字段各分不到 90dp，
        // 用 Expanded 会让 InputDecorator 里的 label+输入框横向溢出（实测 25px）。
        Wrap(
          spacing: AppDimens.s8,
          runSpacing: AppDimens.s8,
          children: <Widget>[
            SizedBox(
                width: _fieldWidth,
                child: _field('第一节开始', _firstStart, 'tt-first-start',
                    number: false)),
            SizedBox(
                width: _fieldWidth, child: _field('每节时长', _lesson, 'tt-lesson')),
            SizedBox(
                width: _fieldWidth, child: _field('课间', _break, 'tt-break')),
            SizedBox(
                width: _fieldWidth, child: _field('每天节数', _count, 'tt-count')),
          ],
        ),
        const SizedBox(height: AppDimens.s8),
        Wrap(
          spacing: AppDimens.s8,
          runSpacing: AppDimens.s8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: <Widget>[
            SizedBox(
              width: _fieldWidth,
              child: DropdownButtonFormField<int>(
                key: const ValueKey<String>('tt-lunch-after'),
                isExpanded: true,
                initialValue: _lunchAfterSection,
                decoration: const InputDecoration(
                    labelText: '午休', isDense: true),
                items: <DropdownMenuItem<int>>[
                  const DropdownMenuItem<int>(value: 0, child: Text('无')),
                  for (int s = 1; s <= 12; s++)
                    DropdownMenuItem<int>(value: s, child: Text('第 $s 节后')),
                ],
                onChanged: (int? v) =>
                    setState(() => _lunchAfterSection = v ?? 0),
              ),
            ),
            SizedBox(
                width: _fieldWidth,
                child: _field('午休分钟', _lunchMinutes, 'tt-lunch-minutes')),
            TextButton(
              key: const ValueKey<String>('tt-generate'),
              onPressed: _submit,
              child: const Text('生成预览'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppDimens.s4),
            child: Text(_error!,
                style: TextStyle(fontSize: 12, color: colors.overdue)),
          ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, String key,
          {bool number = true}) =>
      Padding(
        padding: const EdgeInsets.only(right: AppDimens.s4),
        child: TextField(
          key: ValueKey<String>(key),
          controller: c,
          keyboardType: number ? TextInputType.number : null,
          decoration:
              InputDecoration(labelText: label, isDense: true),
        ),
      );
}

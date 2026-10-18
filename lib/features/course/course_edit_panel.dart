import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_color_picker.dart';
import 'course_steppers.dart';
import 'week_chip_picker.dart';

/// 课程编辑面板（§4.3 规则 2：课名文本框 / 星期下拉 / 节次双 stepper /
/// 老师地点 / 周次 chip 选择器 + 从文本重建）。
///
/// 面板只产出一个 [Course]（经 [onSave] 交回调用方落库），自己不碰 DAO；
/// UID 也在这里算好，保证「所见即所存」。
class CourseEditPanel extends StatefulWidget {
  const CourseEditPanel({
    super.key,
    required this.totalWeeks,
    required this.maxSection,
    this.initial,
    this.isMobile = false,
    this.scrollController,
    this.onSave,
  });

  final int totalWeeks;

  /// 作息表里的最大节数（没有作息表时给个保守值）。
  final int maxSection;
  final Course? initial;
  final bool isMobile;

  /// 移动端底部抽屉把它的滚动控制器交进来（拖拽把手才能带动内容）。
  final ScrollController? scrollController;
  final void Function(Course course)? onSave;

  @override
  State<CourseEditPanel> createState() => _CourseEditPanelState();
}

class _CourseEditPanelState extends State<CourseEditPanel> {
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late final TextEditingController _weeksText;

  late int _weekday;
  late int _start;
  late int _end;
  late List<int> _weeks;

  /// 手动选过的配色；null = 自动（跟随课名）。M6-D §十。
  int? _colorIndex;
  String? _weeksTextError;

  @override
  void initState() {
    super.initState();
    final Course? c = widget.initial;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _weeksText = TextEditingController();
    _weekday = c?.weekday ?? 1;
    _start = c?.startSection ?? 1;
    _end = c?.endSection ?? (_start + 1 <= widget.maxSection ? _start + 1 : _start);
    _weeks = <int>[...?c?.weeks];
    _colorIndex = c?.colorIndex;
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    _weeksText.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;
  bool get _weeksOk => _weeks.isNotEmpty;
  bool get _rangeOk => _start >= 1 && _end >= _start;
  bool get _canSave => _nameOk && _weeksOk && _rangeOk;

  void _save() {
    if (!_canSave) return;
    final String name = _name.text.trim();
    final Course source = widget.initial ??
        Course(
          id: '',
          uid: '',
          name: name,
          weekday: _weekday,
          startSection: _start,
          endSection: _end,
          weeks: _weeks,
        );
    final Course next = source.copyWith(
      colorIndex: _colorIndex,
      clearColor: _colorIndex == null,
      name: name,
      teacher: Course.blankToNull(_teacher.text),
      location: Course.blankToNull(_location.text),
      weekday: _weekday,
      startSection: _start,
      endSection: _end,
      weeks: _weeks,
    );
    widget.onSave?.call(next.copyWith(
      uid: courseUidOf(
        name: next.name,
        weekday: next.weekday,
        startSection: next.startSection,
        endSection: next.endSection,
        weeks: next.weeks,
      ),
    ));
  }

  void _rebuildFromText() {
    final ({List<int>? weeks, String? error}) r =
        rebuildWeeksFromText(_weeksText.text, widget.totalWeeks);
    setState(() {
      _weeksTextError = r.error;
      if (r.weeks != null) _weeks = r.weeks!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    // 星期 + 双 stepper 三个控件：桌面一行三列，移动两行（下拉独占一行）。
    // 移动端必须换行——真机 411dp 实测三个挤一行时两个 stepper 各溢出 8.3dp
    // （stepper 固有宽 ≈126dp，三等分只有 118dp），首版就是这样在手机上炸的。
    final Widget weekday = DropdownButtonFormField<int>(
      key: const ValueKey<String>('field-weekday'),
      isExpanded: true,
      initialValue: _weekday,
      decoration: const InputDecoration(labelText: '星期'),
      items: <DropdownMenuItem<int>>[
        for (int w = 1; w <= 7; w++)
          DropdownMenuItem<int>(value: w, child: Text(_names[w - 1])),
      ],
      onChanged: (int? v) => setState(() => _weekday = v ?? 1),
    );
    final Widget startStepper = CourseSectionStepper(
      key: const ValueKey<String>('field-start'),
      label: '起始节',
      value: _start,
      max: widget.maxSection,
      onChanged: (int v) => setState(() {
        _start = v;
        if (_end < _start) _end = v;
      }),
    );
    final Widget endStepper = CourseSectionStepper(
      key: const ValueKey<String>('field-end'),
      label: '结束节',
      value: _end,
      max: widget.maxSection,
      onChanged: (int v) => setState(() {
        _end = v;
        if (_end < _start) _start = v;
      }),
    );
    final Widget sectionRow = widget.isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              weekday,
              const SizedBox(height: AppDimens.s12),
              Row(
                children: <Widget>[
                  Expanded(child: startStepper),
                  const SizedBox(width: AppDimens.s12),
                  Expanded(child: endStepper),
                ],
              ),
            ],
          )
        : Row(
            children: <Widget>[
              Expanded(child: weekday),
              const SizedBox(width: AppDimens.s12),
              Expanded(child: startStepper),
              const SizedBox(width: AppDimens.s12),
              Expanded(child: endStepper),
            ],
          );
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(AppDimens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('field-name'),
            controller: _name,
            decoration: InputDecoration(
              labelText: '课程名称',
              errorText: _nameDirty && !_nameOk ? '不能为空' : null,
            ),
            onChanged: (_) => setState(() => _nameDirty = true),
          ),
          const SizedBox(height: AppDimens.s12),
          sectionRow,
          if (!_rangeOk)
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.s4),
              child: Text('结束节不能早于起始节（不自动交换）',
                  style: TextStyle(fontSize: 12, color: colors.overdue)),
            ),
          const SizedBox(height: AppDimens.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('field-teacher'),
                  controller: _teacher,
                  decoration: const InputDecoration(labelText: '老师（可空）'),
                ),
              ),
              const SizedBox(width: AppDimens.s12),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('field-location'),
                  controller: _location,
                  decoration: const InputDecoration(labelText: '地点（可空）'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.s16),
          CourseColorPicker(
            value: _colorIndex,
            courseName: _name.text.trim(),
            onChanged: (int? v) => setState(() => _colorIndex = v),
          ),
          const SizedBox(height: AppDimens.s16),
          Text('周次', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppDimens.s8),
          WeekChipPicker(
            totalWeeks: widget.totalWeeks,
            selected: _weeks,
            isMobile: widget.isMobile,
            onChanged: (List<int> v) => setState(() => _weeks = v),
          ),
          if (!_weeksOk)
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.s4),
              child: Text('至少选一个周次',
                  style: TextStyle(fontSize: 12, color: colors.overdue)),
            ),
          const SizedBox(height: AppDimens.s8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('field-weeks-text'),
                  controller: _weeksText,
                  decoration: InputDecoration(
                    labelText: '从文本重建（如 1-5、7-11单）',
                    errorText: _weeksTextError,
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.s8),
              TextButton(
                key: const ValueKey<String>('btn-rebuild'),
                onPressed: _rebuildFromText,
                child: const Text('重建'),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.s16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey<String>('btn-save'),
              onPressed: _canSave ? _save : null,
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }

  bool _nameDirty = false;

  static const List<String> _names = <String>[
    '周一', '周二', '周三', '周四', '周五', '周六', '周日',
  ];
}

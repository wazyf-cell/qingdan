import 'package:flutter/material.dart';

import 'package:qingdan/domain/section_layout.dart';

/// 节次 stepper（起始节 / 结束节各一个）。
///
/// 独立成文件是因为 `course_edit_panel.dart` 装不下（300 行硬红线）。
class CourseSectionStepper extends StatelessWidget {
  const CourseSectionStepper({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;

  /// 作息表里的最大节数；到顶后「+」禁用。
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          tooltip: '$label 减一',
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$value', style: const TextStyle(fontSize: 16)),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
        IconButton(
          tooltip: '$label 加一',
          icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// 可编辑的时间格：显示 `HH:MM`，提交时换算成当日分钟数。
///
/// 换算复用领域层的 [formatMinutes] / [parseMinutes]——同一套时间表示只允许
/// 一处实现（§1.2），这里不另写一份正则。控制器由本组件持有（每次 build 新建
/// 会丢焦点与已输入内容），外部改了时间时通过 `didUpdateWidget` 同步回来。
class CourseTimeCell extends StatefulWidget {
  const CourseTimeCell({
    super.key,
    required this.section,
    required this.tag,
    required this.minutes,
    required this.onSubmitted,
  });

  final int section;

  /// 同一节有「开始」「结束」两个格子，用它区分 key（否则同节两格 key 相撞）。
  final String tag;
  final int minutes;
  final void Function(int? minutes) onSubmitted;

  @override
  State<CourseTimeCell> createState() => _CourseTimeCellState();
}

class _CourseTimeCellState extends State<CourseTimeCell> {
  late final TextEditingController _controller =
      TextEditingController(text: formatMinutes(widget.minutes));

  @override
  void didUpdateWidget(covariant CourseTimeCell old) {
    super.didUpdateWidget(old);
    if (widget.minutes != old.minutes || widget.section != old.section) {
      _controller.text = formatMinutes(widget.minutes);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: ValueKey<String>('time-${widget.section}-${widget.tag}'),
      controller: _controller,
      onSubmitted: (String v) => widget.onSubmitted(parseMinutes(v)),
      decoration: const InputDecoration(isDense: true),
    );
  }
}

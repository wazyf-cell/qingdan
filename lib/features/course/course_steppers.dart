import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/theme/app_colors.dart';

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

/// 可编辑的时间格：显示 `HH:MM`，**输入即校验、合法即上报**（不等键盘确认键）。
///
/// 为什么不能只在 `onSubmitted` 里校验（M6-A1 数据损坏级缺陷）：用户打完
/// `26:00` 后直接点「保存」时 `onSubmitted` 根本不触发，草稿没变 → 库里存的
/// 还是旧时间、输入框显示的却是 `26:00`，表现就是「点了没反应」。
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
    this.showError = false,
    this.onInvalid,
    this.revision = 0,
  });

  final int section;

  /// 同一节有「开始」「结束」两个格子，用它区分 key（否则同节两格 key 相撞）。
  final String tag;
  final int minutes;

  /// 解析成功的当日分钟数（`parseMinutes` 已经把小时卡在 0–23、分钟卡在 0–59）。
  final ValueChanged<int> onSubmitted;

  /// 这一格**该不该**染红。判据由父级决定而不是这里自己算：「当前文本解析不过」
  /// 与「这一格该红」是两件事——敲到一半（`0`、`09`、`09:`）必然解析不过，此时
  /// 染红会让 helperText 与错误行反复出现/消失，手机上打字列表就跟着抖（M6-A1）。
  final bool showError;

  /// 每次 `onChanged` 都如实上报「这段文本解析不过」的原文，**包括空串**。
  /// 父级据此记账（空串 = 这一格还没填，要销账），点保存时按账本拦住非法输入。
  /// 状态放在父级（而不是本组件自己存）：顺移/重排把文本覆盖回草稿真值时，
  /// 红态能自然一致、不留幽灵标记。
  final void Function(String raw)? onInvalid;

  /// 父级**拒绝**了一次改动（草稿没动、输入框却已写了新值）时递增它，
  /// 逼这一格把文本回读成草稿真值——绝不静默丢弃用户输入。
  final int revision;

  @override
  State<CourseTimeCell> createState() => _CourseTimeCellState();
}

class _CourseTimeCellState extends State<CourseTimeCell> {
  /// 只让数字与冒号通过（「冒号固定」这条需求）；长度由 maxLength 5 卡死，
  /// 是否合法仍交给 [parseMinutes] 判——同一套时间表示只允许一处实现（§1.2）。
  static final List<TextInputFormatter> _formatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
  ];

  late final TextEditingController _controller =
      TextEditingController(text: formatMinutes(widget.minutes));

  @override
  void didUpdateWidget(covariant CourseTimeCell old) {
    super.didUpdateWidget(old);
    // 外部（顺移、重排、父级拒绝改动）改了值：把文本同步回来。
    // 只比字符串，避免把用户正在输入的同一个值再写一遍、把光标顶到末尾。
    if (widget.minutes != old.minutes ||
        widget.section != old.section ||
        widget.revision != old.revision) {
      final String text = formatMinutes(widget.minutes);
      if (_controller.text != text) _controller.text = text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 同一条路走两个入口：`onChanged`（每按键）与 `onSubmitted`（键盘确认键）。
  /// 认不出来就原样上报（含空串），**这里不判断该不该红**——红由父级的 [showError] 说。
  void _apply(String raw) {
    final int? parsed = parseMinutes(raw);
    if (parsed == null) {
      widget.onInvalid?.call(raw);
      return;
    }
    widget.onSubmitted(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color bad = colors.overdue;
    final Color line = widget.showError ? bad : colors.divider;
    final Color focus = widget.showError ? bad : colors.accent;
    return TextField(
      key: ValueKey<String>('time-${widget.section}-${widget.tag}'),
      controller: _controller,
      keyboardType: TextInputType.datetime,
      inputFormatters: _formatters,
      maxLength: 5,
      onChanged: _apply,
      onSubmitted: _apply,
      style: TextStyle(color: widget.showError ? bad : null),
      decoration: InputDecoration(
        isDense: true,
        // 计数器会把行撑高，所以关掉；上限提示改由 helperText 承担。
        counterText: '',
        // 用 helperText 不用 errorText：errorText 同样撑高，且边框会染成
        // colorScheme.error（深色板下与 overdue 不是同一个色）。
        helperText: widget.showError ? '应为 HH:MM' : null,
        helperStyle: TextStyle(fontSize: 10, color: bad),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: focus)),
      ),
    );
  }
}

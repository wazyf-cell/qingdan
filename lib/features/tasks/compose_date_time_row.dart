// 统一的「标签 | 值 | 时间按钮 | ✕」日期行（M6-A §A3）。
//
// 快捷抽屉（compose-start / compose-due）与详情面板（detail-start / detail-end /
// detail-due）共用这一份实现，避免出现第二套日期交互。
// 时间按钮只在**已有日期**时出现：先挑日子、再决定要不要给时刻，取消时刻选择器
// 就等于「不填」——不需要额外的复选框。

import 'package:flutter/material.dart';

import 'package:qingdan/features/tasks/date_time_pick.dart';
import 'package:qingdan/features/tasks/due_format.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'quick_compose_rows.dart';

/// 选择器接缝：默认弹真日历 / 真表盘。
///
/// widget 测试里注入假实现——真 `TimePickerDialog` 的表盘要拖拽、文本模式又受
/// locale 的 12/24 小时制影响，硬驱动会得到一条不稳的端到端（M6 总纲第 9 条要求
/// 每条断言都能稳定复现红）。合成逻辑本身由 `applyTime` / `preserveTime` 的单测覆盖。
typedef DateFieldPicker = Future<DateTime?> Function(
    BuildContext context, DateTime? current);

/// 日期行：值文案按 [formatTaskDate]（`10-18` / `10-18 14:30` / 未设置）。
class ComposeDateTimeRow extends StatelessWidget {
  const ComposeDateTimeRow({
    super.key,
    required this.rowKey,
    required this.label,
    required this.value,
    required this.onChanged,
    this.height = 44,
    this.clearable = true,
    this.placeholder = '未设置',
    this.helpText,
    this.pickDate,
    this.pickTime,
  });

  final String rowKey;
  final String label;

  /// 本地时间的当前值（`Task` 里存 UTC，展示前要 `.toLocal()`）。
  final DateTime? value;

  /// null = 清空该字段。
  final ValueChanged<DateTime?> onChanged;

  final double height;

  /// 详情面板当前拿不到「把字段写回 null」的用例入口，所以不渲染 ✕（见 §A3 缺口说明）。
  final bool clearable;
  final String placeholder;
  final String? helpText;

  /// 两个可选接缝，默认真选择器。
  final DateFieldPicker? pickDate;
  final DateFieldPicker? pickTime;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final DateTime? v = value;
    return ComposeRow(
      height: height,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: InkWell(
              key: ValueKey<String>(rowKey),
              borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
              onTap: () => _pickDate(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.s4, vertical: AppDimens.s8),
                child: Text(
                  v == null ? placeholder : formatTaskDate(v),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, color: v == null ? colors.textFaint : null),
                ),
              ),
            ),
          ),
          if (v != null) _timeButton(context, colors, v),
          if (v != null && clearable)
            IconButton(
              key: ValueKey<String>('$rowKey-clear'),
              icon: Icon(Icons.close, size: 16, color: colors.textFaint),
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }

  /// 行尾的时刻钮：已填显示 `14:30`，没填显示「无时间」；再点只重选时刻，不承担清除。
  Widget _timeButton(BuildContext context, AppColors colors, DateTime v) {
    final bool hasTime = hasTimeOfDay(v);
    return InkWell(
      key: ValueKey<String>('$rowKey-time'),
      borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      onTap: () => _pickTime(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(Icons.schedule,
              size: 14,
              color: hasTime ? colors.accent : colors.textFaint),
          const SizedBox(width: 2),
          Text(
            hasTime ? formatTimeOfDay(v) : '无时间',
            style: TextStyle(
              fontSize: 12,
              color: hasTime ? colors.accent : colors.textFaint,
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateFieldPicker pick = pickDate ?? _defaultDate;
    // 只在 await 之前取回调，await 之后不再碰 context（选择器关掉时页面可能已销毁）。
    final ValueChanged<DateTime?> emit = onChanged;
    final DateTime? next = await pick(context, value);
    if (next != null) emit(next);
  }

  Future<void> _pickTime(BuildContext context) async {
    final DateFieldPicker pick = pickTime ?? _defaultTime;
    final ValueChanged<DateTime?> emit = onChanged;
    final DateTime? next = await pick(context, value);
    if (next != null) emit(next);
  }

  Future<DateTime?> _defaultDate(BuildContext context, DateTime? current) =>
      pickDateWithOptionalTime(context, initial: current, helpText: helpText);

  Future<DateTime?> _defaultTime(BuildContext context, DateTime? current) =>
      current == null
          ? Future<DateTime?>.value()
          // 表盘上方那行提示沿用「Select time」，不套用日期行的 helpText。
          : pickTimeFor(context, current);
}

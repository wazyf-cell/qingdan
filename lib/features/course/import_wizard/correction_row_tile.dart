// 校正界面的单行（§4.3）。桌面 = 表格行 + 行内展开编辑；移动 = 卡片 + 底部抽屉。
// 两端**共用同一个行视图数据与同一个编辑面板**，只有容器分端（§五 复用策略）。

import 'package:flutter/material.dart';

import 'package:qingdan/import/course/course_row_parser.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'import_wizard_types.dart';


/// 一行的展示字段。课程解析失败时（✗ 行常常没有 Course）由原始单元格兜底，
/// 让用户看见文件里到底写了什么，而不是看见一片空白。
class RowView {
  const RowView({
    required this.rowNumber,
    required this.name,
    required this.daySection,
    required this.teacher,
    required this.location,
    required this.weeks,
  });

  final int rowNumber;
  final String name;
  final String daySection;
  final String teacher;
  final String location;
  final String weeks;
}

class CorrectionRowTile extends StatelessWidget {
  const CorrectionRowTile({
    super.key,
    required this.correction,
    required this.view,
    required this.isMobile,
    required this.expanded,
    required this.onTapRow,
    required this.onQuickAction,
    required this.colors,
    this.selected = false,
    this.showCheck = false,
    this.onLongPress,
    this.onToggleSelect,
  });

  final CorrectionRow correction;
  final RowView view;
  final bool isMobile;
  final bool expanded;
  final VoidCallback onTapRow;
  final void Function(RowQuickAction action) onQuickAction;
  final AppColors colors;

  /// 多选态：勾选框是否显示、当前是否选中（移动端长按后才出现）。
  final bool selected;
  final bool showCheck;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;

  static const double leftWidth = 190;

  @override
  Widget build(BuildContext context) {
    final ParsedCourseRow parsed = correction.parsed;
    final bool dim = !correction.kept;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          key: ValueKey<String>('row-${view.rowNumber}'),
          onLongPress: onLongPress,
          onTap: onTapRow,
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
              color: expanded ? colors.surfaceHigh : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: AppDimens.s8),
            child: isMobile
                ? _mobileBody(parsed, dim)
                : Row(
                    children: <Widget>[
                      SizedBox(
                          width: leftWidth, child: _leftCell(parsed, dim)),
                      Expanded(child: _fieldsRow(parsed, dim)),
                      _quickMenu(),
                    ],
                  ),
          ),
        ),
        if (parsed.messages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
                left: AppDimens.s12, right: AppDimens.s12, bottom: AppDimens.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final String m in parsed.messages)
                  Text('└ ${statusGlyph(parsed.status)} $m',
                      style: TextStyle(
                          fontSize: 12,
                          color: parsed.isError
                              ? colors.overdue
                              : colors.priorityMedium)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _mobileBody(ParsedCourseRow parsed, bool dim) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: AppDimens.courseBarWidth,
          margin: const EdgeInsets.only(right: AppDimens.s12),
          color: statusColor(parsed),
        ),
        if (showCheck) _check(),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _name(parsed, dim),
              const SizedBox(height: 2),
              Text(
                  <String>[
                    view.daySection,
                    if (view.location.isNotEmpty) view.location,
                    if (view.weeks.isNotEmpty) view.weeks,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            ],
          ),
        ),
        _quickMenu(),
      ],
    );
  }

  Widget _leftCell(ParsedCourseRow parsed, bool dim) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.s12),
      child: Row(
        children: <Widget>[
          if (showCheck) _check(),
          Text(statusGlyph(parsed.status),
              key: ValueKey<String>('status-${view.rowNumber}'),
              style: TextStyle(
                  color: statusColor(parsed), fontWeight: FontWeight.w700)),
          const SizedBox(width: AppDimens.s8),
          Expanded(child: _name(parsed, dim)),
        ],
      ),
    );
  }

  Widget _name(ParsedCourseRow parsed, bool dim) {
    return Text(
      view.name.isEmpty ? '（第 ${parsed.rowNumber} 行）' : view.name,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        decoration: dim ? TextDecoration.lineThrough : null,
        color: dim ? colors.textFaint : colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// 字段列用固定窄宽度排布，整表因此**不需要横向滚动**——首列天然「冻结」。
  /// （设计稿的「可冻结首列表格」在弹窗宽度下退化成「无横向滚动」，
  ///  长值走省略号 + tooltip，见变更日志 S5-c 说明。）
  Widget _check() {
    return Checkbox(
      key: ValueKey<String>('check-${view.rowNumber}'),
      value: selected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onChanged: (_) => onToggleSelect?.call(),
    );
  }

  Widget _fieldsRow(ParsedCourseRow parsed, bool dim) {
    final TextStyle style = TextStyle(
        fontSize: 12, color: dim ? colors.textFaint : colors.textSecondary);
    return Row(
      children: <Widget>[
        _cell(view.daySection, 96, style),
        _cell(view.teacher, 96, style),
        _cell(view.location, 130, style),
        Expanded(child: _cell(view.weeks, 0, style)),
      ],
    );
  }

  Widget _cell(String text, double width, TextStyle style) {
    final Widget child = Text(text.isEmpty ? '—' : text,
        overflow: TextOverflow.ellipsis, style: style);
    return width == 0
        ? child
        : SizedBox(width: width, child: Tooltip(message: text, child: child));
  }

  Widget _quickMenu() {
    return PopupMenuButton<RowQuickAction>(
      key: ValueKey<String>('fix-${view.rowNumber}'),
      tooltip: '修正',
      icon: const Icon(Icons.build_outlined, size: 18),
      onSelected: onQuickAction,
      itemBuilder: (BuildContext context) =>
          <PopupMenuEntry<RowQuickAction>>[
        for (final RowQuickAction a in RowQuickAction.values)
          PopupMenuItem<RowQuickAction>(
              value: a, child: Text(describeQuickAction(a))),
      ],
    );
  }

  Color statusColor(ParsedCourseRow parsed) => switch (parsed.status) {
        RowStatus.ok => colors.success,
        RowStatus.warning => colors.priorityMedium,
        RowStatus.error => colors.overdue,
      };

  static String statusGlyph(RowStatus status) => switch (status) {
        RowStatus.ok => '✓',
        RowStatus.warning => '⚠',
        RowStatus.error => '✗',
      };
}

/// 「修正▾」里的三个高频动作（§4.3 规则 3：不展开编辑器也要能解决 80% 的错误行）。
enum RowQuickAction { fillAllWeeks, ignore, remove }

String describeQuickAction(RowQuickAction a) => switch (a) {
      RowQuickAction.fillAllWeeks => '按全学期填充周次',
      RowQuickAction.ignore => '忽略此条',
      RowQuickAction.remove => '删除此条',
    };

import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'package:qingdan/theme/app_palette.dart';

import 'week_display.dart';

/// 点课程块之后弹层的结果。
enum CourseBlockAction { closed, edit, deleted }

/// 点击课程块的详情弹层（§4.1：桌面锚定 / 移动底部抽屉，本轮统一用两端各自的形态）。
///
/// 弹层自己**不写库**：删除只回到 [CourseBlockAction.deleted]，落库由调用方
/// （课表面板 → 用例层）做，这样「弹层关闭 → 重载 → 顶部回执」的顺序只有一处。
Future<CourseBlockAction> showCourseBlockSheet(
  BuildContext context, {
  required Course course,
  required SectionLayout layout,
  required bool isMobile,
}) async {
  final NavigatorState nav = Navigator.of(context);
  final Widget body = CourseBlockDetail(
    course: course,
    layout: layout,
    onEdit: () => nav.pop(CourseBlockAction.edit),
    onDelete: () async {
      // 顺序要的是「先出确认框，确认后才关弹层」：反过来的话用户点了删除
      // 却看到弹层凭空消失，不知道发生了什么。
      if (!await confirmCourseDelete(context, course: course)) return;
      if (nav.mounted) nav.pop(CourseBlockAction.deleted);
    },
  );
  final CourseBlockAction? action = isMobile
      ? await _mobileBlockSheet(context, body: body)
      : await showDialog<CourseBlockAction>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            content: SizedBox(width: 280, child: body),
          ),
        );
  // 点遮罩 / 返回键关掉：没有选任何动作。
  return action ?? CourseBlockAction.closed;
}

/// 移动形态的底部抽屉，**显式限高 60% 屏高 + 可滚动**（细化 §2.8:143）。
///
/// 不给限高时它靠的是 `showModalBottomSheet` 默认的 9/16≈56% 上限，内容一多
/// 就被裁掉而且没有滚动（实测长课名 + 长地点溢出 11px）；这里把「不超 60%」
/// 写成代码，而不是指望默认值。
Future<CourseBlockAction?> _mobileBlockSheet(
  BuildContext context, {
  required Widget body,
}) =>
    showModalBottomSheet<CourseBlockAction>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => ConstrainedBox(
        key: const ValueKey<String>('block-sheet-shell'),
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
        child: SafeArea(child: SingleChildScrollView(child: body)),
      ),
    );

/// 删除的二次确认框（块详情弹层与课程编辑器共用一份文案与语义）。
///
/// 措辞上有两条硬要求：① 必须写「无法找回」——课程**没有回收站**，软删除对用户
/// 等于永久删除（回收站只管任务），界面上绝不能给「可以找回」的错觉（A6 定案）；
/// ② 必须写明会同步到其他设备，否则用户以为只影响本机。
Future<bool> confirmCourseDelete(
  BuildContext context, {
  required Course course,
}) async {
  final String summary = '${formatWeeksForDisplay(course.weeks)} '
      '· ${weekdayName(course.weekday)} '
      '· 第 ${course.startSection}-${course.endSection} 节';
  final AppColors colors = AppColors.of(context);
  final bool? yes = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text('删除「${course.name}」？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(summary, style: AppTypography.meta),
          const SizedBox(height: AppDimens.s8),
          const Text('删除后该课程从课表消失，会同步到你的其他设备。',
              style: AppTypography.body),
          Text('课程没有回收站，删除后无法找回。',
              style: AppTypography.body
                  .copyWith(color: colors.overdue)),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey<String>('delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('删除', style: TextStyle(color: colors.overdue)),
        ),
      ],
    ),
  );
  return yes == true;
}

/// 详情内容：课名 + 星期节次 + 老师 + 地点 + 周次 + 本节课时间区间 + 编辑/删除。
class CourseBlockDetail extends StatelessWidget {
  const CourseBlockDetail({
    super.key,
    required this.course,
    required this.layout,
    required this.onEdit,
    this.onDelete,
  });

  final Course course;
  final SectionLayout layout;
  final VoidCallback onEdit;

  /// 不传就不渲染「删除」（例如只读预览的地方）。
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.all(AppDimens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: CoursePalette.of(
                      brightness, course.effectiveColorIndex),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppDimens.s8),
              Expanded(
                child: Text(course.name, style: AppTypography.panelTitle),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.s12),
          Text('星期节次：${weekdayName(course.weekday)} '
              '第 ${course.startSection}-${course.endSection} 节',
              style: AppTypography.body),
          if (course.teacher != null)
            Text('老师：${course.teacher}', style: AppTypography.body),
          if (course.location != null)
            Text('地点：${course.location}', style: AppTypography.body),
          Text('周次：${formatWeeksForDisplay(course.weeks)}',
              style: AppTypography.body),
          if (timeRangeText() != null)
            Text('本节课时间：${timeRangeText()}',
                style: AppTypography.meta
                    .copyWith(color: colors.textSecondary)),
          const SizedBox(height: AppDimens.s12),
          // 编辑与删除并排；删除用红字（与确认框、色板 overdue 同一档）。
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (onDelete != null)
                  TextButton.icon(
                    key: const ValueKey<String>('block-delete'),
                    onPressed: () => onDelete!.call(),
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: colors.overdue),
                    label: Text('删除',
                        style: TextStyle(color: colors.overdue)),
                  ),
                TextButton(
                  key: const ValueKey<String>('block-edit'),
                  onPressed: onEdit,
                  child: const Text('编辑'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 本节课的起止时间（由作息表换算；节次缺失时不显示，不瞎猜）。
  String? timeRangeText() {
    final int? start = layout.timeOf(course.startSection)?.startMinutes;
    final int? end = layout.timeOf(course.endSection)?.endMinutes;
    if (start == null || end == null) return null;
    return '${formatMinutes(start)}–${formatMinutes(end)}';
  }
}

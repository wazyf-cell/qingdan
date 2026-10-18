import 'package:flutter/material.dart';

import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_pane_model.dart';

/// 周次网格选择器（M6-A A5）：点一格翻到那一周，**长按一格 = 一键校准**。
///
/// 校准为什么放在这里：用户说的「显示错了一周」，真正错的是
/// `semester.first_week_monday`（「今天是第几周」完全由它推出）。所以在选周的
/// 地方顺手把「这一周其实是本周」改掉，比另开一个设置页更对症。
///
/// 返回校准后的「开学第一周周一」；只翻了周、或取消，都返回 null。回执**不在
/// 本弹层里显示**（模态弹层下面看不见 SnackBar，总纲陷阱表第 1 条），
/// 由课表页顶部那行行内回执负责。
Future<DateTime?> showWeekPickerSheet(
  BuildContext context, {
  required CoursePaneModel model,
  required bool isMobile,
}) {
  return showModalBottomSheet<DateTime?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6),
    builder: (BuildContext ctx) => _WeekPicker(model: model, isMobile: isMobile),
  );
}

/// 纯日期文案。`first_week_monday` 按**纯日期**存（UTC 零点，见 `semester.dart`
/// 字段注释），所以直接读它的年月日，绝不做 `toLocal()`——负时区设备上
/// `toLocal()` 会把 00:00 退到前一天，日期就白错一天。
String weekMondayText(DateTime monday) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${monday.year}-${two(monday.month)}-${two(monday.day)}';
}

class _WeekPicker extends StatelessWidget {
  const _WeekPicker({required this.model, required this.isMobile});

  final CoursePaneModel model;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final int total = model.totalWeeks;
    final int todayWeek = model.todayWeek;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s16, 0, AppDimens.s16, AppDimens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                  child: Text('选择周次', style: AppTypography.panelTitle)),
              Text('长按一格 = 把这一周设为本周',
                  style: AppTypography.meta
                      .copyWith(color: colors.textFaint)),
            ],
          ),
          const SizedBox(height: AppDimens.s12),
          // 最多 30 周 → 最多 6 行，不需要滚动，所以 shrinkWrap + 关掉自带滚动。
          GridView.count(
            crossAxisCount: isMobile ? 5 : 8,
            // 默认 0.5 会把格子拉成竖长条；周次格要的是扁平方块。
            childAspectRatio: isMobile ? 1.2 : 2,
            mainAxisSpacing: AppDimens.s8,
            crossAxisSpacing: AppDimens.s8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              for (int n = 1; n <= total; n++)
                _WeekCell(
                  week: n,
                  isCurrent: n == model.week,
                  // 学期外的周次（今天不在学期内）不标「今」，否则等于在骗人。
                  isToday: todayWeek != 0 && n == todayWeek,
                  onTap: () {
                    model.selectWeek(n);
                    Navigator.of(context).pop();
                  },
                  onLongPress: () => _calibrate(context, model: model, n: n),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 长按 → 确认框（讲清改哪个字段、影响什么）→ 调模型保存 → 关面板。
Future<void> _calibrate(
  BuildContext context, {
  required CoursePaneModel model,
  required int n,
}) async {
  final Semester? semester = model.semester;
  if (semester == null) return;
  final NavigatorState nav = Navigator.of(context);
  final DateTime planned = Semester.mondayOf(model.today)
      .subtract(Duration(days: 7 * (n - 1)));
  final bool? yes = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text('把第 $n 周设为本周？'),
      content: Text('这会修改学期「${semester.name}」的开学第一周日期'
          '（改为 ${weekMondayText(planned)}），所有周次显示与今日高亮都会跟着变，'
          '并同步到你的其他设备。'),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('calibrate-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey<String>('calibrate-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('设为本周'),
        ),
      ],
    ),
  );
  if (yes != true) return;
  // 三个字段一次写完（模型内部只调一次 saveSemester）。
  final DateTime? saved = await model.calibrateThisWeekTo(n);
  if (saved != null && nav.mounted) nav.pop(saved);
}

class _WeekCell extends StatelessWidget {
  const _WeekCell({
    required this.week,
    required this.isCurrent,
    required this.isToday,
    required this.onTap,
    required this.onLongPress,
  });

  final int week;
  final bool isCurrent;
  final bool isToday;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Badge(
      // 「今」角标：Badge 的默认底色是 error 红，必须显式给色，否则本周看起来像逾期。
      isLabelVisible: isToday,
      backgroundColor: isCurrent ? colors.surface : colors.accent,
      label: const Text('今', style: TextStyle(fontSize: 9)),
      child: GestureDetector(
        key: ValueKey<String>('week-pick-$week'),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isCurrent ? colors.accent : colors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppDimens.radiusMobile),
            border: Border.all(
                color: isCurrent ? colors.accent : colors.divider, width: 1),
          ),
          child: Text(
            '$week',
            style: AppTypography.panelTitle.copyWith(
                color: isCurrent ? colors.surface : colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

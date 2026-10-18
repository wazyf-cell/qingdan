import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 周视图头部（细化 §2.6:121-128）：`[‹] 第 N 周 / 共 M 周 [›] [今天] [周末▣(移动)]`。
///
/// 边界禁用：第 1 周 ‹ 置灰不可点、最后一周 › 同理（**不给空周**，§2.6:125）。
/// 末尾两个入口：＋ 添加课程（F28 手工录入）、⚙ 学期与作息（S4b 编辑器）。
/// 没有学期时两者都不传，按钮不渲染——不留死按钮。
///
/// 周次标签本身可点（M6-A A5：弹周次网格选择器）。A8 的「上次更新 / 导入时间」
/// 在周次行**下方单独一行**，绝不塞进这一行——411dp 真机实测这一行已经排到
/// 只剩 123dp 标签余量，再塞就重演「周次标签换行压住星期轴」（S4b 事故）。
class CourseWeekHeader extends StatelessWidget {
  const CourseWeekHeader({
    super.key,
    required this.week,
    required this.totalWeeks,
    required this.canPrev,
    required this.canNext,
    required this.isMobile,
    this.showWeekend = false,
    this.todayButtonDisabled = false,
    this.onPrev,
    this.onNext,
    this.onToday,
    this.onToggleWeekend,
    this.onAddCourse,
    this.onOpenSetup,
    this.onImport,
    this.onPickWeek,
    this.freshnessLabel,
    this.freshnessTooltip,
    this.onFreshnessTap,
    this.semesterSwitcher,
  });

  final int week;
  final int totalWeeks;
  final bool canPrev;
  final bool canNext;
  final bool isMobile;
  final bool showWeekend;
  final bool todayButtonDisabled;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onToday;
  final VoidCallback? onToggleWeekend;

  /// ＋ 添加课程 / ⚙ 学期与作息设置 / ⤓ 导入课表文件。
  ///
  /// [onImport] 只在桌面端传：411dp 头部一行已经排到 123dp 的标签余量，
  /// 再塞一个图标就要牺牲周次标签（移动端改从「学期与作息」弹层进）。
  final VoidCallback? onAddCourse;
  final VoidCallback? onOpenSetup;
  final VoidCallback? onImport;

  /// 点周次标签 → 周次网格选择器（A5）。不传时标签仍可看但不可点。
  final VoidCallback? onPickWeek;

  /// 「上次更新 / 导入时间」那一行（A8）；null = 没有数据，整行不渲染。
  final String? freshnessLabel;
  final String? freshnessTooltip;
  final VoidCallback? onFreshnessTap;

  /// 周次行**最左边**的学期名按钮（M6-D §7.1）。由 `course_pane.dart` 传
  /// `SemesterSwitcher` 进来——头部只管排版，不认识学期这件事。
  final Widget? semesterSwitcher;

  /// 移动端一行要摆 7 个元素，默认内边距会把周次标签挤到换行（真机 411dp 实测
  /// 第二行「16 周」压在星期轴上），加了 maxLines 又会被省略号截断。
  /// 所以只收横向、不动纵向（头部本来就 44dp 高）：文字按钮去掉 64dp 最小宽。
  ButtonStyle? get _tightText => isMobile
      ? TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
          visualDensity: VisualDensity.compact,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )
      : null;

  /// ＋/⚙ 在移动端收到 40dp 宽（高度仍 48dp，纵向不花钱）。
  ButtonStyle? get _tightIcon => isMobile
      ? IconButton.styleFrom(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(40, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String? stamp = freshnessLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.divider, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: isMobile
                ? AppDimens.courseHeaderMobile
                : AppDimens.courseHeaderDesktop,
            child: Row(
              children: <Widget>[
                ?semesterSwitcher,
                _NavButton(
                  icon: Icons.chevron_left,
                  tooltip: '上一周',
                  enabled: canPrev,
                  onPressed: onPrev,
                ),
                Expanded(
                  child: InkWell(
                    onTap: onPickWeek,
                    child: Center(
                      child: Text(
                        weekLabel(week, totalWeeks),
                        // key 挂在 Text 上：测试既要点它（tap 命中的是外面的
                        // InkWell），又要读它的文案（断言周次真的翻了）。
                        key: const ValueKey<String>('week-label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.panelTitle, // 16sp / w600（2026-10-10 定案）
                      ),
                    ),
                  ),
                ),
                _NavButton(
                  icon: Icons.chevron_right,
                  tooltip: '下一周',
                  enabled: canNext,
                  onPressed: onNext,
                ),
                TextButton(
                  style: _tightText,
                  onPressed: todayButtonDisabled ? null : onToday,
                  child: const Text('今天'),
                ),
                if (isMobile)
                  TextButton(
                    style: _tightText,
                    onPressed: onToggleWeekend,
                    child: Text(showWeekend ? '收起周末' : '周末'),
                  ),
                if (onAddCourse != null)
                  IconButton(
                    key: const ValueKey<String>('btn-add-course'),
                    style: _tightIcon,
                    tooltip: '添加课程',
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: onAddCourse,
                  ),
                if (onImport != null)
                  IconButton(
                    key: const ValueKey<String>('btn-import'),
                    style: _tightIcon,
                    tooltip: '导入课表文件',
                    // A7：导入 = 数据进应用，箭头朝下（原来是 file_upload 朝上）。
                    icon: const Icon(Icons.file_download_outlined, size: 20),
                    onPressed: onImport,
                  ),
                if (onOpenSetup != null)
                  IconButton(
                    key: const ValueKey<String>('btn-setup'),
                    style: _tightIcon,
                    tooltip: '学期与作息',
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: onOpenSetup,
                  ),
              ],
            ),
          ),
          if (stamp != null)
            _FreshnessRow(
              label: stamp,
              tooltip: freshnessTooltip,
              onTap: onFreshnessTap,
            ),
        ],
      ),
    );
  }
}

/// A8 的新鲜度行：12sp、muted、单独占一行。
class _FreshnessRow extends StatelessWidget {
  const _FreshnessRow({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Text text = Text(
      label,
      key: const ValueKey<String>('course-freshness'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.meta.copyWith(color: colors.textFaint),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s12, 0, AppDimens.s12, AppDimens.s4),
      child: InkWell(
        key: const ValueKey<String>('course-freshness-tap'),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Icon(Icons.schedule, size: 14, color: colors.textFaint),
            const SizedBox(width: AppDimens.s4),
            // 长文件名必须被 Flexible 收掉，不能把这一行撑爆。
            Flexible(
              child: tooltip == null
                  ? text
                  : Tooltip(message: tooltip!, child: text),
            ),
          ],
        ),
      ),
    );
  }
}

/// 周次标签文案。两份设计稿不一致（`第 12 周 / 16` vs `第 12 周 / 共 16 周`），
/// 2026-10-10 定案取后者为准，细化 §2.6 已按勘误处理。
String weekLabel(int week, int totalWeeks) =>
    totalWeeks == 0 ? '第 $week 周' : '第 $week 周 / 共 $totalWeeks 周';

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return SizedBox(
      width: AppDimens.courseNavButton,
      height: AppDimens.courseNavButton,
      child: IconButton(
        // 禁用态：40% 不透明度且不可点（细化 §2.6:125）。
        icon: Icon(icon, size: 20),
        color: colors.textSecondary
            .withValues(alpha: enabled ? 1 : 0.4),
        tooltip: tooltip,
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}

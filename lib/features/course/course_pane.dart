import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_grid.dart';
import 'course_pane_actions.dart';
import 'course_pane_empty.dart';
import 'course_pane_model.dart';
import 'course_setup.dart';
import 'course_toast.dart';
import 'course_week_header.dart';
import 'import_history_sheet.dart';
import 'import_wizard/import_wizard.dart';
import 'semester_switcher.dart';
import 'today_summary_bar.dart';

/// 课表周视图（F31 / F34 + M6-A A5/A6/A7/A8）。三栏、两栏、抽屉三种形态共用同一个面板。
///
/// 今天落在学期内时顶部出现今日摘要条（F34 **不单独做页面**，界面 §4.1:47）；
/// 节次不在作息表里的课进底部「未排时间」收纳区，绝不静默截断（§3.4）。
/// 周内容外面套 [CourseWeekPager]（左右滑动切周），页与页共享模型里那一份
/// 整学期课程缓存，所以翻页不需要再查库。
///
/// 「打开弹层 → 落库 → 回执」那一层不在这里，见 `course_pane_actions.dart`
/// （本文件卡在 300 行红线上，2026-10-19 按职责拆了一次）。
class CoursePane extends StatefulWidget {
  const CoursePane({super.key});

  @override
  State<CoursePane> createState() => _CoursePaneState();
}

class _CoursePaneState extends State<CoursePane> with CoursePaneActions {
  SyncStatusModel? _sync;
  DateTime? _lastSyncSeen;

  @override
  void initState() {
    super.initState();
    // 首帧后再加载：load() 会 notifyListeners，在 build 期间同步通知会炸。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final CoursePaneModel model = context.read<CoursePaneModel>();
      if (!model.loaded) model.load();
      // 未装配同步层（纯 UI 测试 / 未配置同步）时照常工作，与状态槽同一口径。
      final SyncStatusModel? sync = context.read<SyncStatusModel?>();
      if (sync == null) return;
      _sync = sync;
      _lastSyncSeen = sync.status.lastSuccessAt;
      sync.addListener(_onSyncChanged);
    });
  }

  @override
  void dispose() {
    _sync?.removeListener(_onSyncChanged);
    // 回执控制器的释放由 CoursePaneActions 串在 super 上，
    // 顺序与拆分前一致：摘监听 → toast.dispose → State.dispose。
    super.dispose();
  }

  /// 同步成功之后必须自己重载：模型只在首帧加载一次，而任务面板靠「切视图」
  /// 顺带刷新、课表面板没有这个副作用，所以**对端同步来的课会永远看不见**，
  /// 除非重启应用（2026-10-11 S6-4 真机实测：库里已有 1 学期 + 5 门课 + 12 节
  /// 作息，周视图仍显示「还没有学期」）。
  void _onSyncChanged() {
    final DateTime? now = _sync?.status.lastSuccessAt;
    if (now == null || now == _lastSyncSeen) return;
    _lastSyncSeen = now;
    if (!mounted) return;
    context.read<CoursePaneModel>().load();
  }

  @override
  Widget build(BuildContext context) {
    final CoursePaneModel model = context.watch<CoursePaneModel>();

    if (model.error != null) {
      return Center(child: Text('课表加载失败：${model.error}'));
    }
    if (!model.hasSemester) {
      return _NoSemesterState(isMobile: isMobile);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (model.todayInSemester)
          TodaySummaryBar(
            today: model.today,
            courses: model.todayCourses,
            layout: model.layout,
            // §2.8:140 摘要条点击定位今天（M5-S5 漏接的一条：参数一直留着没人传）。
            onTap: model.revealToday,
          ),
        CourseWeekHeader(
          week: model.week,
          totalWeeks: model.totalWeeks,
          // §7.1：周次行最左边的学期名按钮（点开学期面板）。放在最左是因为
          // 这一行在 411dp 上只剩 ~123dp 给周次标签，任何新入口都只能去挤
          // 自己该挤的地方——学期名有定宽上限（`semester_switcher.dart`）。
          semesterSwitcher: SemesterSwitcher(
            name: model.semester?.name ?? '',
            isMobile: isMobile,
            onTap: () => openSemesters(model),
          ),
          canPrev: model.canPrev,
          canNext: model.canNext,
          isMobile: isMobile,
          showWeekend: model.showWeekend,
          // 学期外 `todayWeek` 是 0，「今天」点了只会走一次空转的 selectWeek(0)，
          // 看着能点其实没反应 = 真缺陷，直接置灰（2026-10-18 复核）。
          todayButtonDisabled:
              !model.todayInSemester || model.week == model.todayWeek,
          onPrev: model.prevWeek,
          onNext: model.nextWeek,
          onToday: model.goToday,
          onToggleWeekend: model.toggleWeekend,
          onAddCourse: addCourse,
          onOpenSetup: () => showCourseSetup(context, isMobile: isMobile),
          // 导入入口：桌面在头部给图标；移动端头部一行已经排满，改从
          // 「学期与作息」弹层进（同一个 showImportWizard）。
          onImport: isMobile ? null : () => showImportWizard(context),
          onPickWeek: () => pickWeek(model),
          // A8：上次更新 / 导入时间。没有数据时 label 为 null → 整行不渲染。
          freshnessLabel: model.freshnessLabel,
          freshnessTooltip: model.freshnessTooltip,
          onFreshnessTap: () => showImportHistorySheet(context,
              batches: model.freshness.batches, isMobile: isMobile),
        ),
        ListenableBuilder(
          listenable: toast,
          builder: (_, _) => CourseToastLine(
            text: toast.text,
            opaque: toast.opaque,
          ),
        ),
        // 作息表空着的时候网格画不出任何块，全部课程都会掉进「未排时间」。
        // 这时给用户一张空网格等于让他以为课表坏了（2026-10-18 模拟器实测），
        // 所以换成把因果讲清楚 + 一个「去填作息」的出口；收纳区也不再重复列一遍。
        if (model.details.isEmpty)
          Expanded(
            child: NoTimetableState(
              courseCount: model.allCourses.length,
              onFill: () => showCourseSetup(context, isMobile: isMobile),
            ),
          )
        else ...<Widget>[
          Expanded(
            child: CourseWeekPager(
              totalWeeks: model.totalWeeks,
              week: model.week,
              onWeekChanged: (int week) => model.selectWeek(week),
              pageBuilder: (BuildContext _, int week) => CourseWeekGrid(
                days: model.visibleDays(isMobile: isMobile),
                layout: model.layout,
                week: week,
                coursesOf: (int weekday) => model.coursesOnDay(week, weekday),
                dateOf: (int weekday) => model.dateInWeek(week, weekday),
                todayWeekday:
                    week == model.todayWeek ? model.today.weekday : null,
                isMobile: isMobile,
                onBlockTap: (Course tapped, List<Course> sameSlot) =>
                    openBlock(tapped),
              ),
            ),
          ),
          if (model.unscheduled.isNotEmpty)
            UnscheduledStrip(courses: model.unscheduled),
        ],
      ],
    );
  }
}

/// 还没有学期时的空态：给一个真的入口，不放死文案。
class _NoSemesterState extends StatelessWidget {
  const _NoSemesterState({required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.event_note_outlined, size: 48, color: colors.textFaint),
          const SizedBox(height: AppDimens.s12),
          const Text('还没有学期，先建一个学期和作息表',
              style: AppTypography.body),
          const SizedBox(height: AppDimens.s4),
          Text('导入课表文件时也会引导你建',
              style: AppTypography.meta.copyWith(color: colors.textFaint)),
          const SizedBox(height: AppDimens.s16),
          FilledButton(
            key: const ValueKey<String>('empty-create-semester'),
            onPressed: () => showCourseSetup(context, isMobile: isMobile),
            child: const Text('建学期'),
          ),
        ],
      ),
    );
  }
}

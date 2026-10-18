import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/features/shell/sidebar/sync_status_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_block_sheet.dart';
import 'course_grid.dart';
import 'course_pane_empty.dart';
import 'course_pane_model.dart';
import 'course_setup.dart';
import 'course_toast.dart';
import 'course_week_header.dart';
import 'import_history_sheet.dart';
import 'import_wizard/import_wizard.dart';
import 'today_summary_bar.dart';
import 'week_picker_sheet.dart';

/// 课表周视图（F31 / F34 + M6-A A5/A6/A7/A8）。三栏、两栏、抽屉三种形态共用同一个面板。
///
/// 今天落在学期内时顶部出现今日摘要条（F34 **不单独做页面**，界面 §4.1:47）；
/// 节次不在作息表里的课进底部「未排时间」收纳区，绝不静默截断（§3.4）。
/// 周内容外面套 [CourseWeekPager]（左右滑动切周），页与页共享模型里那一份
/// 整学期课程缓存，所以翻页不需要再查库。
class CoursePane extends StatefulWidget {
  const CoursePane({super.key});

  @override
  State<CoursePane> createState() => _CoursePaneState();
}

class _CoursePaneState extends State<CoursePane> {
  SyncStatusModel? _sync;
  DateTime? _lastSyncSeen;

  /// 校准 / 删除之后的行内回执（不用 SnackBar，见 `course_toast.dart`）。
  final CourseToastController _toast = CourseToastController();

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
    _toast.dispose();
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

  bool get _isMobile =>
      MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow;

  Future<void> _addCourse() async {
    final CoursePaneModel model = context.read<CoursePaneModel>();
    final CourseUseCase useCase = context.read<CourseUseCase>();
    final Course? draft =
        await showCourseEditor(context,
            isMobile: _isMobile,
            totalWeeks: model.totalWeeks,
            maxSection: model.maxSection);
    if (draft == null) return;
    // 弹层关闭后不再碰 context：useCase 与 model 都在 await 前取好了。
    // 新建的课必须挂上当前学期，否则按学期过滤的周视图永远查不到它
    // （F28 端到端测试第一次就是死在这一步）。
    await useCase.save(draft.copyWith(
        semesterId: draft.semesterId ?? model.semester?.id));
    await model.load();
  }

  Future<void> _openBlock(Course course) async {
    final CoursePaneModel model = context.read<CoursePaneModel>();
    final CourseUseCase useCase = context.read<CourseUseCase>();
    final CourseBlockAction action = await showCourseBlockSheet(
      context,
      course: course,
      layout: model.layout,
      isMobile: _isMobile,
    );
    if (action == CourseBlockAction.deleted) {
      await _deleteCourse(course, useCase, model);
      return;
    }
    if (action != CourseBlockAction.edit || !mounted) return;
    final Course? draft =
        await showCourseEditor(context,
            course: course,
            isMobile: _isMobile,
            totalWeeks: model.totalWeeks,
            maxSection: model.maxSection,
            // 编辑器里也能删（A6）：传了 onDelete 才渲染那一行。
            onDelete: () => _deleteCourse(course, useCase, model));
    if (draft == null) return;
    await useCase.save(draft);
    await model.load();
  }

  /// 删课的唯一落库点（块详情弹层与编辑器共用同一条路）。
  ///
  /// `CourseDao.softDelete` 只是把 `deleted` 置 1 供同步传播，**课程没有回收站**，
  /// 所以对用户等于永久删除——回执里必须这么说，不给「能找回」的错觉（A6）。
  Future<void> _deleteCourse(Course course, CourseUseCase useCase,
      CoursePaneModel model) async {
    await useCase.delete(course.id);
    await model.load();
    // await 之后不碰 context；控制器也只有在还挂着时才通知（dispose 后
    // notifyListeners 会抛）。
    if (!mounted) return;
    _toast.show('已删除「${course.name}」（课程没有回收站，无法找回）');
  }

  /// 周次网格选择器：点格子翻周（模型自己就翻了），长按格子校准。
  /// 校准回执在**面板关闭之后**才显示，因为弹层里放 SnackBar 看不见。
  Future<void> _pickWeek(CoursePaneModel model) async {
    final DateTime? calibrated = await showWeekPickerSheet(context,
        model: model, isMobile: _isMobile);
    if (calibrated == null || !mounted) return;
    _toast.show('已把开学第一周改为 ${weekMondayText(calibrated)}');
  }

  @override
  Widget build(BuildContext context) {
    final CoursePaneModel model = context.watch<CoursePaneModel>();

    if (model.error != null) {
      return Center(child: Text('课表加载失败：${model.error}'));
    }
    if (!model.hasSemester) {
      return _NoSemesterState(isMobile: _isMobile);
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
          canPrev: model.canPrev,
          canNext: model.canNext,
          isMobile: _isMobile,
          showWeekend: model.showWeekend,
          // 学期外 `todayWeek` 是 0，「今天」点了只会走一次空转的 selectWeek(0)，
          // 看着能点其实没反应 = 真缺陷，直接置灰（2026-10-18 复核）。
          todayButtonDisabled:
              !model.todayInSemester || model.week == model.todayWeek,
          onPrev: model.prevWeek,
          onNext: model.nextWeek,
          onToday: model.goToday,
          onToggleWeekend: model.toggleWeekend,
          onAddCourse: _addCourse,
          onOpenSetup: () => showCourseSetup(context, isMobile: _isMobile),
          // 导入入口：桌面在头部给图标；移动端头部一行已经排满，改从
          // 「学期与作息」弹层进（同一个 showImportWizard）。
          onImport: _isMobile ? null : () => showImportWizard(context),
          onPickWeek: () => _pickWeek(model),
          // A8：上次更新 / 导入时间。没有数据时 label 为 null → 整行不渲染。
          freshnessLabel: model.freshnessLabel,
          freshnessTooltip: model.freshnessTooltip,
          onFreshnessTap: () => showImportHistorySheet(context,
              batches: model.freshness.batches, isMobile: _isMobile),
        ),
        ListenableBuilder(
          listenable: _toast,
          builder: (_, _) => CourseToastLine(
            text: _toast.text,
            opaque: _toast.opaque,
          ),
        ),
        // 作息表空着的时候网格画不出任何块，全部课程都会掉进「未排时间」。
        // 这时给用户一张空网格等于让他以为课表坏了（2026-10-18 模拟器实测），
        // 所以换成把因果讲清楚 + 一个「去填作息」的出口；收纳区也不再重复列一遍。
        if (model.details.isEmpty)
          Expanded(
            child: NoTimetableState(
              courseCount: model.allCourses.length,
              onFill: () => showCourseSetup(context, isMobile: _isMobile),
            ),
          )
        else ...<Widget>[
          Expanded(
            child: CourseWeekPager(
              totalWeeks: model.totalWeeks,
              week: model.week,
              onWeekChanged: (int week) => model.selectWeek(week),
              pageBuilder: (BuildContext _, int week) => CourseWeekGrid(
                days: model.visibleDays(isMobile: _isMobile),
                layout: model.layout,
                coursesOf: (int weekday) => model.coursesOnDay(week, weekday),
                dateOf: (int weekday) => model.dateInWeek(week, weekday),
                todayWeekday:
                    week == model.todayWeek ? model.today.weekday : null,
                isMobile: _isMobile,
                onBlockTap: (Course tapped, List<Course> sameSlot) =>
                    _openBlock(tapped),
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

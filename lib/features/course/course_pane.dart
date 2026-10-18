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
import 'course_pane_model.dart';
import 'import_wizard/import_wizard.dart';
import 'course_setup.dart';
import 'course_week_header.dart';
import 'today_summary_bar.dart';

/// 课表周视图（F31 / F34）。三栏、两栏、抽屉三种形态共用同一个面板。
///
/// 今天落在学期内时顶部出现今日摘要条（F34 **不单独做页面**，界面 §4.1:47）；
/// 节次不在作息表里的课进底部「未排时间」收纳区，绝不静默截断（§3.4）。
class CoursePane extends StatefulWidget {
  const CoursePane({super.key});

  @override
  State<CoursePane> createState() => _CoursePaneState();
}

class _CoursePaneState extends State<CoursePane> {
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
    final bool? edit = await showCourseBlockSheet(
      context,
      course: course,
      layout: model.layout,
      isMobile: _isMobile,
    );
    if (edit != true || !mounted) return;
    final Course? draft =
        await showCourseEditor(context,
            course: course,
            isMobile: _isMobile,
            totalWeeks: model.totalWeeks,
            maxSection: model.maxSection);
    if (draft == null) return;
    await useCase.save(draft);
    await model.load();
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
          ),
        CourseWeekHeader(
          week: model.week,
          totalWeeks: model.totalWeeks,
          canPrev: model.canPrev,
          canNext: model.canNext,
          isMobile: _isMobile,
          showWeekend: model.showWeekend,
          todayButtonDisabled: model.week == model.todayWeek,
          onPrev: model.prevWeek,
          onNext: model.nextWeek,
          onToday: model.goToday,
          onToggleWeekend: model.toggleWeekend,
          onAddCourse: _addCourse,
          onOpenSetup: () => showCourseSetup(context, isMobile: _isMobile),
          // 导入入口：桌面在头部给图标；移动端头部一行已经排满，改从
          // 「学期与作息」弹层进（同一个 showImportWizard）。
          onImport: _isMobile ? null : () => showImportWizard(context),
        ),
        Expanded(
          child: CourseWeekGrid(
            days: model.visibleDays(isMobile: _isMobile),
            layout: model.layout,
            coursesOf: model.coursesOn,
            dateOf: model.dateOf,
            todayWeekday:
                model.week == model.todayWeek ? model.today.weekday : null,
            isMobile: _isMobile,
            onBlockTap: (Course course, List<Course> _) => _openBlock(course),
          ),
        ),
        if (model.unscheduled.isNotEmpty)
          _UnscheduledStrip(courses: model.unscheduled),
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

/// 「未排时间」收纳区：网格底部的折叠条（2026-10-10 定案：放底部，不挤占列宽）。
class _UnscheduledStrip extends StatelessWidget {
  const _UnscheduledStrip({required this.courses});

  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: AppDimens.s12),
      childrenPadding: const EdgeInsets.only(bottom: AppDimens.s8),
      title: Text('未排时间（${courses.length}）',
          style: AppTypography.body.copyWith(color: colors.textSecondary)),
      subtitle: Text('这些课占的节次不在作息表里，先收在这里，不截断',
          style: AppTypography.meta.copyWith(color: colors.textFaint)),
      children: <Widget>[
        for (final Course c in courses)
          ListTile(
            dense: true,
            title: Text(c.name, style: AppTypography.body),
            subtitle: Text(
              '第 ${c.startSection}-${c.endSection} 节'
              '${c.location == null ? '' : ' · ${c.location}'}',
              style: AppTypography.meta,
            ),
          ),
      ],
    );
  }
}

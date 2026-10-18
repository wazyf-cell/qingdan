import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_block_sheet.dart';
import 'course_editor_sheet.dart';
import 'course_pane.dart';
import 'course_pane_model.dart';
import 'course_toast.dart';
import 'semester_sheet.dart';
import 'week_picker_sheet.dart';

/// 课表面板的**交互接线层**：打开弹层 → 拿回结果 → 落库 → reload → 行内回执。
///
/// 从 `course_pane.dart` 拆出（那边只剩外壳的生命周期与装配）。拆法照抄
/// `course_editor_sheet.dart` 从 `course_setup.dart` 分离那次：同一职责搬走，
/// 调用方靠 import 直接拿到符号。
///
/// 用 `mixin ... on State<CoursePane>` 而不是新 widget，是为了让这次搬迁**零行为
/// 改动**：`context` 还是同一个 `State.context`（Provider 向上查找的路径没变），
/// 元素树少一个节点都没多，回调时序与 await 前后取值的顺序原样保留。
mixin CoursePaneActions on State<CoursePane> {
  /// 校准 / 删除之后的行内回执（不用 SnackBar，见 `course_toast.dart`）。
  final CourseToastController toast = CourseToastController();

  bool get isMobile =>
      MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow;

  @override
  void dispose() {
    toast.dispose();
    super.dispose();
  }

  Future<void> addCourse() async {
    final CoursePaneModel model = context.read<CoursePaneModel>();
    final CourseUseCase useCase = context.read<CourseUseCase>();
    final Course? draft =
        await showCourseEditor(context,
            isMobile: isMobile,
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

  Future<void> openBlock(Course course) async {
    final CoursePaneModel model = context.read<CoursePaneModel>();
    final CourseUseCase useCase = context.read<CourseUseCase>();
    final CourseBlockAction action = await showCourseBlockSheet(
      context,
      course: course,
      layout: model.layout,
      isMobile: isMobile,
    );
    if (action == CourseBlockAction.deleted) {
      await deleteCourse(course, useCase, model);
      return;
    }
    if (action != CourseBlockAction.edit || !mounted) return;
    final Course? draft =
        await showCourseEditor(context,
            course: course,
            isMobile: isMobile,
            totalWeeks: model.totalWeeks,
            maxSection: model.maxSection,
            // 编辑器里也能删（A6）：传了 onDelete 才渲染那一行。
            onDelete: () => deleteCourse(course, useCase, model));
    if (draft == null) return;
    await useCase.save(draft);
    await model.load();
  }

  /// 删课的唯一落库点（块详情弹层与编辑器共用同一条路）。
  ///
  /// `CourseDao.softDelete` 只是把 `deleted` 置 1 供同步传播，**课程没有回收站**，
  /// 所以对用户等于永久删除——回执里必须这么说，不给「能找回」的错觉（A6）。
  Future<void> deleteCourse(Course course, CourseUseCase useCase,
      CoursePaneModel model) async {
    await useCase.delete(course.id);
    await model.load();
    // await 之后不碰 context；控制器也只有在还挂着时才通知（dispose 后
    // notifyListeners 会抛）。
    if (!mounted) return;
    toast.show('已删除「${course.name}」（课程没有回收站，无法找回）');
  }

  /// 周次网格选择器：点格子翻周（模型自己就翻了），长按格子校准。
  /// 校准回执在**面板关闭之后**才显示，因为弹层里放 SnackBar 看不见。
  Future<void> pickWeek(CoursePaneModel model) async {
    final DateTime? calibrated =
        await showWeekPickerSheet(context, model: model, isMobile: isMobile);
    if (calibrated == null || !mounted) return;
    toast.show('已把开学第一周改为 ${weekMondayText(calibrated)}');
  }

  /// 学期面板（M6-D §7.1）：切 / 改 / 删 / 新建学期都从这里进。切换与校准的回执
  /// 由面板**返回**给这里显示——面板一关它自己那行字就没了，而「切过去了没有」
  /// 必须让用户看得见（仍走行内回执，不用 SnackBar）。
  Future<void> openSemesters(CoursePaneModel model) async {
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final TimetableUseCase? templates = context.read<TimetableUseCase?>();
    final String? said = await showSemesterSheet(context,
        model: model,
        semesters: semesters,
        templates: templates,
        isMobile: isMobile);
    if (said == null || !mounted) return;
    toast.show(said);
  }
}

import 'package:flutter/foundation.dart';

import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_conflict.dart';
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

/// 课表周视图的状态模型（F31 / F34）。
///
/// 只经用例层读数据（AGENTS.md：UI 不碰 DAO）。加载失败**记进 [error] 由界面
/// 呈现**，不静默吞掉；与 `SidebarModel` 的区别是本视图失败不阻塞启动，故不 rethrow。
class CoursePaneModel extends ChangeNotifier {
  CoursePaneModel({
    required SemesterUseCase semesterUseCase,
    required CourseUseCase courseUseCase,
    DateTime Function()? clock,
  })  : _semesters = semesterUseCase,
        _courses = courseUseCase,
        _clock = clock ?? DateTime.now;

  final SemesterUseCase _semesters;
  final CourseUseCase _courses;
  final DateTime Function() _clock;

  Semester? semester;
  List<TimeDetail> details = const <TimeDetail>[];
  List<Course> weekCourses = const <Course>[];

  /// 当前显示的周次（1 起）。
  int week = 1;

  /// 移动端周末是否展开（细化 §2.1:64：默认折叠；桌面恒 7 列不看此值）。
  bool showWeekend = false;

  String? error;
  bool loaded = false;

  /// 节次 → 像素布局（与今日摘要共用同一纯函数，§6.3.2）。
  SectionLayout get layout => layoutSections(details);

  bool get hasSemester => semester != null;

  /// 作息表里的最大节数；没有作息表时给个保守上限，免得 stepper 卡死。
  int get maxSection {
    if (details.isEmpty) return 12;
    return details
        .map((TimeDetail d) => d.section)
        .reduce((int a, int b) => a > b ? a : b);
  }

  /// 「今天」（注入时钟，便于测试与跨天刷新）。界面不得自己调 DateTime.now()，
  /// 否则今天高亮与摘要条会跟模型用两套时间。
  DateTime get today => _clock();

  int get totalWeeks => semester?.totalWeeks ?? 0;

  /// 第 1 周时 ‹ 禁用、最后一周时 › 禁用（细化 §2.6:125：不给空周）。
  bool get canPrev => week > 1;
  bool get canNext => week < totalWeeks;

  /// 今天是否落在学期内（决定「今天」高亮与今日摘要条是否出现）。
  bool get todayInSemester => semester?.weekOf(_clock()) != null;

  int get todayWeek => semester?.weekOf(_clock()) ?? 0;

  DateTime get weekMonday =>
      semester?.mondayOfWeek(week) ?? Semester.mondayOf(_clock());

  /// 当前周第 [weekday]（1~7，ISO）对应的日期。
  DateTime dateOf(int weekday) => weekMonday.add(Duration(days: weekday - 1));

  /// 加载学期 + 作息 + 当前周课程。
  Future<void> load() async {
    try {
      semester = await _semesters.activeSemester();
      details = await _semesters.loadDefaultDetails();
      // 打开就定位到今天那一周（界面 §4.1：周视图默认定位到本周）；学期外回落到第 1 周。
      week = (semester?.weekOf(_clock()) ?? 1).clamp(1, totalWeeks == 0 ? 1 : totalWeeks);
      await _reloadWeek();
      error = null;
    } catch (e) {
      error = '$e';
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> selectWeek(int target) async {
    final int upper = totalWeeks == 0 ? 1 : totalWeeks;
    final int clamped = target.clamp(1, upper);
    if (clamped == week && weekCourses.isNotEmpty) return;
    week = clamped;
    await _reloadWeek();
    notifyListeners();
  }

  Future<void> prevWeek() =>
      canPrev ? selectWeek(week - 1) : Future<void>.value();

  Future<void> nextWeek() =>
      canNext ? selectWeek(week + 1) : Future<void>.value();

  /// 回到今天所在的那一周（[今天] 按钮）。
  Future<void> goToday() =>
      todayInSemester ? selectWeek(todayWeek) : Future<void>.value();

  void toggleWeekend() {
    showWeekend = !showWeekend;
    notifyListeners();
  }

  /// 当前周第 [weekday] 天的课程（查询已按周次过滤，这里只分天）。
  List<Course> coursesOn(int weekday) => weekCourses
      .where((Course c) => c.weekday == weekday && c.isOn(week))
      .toList(growable: false);

  /// 当天的同槽分组（渲染堆叠用）。
  List<OverlapGroup> groupsOn(int weekday) =>
      groupByOverlap(coursesOn(weekday));

  /// 节次不在作息表里的课 → 底部「未排时间」收纳区（§3.4，绝不静默截断）。
  List<Course> get unscheduled {
    final SectionLayout l = layout;
    return weekCourses
        .where((Course c) =>
            c.isOn(week) &&
            l.missingSections(c.startSection, c.endSection).isNotEmpty)
        .toList(growable: false);
  }

  /// 今日摘要条的数据（学期外为空，细化 §2.8:140）。
  List<Course> get todayCourses {
    if (!todayInSemester) return const <Course>[];
    return coursesOn(_clock().weekday);
  }

  /// 显示的天数：桌面恒 7 列；移动默认周一~周五，可展开周末。
  List<int> visibleDays({required bool isMobile}) =>
      (!isMobile || showWeekend)
          ? const <int>[1, 2, 3, 4, 5, 6, 7]
          : const <int>[1, 2, 3, 4, 5];

  Future<void> _reloadWeek() async {
    final Semester? s = semester;
    weekCourses = s == null
        ? const <Course>[]
        : await _courses.coursesOnWeek(week, semesterId: s.id);
  }
}

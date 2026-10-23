import 'package:flutter/foundation.dart';

import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_conflict.dart';
import 'package:qingdan/domain/course_freshness.dart';
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

/// 课表周视图的状态模型（F31 / F34 + M6-A A5/A8）。
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

  /// 本学期**全部**未删除课程。一次 `load()` 捞全，之后切周与相邻页都不再查库——
  /// 滑动切周要「手指一抬就看到下一页」，而 `findOnWeek` 本来就是「捞全 + `isOn`
  /// 过滤」，缓存整学期不多花一次查询，还省掉了每周一次往返。
  List<Course> allCourses = const <Course>[];

  /// 顶部「上次更新 / 导入时间」的读数（A8）。
  CourseFreshness freshness = const CourseFreshness();

  /// 当前显示的周次（1 起）。
  int week = 1;

  /// 移动端周末是否展开（细化 §2.1:64：默认折叠；桌面恒 7 列不看此值）。
  bool showWeekend = false;

  String? error;
  bool loaded = false;

  /// 最近一次成功 [load] 的模型时间（注入时钟）。重新进入页签时用它跟
  /// 「上次同步成功」比：同步发生在页签不在前台时，没人听得到状态流。
  DateTime? loadedAt;

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

  /// 第 [target] 周的周一。没有学期时按「本周一」推算，保证表头永远有日期。
  DateTime mondayOf(int target) => semester?.mondayOfWeek(target) ??
      Semester.mondayOf(_clock()).add(Duration(days: 7 * (target - 1)));

  DateTime get weekMonday => mondayOf(week);

  /// 当前周第 [weekday]（1~7，ISO）对应的日期。
  DateTime dateOf(int weekday) => dateInWeek(week, weekday);

  /// 第 [target] 周第 [weekday] 天的日期（滑动切周时相邻页各自要算自己的表头）。
  DateTime dateInWeek(int target, int weekday) =>
      mondayOf(target).add(Duration(days: weekday - 1));

  /// 当前周要上的课。
  List<Course> get weekCourses => coursesInWeek(week);

  List<Course> coursesInWeek(int target) =>
      <Course>[for (final Course c in allCourses) if (c.isOn(target)) c];

  /// 当前周第 [weekday] 天的课程（查询已按周次过滤，这里只分天）。
  List<Course> coursesOn(int weekday) => coursesOnDay(week, weekday);

  List<Course> coursesOnDay(int target, int weekday) => <Course>[
        for (final Course c in coursesInWeek(target))
          if (c.weekday == weekday) c
      ];

  /// 当天的同槽分组（渲染堆叠用）。
  List<OverlapGroup> groupsOn(int weekday) => groupsOnDay(week, weekday);

  List<OverlapGroup> groupsOnDay(int target, int weekday) =>
      groupByOverlap(coursesOnDay(target, weekday));

  /// 节次不在作息表里的课 → 底部「未排时间」收纳区（§3.4，绝不静默截断）。
  List<Course> get unscheduled => unscheduledInWeek(week);

  List<Course> unscheduledInWeek(int target) {
    final SectionLayout l = layout;
    return coursesInWeek(target)
        .where((Course c) =>
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

  /// 顶部那一行的文案；无数据返回 null（整行不渲染）。
  String? get freshnessLabel {
    final DateTime? at = freshness.at;
    if (at == null) return null;
    final String stamp = courseStamp(at);
    return switch (freshness.kind) {
      CourseFreshnessKind.import =>
        '$stamp 导入 · ${freshness.fileName ?? '课表文件'}',
      CourseFreshnessKind.edit => '$stamp 更新',
      CourseFreshnessKind.none => null,
    };
  }

  /// 导入读数**按当前学期取**：v6 给 `import_batches` 补了 `semester_id`，
  /// `latestBatch(semesterId)` 就是本学期最近一次（M6-D §八）。
  /// 这句 tooltip 以前写「不区分学期」，那是补列之前的老实话，现在留着就成了
  /// 假声明（2026-10-19 审计抓到）。
  String get freshnessTooltip => freshness.kind == CourseFreshnessKind.import
      ? '本学期最近一次导入 · 点此查看最近 10 次'
      : '本学期课程最后一次改动 · 点此查看最近导入';

  /// 加载学期 + 作息 + 整学期课程 + 新鲜度。
  Future<void> load() async {
    try {
      semester = await _semesters.activeSemester();
      // 节次读**当前学期自己**的那张作息表（M6-D 起建学期即从模板复制一份）。
      // 这里以前调 `loadDefaultDetails()`，那张是 `semester_id IS NULL` 的匿名
      // 老表：2026-10-19 真机库里两个学期各有 12 节、匿名表一条都没有，于是周
      // 视图永远说「作息表还是空的」、所有课程落进「未排时间」。老库（学期没有
      // 自己的作息行）由用例层回落到同一张匿名表，不会空也不会崩。
      details = await _semesters.loadDetailsForSemester(semester?.id);
      // 打开就定位到今天那一周（界面 §4.1：周视图默认定位到本周）；学期外回落到第 1 周。
      week = (semester?.weekOf(_clock()) ?? 1)
          .clamp(1, totalWeeks == 0 ? 1 : totalWeeks);
      await _reloadCourses();
      error = null;
    } catch (e) {
      error = '$e';
    }
    loaded = true;
    loadedAt = _clock();
    notifyListeners();
  }

  Future<void> selectWeek(int target) async {
    final int upper = totalWeeks == 0 ? 1 : totalWeeks;
    final int clamped = target.clamp(1, upper);
    if (clamped == week) return;
    week = clamped;
    notifyListeners();
  }

  Future<void> prevWeek() =>
      canPrev ? selectWeek(week - 1) : Future<void>.value();

  Future<void> nextWeek() =>
      canNext ? selectWeek(week + 1) : Future<void>.value();

  /// 切换当前学期（M6-D §7.1）：调用例层 `setActiveSemester` 后**必须重读**。
  ///
  /// 不重读的话，`semester` / `allCourses` / `week` 全是旧学期那一套，周视图会
  /// 继续显示上一个学期的课（面板只在首帧 load 一次，这是 S6-4 真机已经栽过的
  /// 同一个坑）。`is_active` 是设备本地列，用例层不记 op-log，所以切学期不会
  /// 惊动同步、也不会改到另一台设备的当前学期。
  Future<void> switchSemester(String id) async {
    await _semesters.setActiveSemester(id);
    await load();
  }

  /// 回到今天所在的那一周（[今天] 按钮）。
  Future<void> goToday() =>
      todayInSemester ? selectWeek(todayWeek) : Future<void>.value();

  /// 摘要条点击 = 定位到今天（细化 §2.8:140）。比 [goToday] 多做一件事：
  /// 今天落在周末而周末折叠着的话，先把周末展开——否则「今天」那一列根本
  /// 不在屏幕上，点摘要条等于没点（2026-10-18 模拟器：今天周日，摘要条写着
  /// 「今天没有课」，但周日那列被「收起周末」藏着）。
  Future<void> revealToday() async {
    if (!todayInSemester) return;
    if (today.weekday >= DateTime.saturday && !showWeekend) toggleWeekend();
    await selectWeek(todayWeek);
  }

  /// 一键校准（A5）：把第 [n] 周当作「本周」。
  ///
  /// 真正改的是 `semester.first_week_monday`——「今天是第几周」完全由它推出，
  /// 用户看到的「显示错了一周」根因就是这个日期当初填错了整整一周。
  ///
  /// 保存**只调一次 [SemesterUseCase.saveSemester]**：拆成
  /// rename → setTotalWeeks → setFirstWeek 三次写时，每次都拿同一份旧快照整行
  /// 写回，后一次盖掉前一次，最后只有最后一个字段生效（2026-10-18 用户报
  /// 「点了没反应」就是它）。
  ///
  /// 返回改好后的「开学第一周周一」，供界面回执；没有学期或周次非法返回 null。
  Future<DateTime?> calibrateThisWeekTo(int n) async {
    final Semester? s = semester;
    if (s == null || n < 1 || n > Semester.maxTotalWeeks) return null;
    final DateTime newMonday =
        Semester.mondayOf(_clock()).subtract(Duration(days: 7 * (n - 1)));
    await _semesters.saveSemester(
      s,
      name: s.name,
      firstWeekDate: newMonday,
      totalWeeks: s.totalWeeks,
    );
    await load();
    await goToday();
    return newMonday;
  }

  void toggleWeekend() {
    showWeekend = !showWeekend;
    notifyListeners();
  }

  Future<void> _reloadCourses() async {
    final Semester? s = semester;
    if (s == null) {
      allCourses = const <Course>[];
      freshness = const CourseFreshness();
      return;
    }
    allCourses = await _courses.activeCourses(semesterId: s.id);
    freshness = await _courses.freshness(s.id);
  }
}

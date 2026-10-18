// 课表周视图网格（细化 §2.1~§2.5）：把星期轴、节次轴、每日列组成一张可滚动的表。
//
// 布局全部来自 SectionLayout 与 groupByOverlap 两个纯函数，与导入预览共用同一套
// 分组规则；本文件只做装配，不含算法（算法在 lib/domain/，块渲染在 course_block.dart）。
//
// 同文件的 `CourseWeekPager` 是这张表的横向壳子（M6-A A5 滑动切周）。
import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_conflict.dart';
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'course_day_axis.dart';
import 'course_day_column.dart';

class CourseWeekGrid extends StatelessWidget {
  const CourseWeekGrid({
    super.key,
    required this.days,
    required this.layout,
    required this.week,
    required this.coursesOf,
    required this.dateOf,
    this.todayWeekday,
    this.isMobile = false,
    this.onBlockTap,
  });

  final List<int> days;
  final SectionLayout layout;

  /// 这一页是第几周：透传给日列，让「换周就把同槽块的组内索引清回第一条」
  /// 能看出来（细化 §2.4，2026-10-19）。
  final int week;
  final List<Course> Function(int weekday) coursesOf;
  final DateTime Function(int weekday) dateOf;

  /// 显示今天高亮的星期（1~7）；非当前周传 null（细化 §2.5:119）。
  final int? todayWeekday;
  final bool isMobile;
  final void Function(Course course, List<Course> sameSlot)? onBlockTap;

  double get _axisWidth =>
      isMobile ? AppDimens.courseAxisMobile : AppDimens.courseAxisDesktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CourseDayAxis(
          days: days,
          axisWidth: _axisWidth,
          dateOf: dateOf,
          todayWeekday: todayWeekday,
          isMobile: isMobile,
        ),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: layout.totalHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                      width: _axisWidth,
                      child: CourseSectionAxis(
                          layout: layout, isMobile: isMobile)),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final int weekday in days)
                          Expanded(
                            child: CourseDayColumn(
                              key: ValueKey<String>('day-$weekday'),
                              layout: layout,
                              week: week,
                              groups: groupByOverlap(coursesOf(weekday)),
                              isToday: weekday == todayWeekday,
                              isMobile: isMobile,
                              onBlockTap: onBlockTap,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 横向滑动切周（M6-A A5）：一学期 = 一本册子，第 1 周与最后一周**滑不动**
/// （`itemCount` 天然限制边界，不做无限循环，也不给空周，§2.6:125）。
///
/// **双向同步怎么防死循环**：两条边各自先比一次「值是不是已经相等」。
/// - 手指拖完 → [PageView.onPageChanged] 只在「这一页的周次 != 模型当前周」时
///   才回写模型；
/// - 点箭头 / 「今天」/ 网格选择器 → [didUpdateWidget] 只在「模型周次 !=
///   控制器页码」时才 `jumpToPage`，于是程序性回跳不会再把 onPageChanged
///   喂回模型，圈数停在 1。
class CourseWeekPager extends StatefulWidget {
  const CourseWeekPager({
    super.key,
    required this.totalWeeks,
    required this.week,
    required this.onWeekChanged,
    required this.pageBuilder,
  });

  final int totalWeeks;

  /// 模型当前周（1 起）——页码是 `week - 1`。
  final int week;
  final void Function(int week) onWeekChanged;
  final Widget Function(BuildContext context, int week) pageBuilder;

  @override
  State<CourseWeekPager> createState() => _CourseWeekPagerState();
}

class _CourseWeekPagerState extends State<CourseWeekPager> {
  late final PageController _controller = PageController(
      initialPage: (widget.week - 1).clamp(0, widget.totalWeeks - 1));

  @override
  void didUpdateWidget(covariant CourseWeekPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_controller.hasClients) return;
    final int target = widget.week - 1;
    final double? page = _controller.page;
    if (page != null && page.round() == target) return; // 相等就不跳
    _controller.jumpToPage(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      key: const ValueKey<String>('week-pager'),
      controller: _controller,
      itemCount: widget.totalWeeks,
      onPageChanged: (int index) {
        final int week = index + 1;
        if (week != widget.week) widget.onWeekChanged(week);
      },
      itemBuilder: (BuildContext ctx, int index) =>
          widget.pageBuilder(ctx, index + 1),
    );
  }
}

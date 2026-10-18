// 课表周视图网格（细化 §2.1~§2.5）：把星期轴、节次轴、每日列组成一张可滚动的表。
//
// 布局全部来自 SectionLayout 与 groupByOverlap 两个纯函数，与导入预览共用同一套
// 分组规则；本文件只做装配，不含算法（算法在 lib/domain/，块渲染在 course_block.dart）。

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
    required this.coursesOf,
    required this.dateOf,
    this.todayWeekday,
    this.isMobile = false,
    this.onBlockTap,
  });

  final List<int> days;
  final SectionLayout layout;
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

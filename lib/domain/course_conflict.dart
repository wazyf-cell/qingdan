// 同槽分组：渲染层的「单块 + 循环角标」与导入层「时间重叠」警告共用（§3.4 / §4.1）。

import 'course.dart';

/// 一组互相占用节次的课程。
///
/// 渲染形态（细化 §2.4）：**每门课保留自己真实的节次跨度**，组内共享一个「当前
/// 索引」，只显示被选中的那一条，其余隐藏；组内 ≥2 门时右下角挂循环角标，点它切
/// 下一条。默认索引 0 = 起始节次最早、同起始节次按课名（与旧堆叠的先后次序一致）。
///
/// **2026-10-19 用户裁决：改为单块 + 循环角标，推翻原「垂直堆叠、不做切换」定案**
/// （旧形态是把组的跨度按条数均分，均分后不足 28dp 再降级成「首二字 + +N」，
/// 两节课挤两门课时课名被压得看不清）。
class OverlapGroup {
  OverlapGroup(List<Course> members)
      : courses = <Course>[...members]..sort((Course a, Course b) {
          final int byStart = a.startSection.compareTo(b.startSection);
          // 同一起始节次再按课名：这样「默认显示第一条」在两处入口（周视图 /
          // 导入预览）都确定，不会跟着 DAO 返回顺序漂（2026-10-19 定案）。
          // 排序在副本上做，绝不原地改调用方传进来的列表。
          return byStart != 0 ? byStart : a.name.compareTo(b.name);
        });

  final List<Course> courses;

  /// 组的稳定标识：成员 id 排序后拼接。视图里「当前显示第几条」拿它当键。
  ///
  /// **不能用 `courses.hashCode`**：分组每帧重算（`CourseWeekGrid.build` 里直接
  /// 调 [groupByOverlap]），每次都是新对象、新的 identity 哈希，键一漂，用户刚
  /// 切到的那条会在任意一次重绘后莫名回到第一条。
  String get groupKey =>
      (<String>[for (final Course c in courses) c.id]..sort()).join('|');
}

/// 把同一天的课程按「节次区间相交」分组（区间图连通分量，传递性合并）。
///
/// 调用方决定传什么集合：周视图传**已按当前周过滤**的课（所以 A 上 1-8 周、
/// B 上 9-16 周这种「槽位重叠但本周只上一门」的情况天然不成组，渲染层不需要
/// 再看周次，2026-10-19 定案），导入预览传全部课（§3.4 的重叠提示不看周次交集，
/// 只看槽位）。
List<OverlapGroup> groupByOverlap(List<Course> sameDayCourses) {
  final List<Course> sorted = <Course>[...sameDayCourses]
    ..sort((Course a, Course b) => a.startSection.compareTo(b.startSection));

  final List<OverlapGroup> groups = <OverlapGroup>[];
  List<Course> current = <Course>[];
  int currentEnd = 0;
  for (final Course c in sorted) {
    if (current.isNotEmpty && c.startSection > currentEnd) {
      groups.add(OverlapGroup(current));
      current = <Course>[];
    }
    current.add(c);
    if (c.endSection > currentEnd) currentEnd = c.endSection;
  }
  if (current.isNotEmpty) groups.add(OverlapGroup(current));
  return groups;
}

/// 两条课是否占用同一节次（不看周次）。
bool sectionsOverlap(Course a, Course b) =>
    a.startSection <= b.endSection && b.startSection <= a.endSection;

/// 与 [target] 槽位冲突的其它课程（导入预览写警告时要点名冲突对象，
/// §4.3 规则 7：不写「存在冲突」这种废话）。
List<Course> conflictingWith(Course target, List<Course> others) => others
    .where((Course c) =>
        c.id != target.id && c.weekday == target.weekday && sectionsOverlap(c, target))
    .toList(growable: false);

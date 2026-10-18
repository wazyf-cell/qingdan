// 同槽分组：渲染层堆叠与导入层「时间重叠」警告共用（§3.4 / §4.1）。

import 'course.dart';

/// 一组互相占用节次的课程（渲染时**垂直堆叠**，不做 TAB 切换、不做叠加阴影）。
class OverlapGroup {
  OverlapGroup(List<Course> members)
      : courses = <Course>[
          ...members..sort((Course a, Course b) => a.startSection.compareTo(b.startSection)),
        ];

  final List<Course> courses;

  int get spanStart =>
      courses.map((Course c) => c.startSection).reduce((int a, int b) => a < b ? a : b);

  int get spanEnd =>
      courses.map((Course c) => c.endSection).reduce((int a, int b) => a > b ? a : b);

  /// 组占了多少节（含两端）。
  int get spanSections => spanEnd - spanStart + 1;

  /// 每条课分到的**节数份额**：组的跨度按条数均分（跨 2 节有 2 条 → 各 1 节；
  /// 2 节 3 条 → 各 2/3 节）。
  double get shareSections => spanSections / courses.length;

  /// 挤不下的判定：组高均分到每条后**不足 28dp** 就降级（细化 §2.4:107）。
  ///
  /// 降级形态：整组只画一个容器块（底色取第一条课的调色板色），内容是第一条课的
  /// 课名首二字 + 右上角「+N」角标（细化 §2.4:108-109）。
  bool needsCompactFor(double groupHeightDp, {double minBlockDp = 28}) =>
      courses.length > 1 && groupHeightDp / courses.length < minBlockDp;

  /// 「+N」角标里的 N：容器块已显示第一条，其余都折算进角标。
  int get badgeCount => courses.length - 1;

  /// 第 [index] 条课在组内的偏移（单位：节）。
  double offsetSectionsOf(int index) => index * shareSections;
}

/// 把同一天的课程按「节次区间相交」分组（区间图连通分量，传递性合并）。
///
/// 调用方决定传什么集合：周视图传**已按当前周过滤**的课，导入预览传全部课
/// （§3.4 的重叠提示不看周次交集，只看槽位）。
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

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_conflict.dart';

/// 同槽分组与堆叠份额测试（§3.4 / 细化 §2.4:103-111）。
void main() {
  Course course({
    required String id,
    int weekday = 2,
    int start = 3,
    int end = 4,
    List<int> weeks = const <int>[1, 2, 3],
  }) =>
      Course(
        id: id,
        uid: 'uid_$id',
        name: '课程$id',
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: weeks,
      );

  test('互不相交的三条 → 三个组，每组份额就是自己的跨度', () {
    final List<OverlapGroup> groups = groupByOverlap(<Course>[
      course(id: 'a', start: 1, end: 1),
      course(id: 'b', start: 3, end: 4),
      course(id: 'c', start: 6, end: 7),
    ]);
    expect(groups, hasLength(3));
    expect(groups[1].spanSections, 2);
    expect(groups[1].shareSections, closeTo(2, 1e-9));
  });

  test('跨 2 节有 2 条重叠 → 各占 1 节高（§4.1 堆叠规则）', () {
    final List<OverlapGroup> groups = groupByOverlap(<Course>[
      course(id: 'a', start: 3, end: 4),
      course(id: 'b', start: 3, end: 4),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.spanStart, 3);
    expect(groups.single.spanEnd, 4);
    expect(groups.single.shareSections, closeTo(1, 1e-9));
    expect(groups.single.offsetSectionsOf(1), closeTo(1, 1e-9));
  });

  test('2 节挤 3 条 → 每条 2/3 节', () {
    final OverlapGroup g = groupByOverlap(<Course>[
      course(id: 'a'),
      course(id: 'b'),
      course(id: 'c'),
    ]).single;
    expect(g.shareSections, closeTo(2 / 3, 1e-9));
  });

  test('重叠具有传递性：1-2 / 2-3 / 3-4 合成一组，跨度 1-4', () {
    final List<OverlapGroup> groups = groupByOverlap(<Course>[
      course(id: 'a', start: 1, end: 2),
      course(id: 'b', start: 2, end: 3),
      course(id: 'c', start: 3, end: 4),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.spanStart, 1);
    expect(groups.single.spanEnd, 4);
    expect(groups.single.courses.map((Course c) => c.id).toList(),
        <String>['a', 'b', 'c']);
  });

  test('不同星期不参与分组（调用方按天传入）', () {
    expect(groupByOverlap(<Course>[
      course(id: 'a', weekday: 1),
      course(id: 'b', weekday: 1),
    ]).single.courses, hasLength(2));
  });

  test('降级阈值按**均分后的实际高度**判，不看条数（细化 §2.4:107）', () {
    final OverlapGroup fourInOne = groupByOverlap(<Course>[
      course(id: 'a', start: 1, end: 1),
      course(id: 'b', start: 1, end: 1),
      course(id: 'c', start: 1, end: 1),
      course(id: 'd', start: 1, end: 1),
    ]).single;
    // 一节 45 分钟 = 40.5dp，4 条均分 ≈ 10.1dp < 28 → 降级。
    expect(fourInOne.needsCompactFor(40.5), isTrue);
    expect(fourInOne.badgeCount, 3);
    // 2 条均分 20.25dp 仍 < 28 → 也降级；单条不参与降级。
    final OverlapGroup two = groupByOverlap(<Course>[
      course(id: 'a', start: 1, end: 1),
      course(id: 'b', start: 1, end: 1),
    ]).single;
    expect(two.needsCompactFor(40.5), isTrue);
    final OverlapGroup one =
        groupByOverlap(<Course>[course(id: 'a', start: 1, end: 2)]).single;
    expect(one.needsCompactFor(81), isFalse);
    expect(one.needsCompactFor(10), isFalse, reason: '单条没有「+N」可折');
  });

  test('冲突对象点名：同星期同槽才算，且不含自己（§4.3 规则 7）', () {
    final Course target = course(id: 'a', start: 3, end: 4);
    final List<Course> others = <Course>[
      target,
      course(id: 'b', start: 3, end: 4), // 冲突
      course(id: 'c', start: 5, end: 6), // 不冲突
      course(id: 'd', weekday: 3, start: 3, end: 4), // 不同天，不算
    ];
    expect(conflictingWith(target, others).map((Course c) => c.id).toList(),
        <String>['b']);
  });

  test('sectionsOverlap 只看节次，不看周次（预览按槽位提示）', () {
    expect(
        sectionsOverlap(
            course(id: 'a', start: 1, end: 2, weeks: <int>[1]),
            course(id: 'b', start: 2, end: 3, weeks: <int>[9])),
        isTrue);
    expect(
        sectionsOverlap(
            course(id: 'a', start: 1, end: 2), course(id: 'b', start: 3, end: 4)),
        isFalse);
  });
}

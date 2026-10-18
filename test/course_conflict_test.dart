import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_conflict.dart';

/// 同槽分组测试（§3.4 / 细化 §2.4）。
///
/// ★ 2026-10-19 改版：本文件原来钉的是**均分堆叠 + 挤不下降级成「+N」**那套语义
/// （`shareSections` / `offsetSectionsOf` / `needsCompactFor` / `badgeCount`）。
/// 用户裁决把渲染换成「单块 + 循环角标」，四个成员随之删除，同一条用例改写成新
/// 语义的断言；每条改写处都注明「原来钉的是什么、为什么换掉」。
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

  test('互不相交的三条 → 三个组，每组各一条（原断言：每组份额 == 自己的跨度）',
      () {
    final List<OverlapGroup> groups = groupByOverlap(<Course>[
      course(id: 'a', start: 1, end: 1),
      course(id: 'b', start: 3, end: 4),
      course(id: 'c', start: 6, end: 7),
    ]);
    expect(groups, hasLength(3));
    // 原来这里还钉了一句 `groups[1].spanSections == 2`（并集跨度）。那个 getter
    // 生产代码零引用，随死 API 一起删了；「哪门课落进哪一组、一条都不丢」本来就
    // 由下面两行钉住（keys 认组内成员，条数认没丢人），覆盖没打折。
    // 均分份额没了，但「一条都不丢」这件事改由条数来钉：单条就是一组一条。
    expect(groups.map((OverlapGroup g) => g.courses.length), <int>[1, 1, 1]);
    expect(groups.map((OverlapGroup g) => g.groupKey), <String>['a', 'b', 'c']);
  });

  test('跨 2 节有 2 条重叠 → 合成一组，两条各自保留整跨度'
      '（原断言：shareSections==1 且 offsetSectionsOf(1)==1，即第二条往下挪一节）', () {
    final List<OverlapGroup> groups = groupByOverlap(<Course>[
      course(id: 'a', start: 3, end: 4),
      course(id: 'b', start: 3, end: 4),
    ]);
    expect(groups, hasLength(1));
    // 这里原来钉 `spanStart==3 / spanEnd==4`：两条本来就是 3-4，并集跟成员自己的
    // 跨度一模一样，删掉不丢信息——合成一组由上一行钉，保留整跨度由下一行钉。
    // 新语义里没有任何一条被压成半节：分组不改写成员自己的节次。
    expect(groups.single.courses.map((Course c) => '${c.startSection}-${c.endSection}').toSet(),
        <String>{'3-4'},
        reason: '各画各的真实跨度，不再均分');
  });

  test('2 节挤 3 条 → 组里有 3 条可切（原断言：每条 2/3 节）', () {
    final OverlapGroup g = groupByOverlap(<Course>[
      course(id: 'a'),
      course(id: 'b'),
      course(id: 'c'),
    ]).single;
    expect(g.courses, hasLength(3));
    // 循环角标的「还有几门」= 条数减一（原 badgeCount 的同一条算式，
    // 现在只用于文案，不再决定画不画降级块）。
    expect(g.courses.length - 1, 2);
  });

  test('重叠具有传递性：1-2 / 2-3 / 3-4 合成一组，按起始节次排', () {
    final List<OverlapGroup> groups = groupByOverlap(<Course>[
      course(id: 'a', start: 1, end: 2),
      course(id: 'b', start: 2, end: 3),
      course(id: 'c', start: 3, end: 4),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.courses.map((Course c) => c.id).toList(),
        <String>['a', 'b', 'c']);
    // 原来这里钉 `spanStart==1 / spanEnd==4`（并集跨度）：那两个 getter 生产代码
    // 零引用，删了。传递性合并这件事本来就靠上面两行——**三条不同跨度的成员进了
    // 同一组**，并集 1-4 是它们的必然结果，这里把成员跨度集合显式写出来当证据。
    expect(groups.single.courses.map((Course c) => '${c.startSection}-${c.endSection}').toSet(),
        <String>{'1-2', '2-3', '3-4'},
        reason: '首尾相接的三条并到一组，覆盖 1~4 节');
    // 组的并集跨度 1-4 只描述组；渲染用的是每条自己的跨度，
    // 所以这里 4 != 2（原 shareSections 会把它摊成每人 4/3 节）。
    expect(groups.single.courses.map((Course c) => c.endSection - c.startSection + 1),
        <int>[2, 2, 2]);
  });

  test('不同星期不参与分组（调用方按天传入）', () {
    expect(groupByOverlap(<Course>[
      course(id: 'a', weekday: 1),
      course(id: 'b', weekday: 1),
    ]).single.courses, hasLength(2));
  });

  test('默认第一条 = 起始节次最早，同起始节次按课名（Q6）', () {
    final OverlapGroup g = groupByOverlap(<Course>[
      course(id: 'late', start: 2, end: 6),
      course(id: 'b', start: 1, end: 2),
      course(id: 'a', start: 1, end: 3),
    ]).single;
    expect(g.courses.map((Course c) => c.id).toList(), <String>['a', 'b', 'late'],
        reason: '同为第 1 节起的，课名「课程a」<「课程b」，顺序必须确定不漂');
  });

  test('groupKey 认成员集合不认对象：换一批新实例键不变', () {
    // 视图里「当前显示第几条」就拿它当键。原来用 List.hashCode 会漂——
    // 分组每帧重算，每次都是新对象，用户刚切到的那条会在任意一次重绘后弹回第一条。
    final List<Course> first = <Course>[course(id: 'a'), course(id: 'b')];
    final List<Course> again = <Course>[course(id: 'b'), course(id: 'a')];
    expect(groupByOverlap(first).single.groupKey,
        groupByOverlap(again).single.groupKey);
    expect(groupByOverlap(first).single.groupKey, 'a|b');
  });

  test('≥2 门才算有得可切（原断言：按均分后的实际高度判要不要降级成「+N」）', () {
    // 28dp 阈值随堆叠一起废掉：现在挤不挤都不再改变「画几条」，只显示其中一条，
    // 剩下的靠角标切。所以「有几门」是唯一的判据，与像素高度无关。
    final OverlapGroup fourInOne = groupByOverlap(<Course>[
      course(id: 'a', start: 1, end: 1),
      course(id: 'b', start: 1, end: 1),
      course(id: 'c', start: 1, end: 1),
      course(id: 'd', start: 1, end: 1),
    ]).single;
    expect(fourInOne.courses.length, 4);
    final OverlapGroup two = groupByOverlap(<Course>[
      course(id: 'a', start: 1, end: 1),
      course(id: 'b', start: 1, end: 1),
    ]).single;
    expect(two.courses.length, 2);
    final OverlapGroup one =
        groupByOverlap(<Course>[course(id: 'a', start: 1, end: 2)]).single;
    expect(one.courses.length, 1, reason: '单条没有可切的对象，角标也不该画');
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

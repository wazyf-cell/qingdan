import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/domain/time_table.dart';

/// 节次 → 像素的纯函数测试（细化 §2.2:68-80，数值逐条对着设计稿算）。
void main() {
  TimeDetail d(int section, int start, int end) => TimeDetail(
      id: 'd$section',
      timetableId: 't1',
      section: section,
      startMinutes: start,
      endMinutes: end);

  // 第 1 节 08:00-08:45，课间 10 分钟，第 2 节 08:55-09:40，
  // 然后 90 分钟大空档（午休），第 3 节 11:10-11:55。
  List<TimeDetail> normalDay() => <TimeDetail>[
        d(1, 480, 525),
        d(2, 535, 580),
        d(3, 670, 715),
      ];

  test('节高 = 时长 × 0.9；首节前有 8dp 边距（映射不从 00:00 开始）', () {
    final SectionLayout l = layoutSections(<TimeDetail>[d(1, 480, 525)]);
    expect(l.slots.single.top, kGridEdgePaddingDp);
    expect(l.slots.single.height, closeTo(40.5, 1e-9));
    expect(l.totalHeight, closeTo(8 + 40.5 + 8, 1e-9));
  });

  test('空档分两段：g<=15 按比例，g>15 才压缩到 14~24', () {
    expect(gapHeightOf(10), closeTo(9, 1e-9)); // 10 分钟课间按比例，不被抬到 14
    expect(gapHeightOf(15), closeTo(13.5, 1e-9));
    expect(gapHeightOf(16), closeTo(14.4, 1e-9));
    expect(gapHeightOf(90), closeTo(24, 1e-9)); // 90 分钟午休压到上限
    expect(gapHeightOf(300), closeTo(24, 1e-9));
  });

  test('三节一天的完整排布：top 逐节累加，总高含末节后 8dp', () {
    final SectionLayout l = layoutSections(normalDay());
    expect(l.slots[0].top, closeTo(8, 1e-9));
    expect(l.slots[1].top, closeTo(8 + 40.5 + 9, 1e-9)); // 课间按比例
    expect(l.slots[2].top, closeTo(8 + 40.5 + 9 + 40.5 + 24, 1e-9)); // 午休压缩
    expect(l.totalHeight, closeTo(8 + 40.5 + 9 + 40.5 + 24 + 40.5 + 8, 1e-9));
  });

  test('yOf 在节内线性、在空档按压缩后的比例插值', () {
    final SectionLayout l = layoutSections(normalDay());
    expect(l.yOf(480), closeTo(8, 1e-9));
    expect(l.yOf(525), closeTo(48.5, 1e-9));
    expect(l.yOf(530), closeTo(53, 1e-9)); // 10 分钟空档的中点 → 48.5 + 4.5
    expect(l.yOf(625), closeTo(110, 1e-9)); // 90 分钟午休的中点 → 98 + 12
    expect(l.yOf(715), closeTo(162.5, 1e-9));
  });

  test('yOf 越界不外推（早于第一节取顶，晚于最后一节取底）', () {
    final SectionLayout l = layoutSections(normalDay());
    expect(l.yOf(0), closeTo(8, 1e-9));
    expect(l.yOf(479), closeTo(8, 1e-9));
    expect(l.yOf(2000), closeTo(162.5, 1e-9));
  });

  test('rectFor 每块相对槽位上下各缩 1dp（细化 §2.2:78）', () {
    final SectionLayout l = layoutSections(normalDay());
    final ({double top, double height}) one = l.rectFor(1, 1)!;
    expect(one.top, closeTo(9, 1e-9));
    expect(one.height, closeTo(48.5 - 1 - 9, 1e-9)); // yOf(525)-1 - (yOf(480)+1)
    final ({double top, double height}) span = l.rectFor(1, 2)!;
    expect(span.top, closeTo(9, 1e-9));
    expect(span.height, closeTo(98 - 1 - 9, 1e-9));
  });

  test('允许跳号：缺的节次没有槽，且**不静默截断**（§3.4）', () {
    final SectionLayout l =
        layoutSections(<TimeDetail>[d(1, 480, 525), d(3, 590, 635)]);
    expect(l.slot(2), isNull);
    expect(l.missingSections(1, 3), <int>[2]);
    expect(l.rectFor(1, 3), isNull, reason: '缺节次时不能画一个假装完整的块');
    expect(l.rectFor(1, 1), isNotNull);
    expect(l.missingSections(4, 4), <int>[4]);
  });

  test('输入乱序也按节次排布', () {
    final SectionLayout l = layoutSections(
        <TimeDetail>[d(3, 670, 715), d(1, 480, 525), d(2, 535, 580)]);
    expect(l.slots.map((SectionSlot s) => s.section).toList(), <int>[1, 2, 3]);
    expect(l.slots[0].top, lessThan(l.slots[1].top));
  });

  test('timeOf 给出该节起止分钟，缺节次返回 null', () {
    final SectionLayout l = layoutSections(normalDay());
    expect(l.timeOf(2)!.startMinutes, 535);
    expect(l.timeOf(2)!.endMinutes, 580);
    expect(l.timeOf(9), isNull);
  });

  test('空作息表不炸：总高 0，任何节次都算缺', () {
    final SectionLayout l = layoutSections(<TimeDetail>[]);
    expect(l.slots, isEmpty);
    expect(l.totalHeight, 0);
    expect(l.yOf(480), 0);
    expect(l.missingSections(1, 1), <int>[1]);
  });

  test('parseMinutes 与 formatMinutes 成对，非法格式返回 null', () {
    expect(parseMinutes('08:00'), 480);
    expect(parseMinutes('8:05'), 485);
    expect(parseMinutes('19:30'), 1170);
    expect(parseMinutes(formatMinutes(525)), 525);
    expect(parseMinutes('8:0'), isNull);
    expect(parseMinutes('0800'), isNull);
    expect(parseMinutes('24:00'), isNull);
    expect(parseMinutes('12:60'), isNull);
    expect(parseMinutes(''), isNull);
  });

  test('formatMinutes 补零', () {
    expect(formatMinutes(480), '08:00');
    expect(formatMinutes(57), '00:57');
    expect(formatMinutes(1170), '19:30');
    expect(formatMinutes(0), '00:00');
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/time_table.dart';

/// M6-A1 领域层闸门（数据损坏级）：24 时上限、一天节数上限、顺移越界体检。
///
/// 旧代码三条都没有：`validateTimeDetails` 只查 `end>start` 与升序不重叠，
/// `shiftSectionsAfter` 平移无天花板 → 某节能被存成 1475 分钟（显示 `24:35`），
/// 而 `parseMinutes('24:35')` 因 h>23 恒返回 null，那一格从此**永远改不回来**。
void main() {
  TimeDetail d(int section, int start, int end) => TimeDetail(
      id: 'd$section',
      timetableId: 't1',
      section: section,
      startMinutes: start,
      endMinutes: end);

  /// 07:00 起、40 分钟/节、课间 5：排到 21 节也仍在 23:59 之内，
  /// 这样「节数」与「时刻」两条闸能被分别验证，不互相遮掩。
  List<TimeDetail> day(int count) => generateTimeDetails(
      timetableId: 't1',
      firstStartMinutes: 420,
      lessonMinutes: 40,
      breakMinutes: 5,
      sectionCount: count);

  group('validateTimeDetails 的时刻上限', () {
    test('结束 1475（24:35）被拒（旧版没有这条，脏数据能进库）', () {
      final String? e =
          validateTimeDetails(<TimeDetail>[d(1, 420, 460), d(2, 465, 1475)]);
      expect(e, isNotNull);
      expect(e, contains('超出 00:00–23:59'));
      expect(e, contains('24:35'), reason: '错误串要带换算结果，用户才知道是哪里');
      expect(e, contains('第 2 节'));
    });

    test('开始时间为负同样被拒', () {
      expect(validateTimeDetails(<TimeDetail>[d(1, -5, 460)]),
          contains('超出 00:00–23:59'));
    });

    test('23:59（1439）是合法上界，正好通过', () {
      expect(validateTimeDetails(<TimeDetail>[d(1, 420, kMaxMinuteOfDay)]),
          isNull);
    });

    test('1440（24:00）不合法——上限是当日分钟数，不是「大于 24 时」', () {
      expect(validateTimeDetails(<TimeDetail>[d(1, 420, 1440)]),
          contains('超出 00:00–23:59'));
    });
  });

  group('validateTimeDetails 的节数上限', () {
    test('21 节被拒（需求原文：不能无限加）', () {
      expect(validateTimeDetails(day(21)), contains('最多 20 节'));
    });

    test('20 节合法数据通过：上限含 20，不是 19', () {
      expect(validateTimeDetails(day(20)), isNull);
    });
  });

  test('既有校验一条没丢：节次<1 / 结束不晚于开始 / 时间重叠', () {
    expect(validateTimeDetails(<TimeDetail>[d(0, 420, 460)]), contains('1 开始'));
    expect(validateTimeDetails(<TimeDetail>[d(1, 420, 420)]), contains('晚于'));
    expect(validateTimeDetails(<TimeDetail>[d(1, 420, 470), d(2, 465, 505)]),
        contains('重叠'));
    expect(validateTimeDetails(<TimeDetail>[d(1, 420, 460), d(2, 460, 500)]),
        isNull,
        reason: '零课间仍然允许');
  });

  group('firstOutOfRange：载入既有数据时的体检', () {
    test('干净数据与空表返回 null', () {
      expect(firstOutOfRange(day(12)), isNull);
      expect(firstOutOfRange(<TimeDetail>[]), isNull);
    });

    test('只报第一个越界节次（供 UI 标红与复述）', () {
      final String? e = firstOutOfRange(<TimeDetail>[
        d(1, 420, 460),
        d(2, 1440, 1470),
        d(3, 1500, 1560),
      ]);
      expect(e, contains('第 2 节'));
      expect(e, isNot(contains('第 3 节')));
    });

    test('shiftSectionsAfter 平移越界会被抓到（旧版无天花板）', () {
      final List<TimeDetail> pushed = shiftSectionsAfter(day(20), 1, 140);
      expect(firstOutOfRange(pushed), contains('超出 00:00–23:59'));
      expect(validateTimeDetails(pushed), contains('超出 00:00–23:59'));
      // 同一张表只往后挪 60 分钟仍在范围内：证明判据不是「一律拒绝平移」。
      expect(firstOutOfRange(shiftSectionsAfter(day(20), 1, 60)), isNull);
    });

    test('平移不会把第一节自己推到越界（它不参与顺移，只被直接改）', () {
      final List<TimeDetail> pushed = shiftSectionsAfter(day(20), 1, 140);
      expect(pushed.first.startMinutes, 420);
      expect(pushed.first.endMinutes, 460);
    });
  });

  group('parseMinutes 是这道闸的另一半', () {
    test('26:00 / 12:60 / 8:5 / abc 全不合法，08:05 == 485', () {
      expect(parseMinutes('26:00'), isNull);
      expect(parseMinutes('12:60'), isNull);
      expect(parseMinutes('8:5'), isNull);
      expect(parseMinutes('abc'), isNull);
      expect(parseMinutes(''), isNull);
      expect(parseMinutes('08:05'), 485);
    });

    test('合法输入的上界正好落在 kMaxMinuteOfDay', () {
      expect(parseMinutes('23:59'), kMaxMinuteOfDay);
      expect(parseMinutes('24:00'), isNull);
    });

    test('越界值显示成 24:35 后就再也解析不出来（这就是「永远改不回来」）', () {
      expect(kMaxMinuteOfDay, 1439);
      expect(formatMinutes(1475), '24:35');
      expect(parseMinutes(formatMinutes(1475)), isNull);
    });
  });

  test('minuteOutOfRange 的边界：0 与 1439 在内，-1 与 1440 在外', () {
    expect(minuteOutOfRange(0), isFalse);
    expect(minuteOutOfRange(1439), isFalse);
    expect(minuteOutOfRange(-1), isTrue);
    expect(minuteOutOfRange(1440), isTrue);
  });
}

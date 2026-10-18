import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/due_date_parser.dart';

void main() {
  // 固定基准时刻：2026-09-29（周二）14:30。
  final DateTime now = DateTime(2026, 9, 29, 14, 30);

  DateTime dueOf(ParsedDue p) => p.due;

  group('相对日短语', () {
    test('今天（无时刻→默认 9 点）', () {
      final ParsedDue? p = parseDuePhrase('开会 今天', now);
      expect(p, isNotNull);
      expect(dueOf(p!), DateTime(2026, 9, 29, 9));
      expect(p.label, contains('今天'));
      expect(p.hasExplicitTime, isFalse);
    });

    test('明天', () {
      final ParsedDue? p = parseDuePhrase('明天交报告', now);
      expect(dueOf(p!), DateTime(2026, 9, 30, 9));
      expect(p.label, '明天(9/30)');
    });

    test('后天 / 大后天', () {
      expect(
          dueOf(parseDuePhrase('后天', now)!), DateTime(2026, 10, 1, 9));
      expect(
          dueOf(parseDuePhrase('大后天', now)!), DateTime(2026, 10, 2, 9));
    });

    test('明早 → 明天 8 点；今晚 → 今天 20 点', () {
      expect(dueOf(parseDuePhrase('明早取快递', now)!),
          DateTime(2026, 9, 30, 8));
      expect(dueOf(parseDuePhrase('今晚聚餐', now)!),
          DateTime(2026, 9, 29, 20));
    });
  });

  group('星期短语', () {
    test('周五 → 本周最近未来的周五（10/2）', () {
      final ParsedDue? p = parseDuePhrase('周五开会', now);
      expect(dueOf(p!), DateTime(2026, 10, 2, 9));
    });

    test('下周三 → 10/7', () {
      expect(dueOf(parseDuePhrase('下周三汇报', now)!),
          DateTime(2026, 10, 7, 9));
    });

    test('下下周一 → 10/12', () {
      expect(dueOf(parseDuePhrase('下下周一例会', now)!),
          DateTime(2026, 10, 12, 9));
    });

    test('今天命中的周X取今天（周二说「周二」）', () {
      expect(dueOf(parseDuePhrase('周二', now)!), DateTime(2026, 9, 29, 9));
    });
  });

  group('时刻短语', () {
    test('X点 / X点半', () {
      expect(dueOf(parseDuePhrase('明天15点', now)!),
          DateTime(2026, 9, 30, 15));
      expect(dueOf(parseDuePhrase('明天15点半', now)!),
          DateTime(2026, 9, 30, 15, 30));
    });

    test('上午X点 / 下午X点（+12）', () {
      expect(dueOf(parseDuePhrase('明天上午10点', now)!),
          DateTime(2026, 9, 30, 10));
      expect(dueOf(parseDuePhrase('明天下午3点', now)!),
          DateTime(2026, 9, 30, 15));
    });

    test('晚上X点 / 中午12点', () {
      expect(dueOf(parseDuePhrase('明天晚上8点', now)!),
          DateTime(2026, 9, 30, 20));
      expect(dueOf(parseDuePhrase('明天中午12点', now)!),
          DateTime(2026, 9, 30, 12));
    });

    test('H:mm', () {
      expect(dueOf(parseDuePhrase('明天 10:30', now)!),
          DateTime(2026, 9, 30, 10, 30));
    });

    test('显式时刻覆盖默认时刻', () {
      final ParsedDue? p = parseDuePhrase('明天18点跑步', now);
      expect(p!.due.hour, 18);
      expect(p.hasExplicitTime, isTrue);
    });
  });

  group('绝对日期', () {
    test('12月25日', () {
      expect(dueOf(parseDuePhrase('12月25日活动', now)!),
          DateTime(2026, 12, 25, 9));
    });

    test('10/5（M/D）', () {
      expect(dueOf(parseDuePhrase('10/5 交税', now)!),
          DateTime(2026, 10, 5, 9));
    });

    test('早于今天顺延一年（1月1日）', () {
      expect(dueOf(parseDuePhrase('1月1日', now)!),
          DateTime(2027, 1, 1, 9));
    });
  });

  group('剔除与落点', () {
    test('start/end 覆盖日期与时刻短语，剩余文本为标题', () {
      final ParsedDue? p = parseDuePhrase('明早10点交周报', now);
      expect(p, isNotNull);
      final String remaining = _cut('明早10点交周报', p!.start, p.end);
      expect(remaining.trim(), '交周报');
      expect(dueOf(p), DateTime(2026, 9, 30, 10));
    });

    test('无匹配 → null', () {
      expect(parseDuePhrase('买牛奶', now), isNull);
      expect(parseDuePhrase('', now), isNull);
      expect(parseDuePhrase('25点开会', now), isNull); // 无效时刻且无日期词。
    });
  });
}

/// 按 (start, end) 区间剔除片段（模拟 quick_add_field 的标题提取）。
String _cut(String input, int start, int end) {
  if (start < 0 || end <= start) return input;
  return input.substring(0, start) + input.substring(end);
}

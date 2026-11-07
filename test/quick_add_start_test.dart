import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/quick_add_parser.dart';

/// 2026-10-26 定案：快速添加支持 `开始` / `截止` 标记，裸短语仍按截止。
void main() {
  final DateTime now = DateTime(2026, 10, 26, 12);

  ParsedQuickAdd p(String input) {
    final ParsedQuickAdd? parsed = parseQuickAdd(input, now);
    expect(parsed, isNotNull, reason: input);
    return parsed!;
  }

  test('D1 今天7点开始', () {
    final ParsedQuickAdd q = p('今天7点开始 写作业');
    expect(q.start, DateTime(2026, 10, 26, 7));
    expect(q.due, isNull);
    expect(q.title, '写作业');
  });

  test('D2 明天开始 → 默认 09:00', () {
    final ParsedQuickAdd q = p('明天开始 写作业');
    expect(q.start, DateTime(2026, 10, 27, 9));
    expect(q.due, isNull);
    expect(q.title, '写作业');
  });

  test('D3 7点开始（无日期→今天）', () {
    final ParsedQuickAdd q = p('7点开始 写作业');
    expect(q.start, DateTime(2026, 10, 26, 7));
    expect(q.due, isNull);
    expect(q.title, '写作业');
  });

  test('D4 开始 + 截止', () {
    final ParsedQuickAdd q = p('今天7点开始 明天18点截止 写作业');
    expect(q.start, DateTime(2026, 10, 26, 7));
    expect(q.due, DateTime(2026, 10, 27, 18));
    expect(q.title, '写作业');
  });

  test('D5 开始 + 裸截止', () {
    final ParsedQuickAdd q = p('今天7点开始 明天18点 写作业');
    expect(q.start, DateTime(2026, 10, 26, 7));
    expect(q.due, DateTime(2026, 10, 27, 18));
    expect(q.title, '写作业');
  });

  test('D6 裸日期仍按截止（旧行为）', () {
    final ParsedQuickAdd q = p('今天7点 写作业');
    expect(q.start, isNull);
    expect(q.due, DateTime(2026, 10, 26, 7));
    expect(q.title, '写作业');
  });

  test('D7 截止标记', () {
    final ParsedQuickAdd q = p('明天18点截止 写作业');
    expect(q.start, isNull);
    expect(q.due, DateTime(2026, 10, 27, 18));
    expect(q.title, '写作业');
  });

  test('D8 标题里的「开始」不误判', () {
    expect(parseQuickAdd('开始写作业', now), isNull);
  });

  test('D9 今天开始（日期+标记）', () {
    final ParsedQuickAdd q = p('今天开始写作业');
    expect(q.start, DateTime(2026, 10, 26, 9));
    expect(q.due, isNull);
    expect(q.title, '写作业');
  });

  test('D10 从今天7点开始', () {
    final ParsedQuickAdd q = p('从今天7点开始 写作业');
    expect(q.start, DateTime(2026, 10, 26, 7));
    expect(q.title, '写作业');
  });

  test('D11 今晚8点开始', () {
    expect(p('今晚8点开始 复盘').start, DateTime(2026, 10, 26, 20));
  });

  test('D12 明早8点开始', () {
    expect(p('明早8点开始 跑步').start, DateTime(2026, 10, 27, 8));
  });

  test('D13 10/31 08:00开始', () {
    expect(p('10/31 08:00开始 考试').start, DateTime(2026, 10, 31, 8));
  });

  test('D14 下周一9点开始', () {
    expect(p('下周一9点开始 周报').start, DateTime(2026, 11, 2, 9));
  });

  test('D15 只有日期短语时标题为空', () {
    final ParsedQuickAdd q = p('今天7点开始 明天18点截止');
    expect(q.title, isEmpty);
    expect(q.start, DateTime(2026, 10, 26, 7));
    expect(q.due, DateTime(2026, 10, 27, 18));
  });

  test('D16 多余短语留在标题', () {
    final ParsedQuickAdd q = p('今天7点开始 明天18点截止 写作业 后天');
    expect(q.title, '写作业 后天');
  });

  test('D17 无日期的「截止」留在标题', () {
    final ParsedQuickAdd q = p('今天7点开始 截止 写作业');
    expect(q.start, DateTime(2026, 10, 26, 7));
    expect(q.due, isNull);
    expect(q.title, '截止 写作业');
  });

  test('D18 同一天的开始 + 截止', () {
    final ParsedQuickAdd q = p('今天7点开始 今天18点截止 写作业');
    expect(q.start, DateTime(2026, 10, 26, 7));
    expect(q.due, DateTime(2026, 10, 26, 18));
    expect(q.title, '写作业');
  });
}

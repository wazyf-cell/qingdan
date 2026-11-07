/// 快速添加的「开始 / 截止」标记语法（从 `due_date_parser.dart` 拆出，
/// 守住单文件 300 行红线）。
library;

import 'due_date_parser.dart';

/// 日期/时刻短语 + `开始`/`截止` 标记；`从` 一并吃掉（「从今天7点开始」）。
final RegExp _markedPattern = RegExp(
  '(?:从)?((?:$kDatePhraseSource)(?:\\s*(?:$kTimePhraseSource))?|'
  '(?:$kTimePhraseSource))'
  r'\s*(开始|截止)',
);

/// 快速添加的完整解析：可带一个 `开始` 和一个 `截止` 标记。
///
/// 规则（2026-10-26 定案）：
/// - 标记必须**紧跟**在日期/时刻短语后面；标题里的「开始/截止」不误判；
/// - 没有标记的裸短语仍然按截止（旧行为）；
/// - 有 `开始` 标记、没有 `截止` 标记时，另一条裸短语按截止（D5）；
/// - 最多取第一个开始、第一个截止，多余短语留在标题里。
class ParsedQuickAdd {
  const ParsedQuickAdd({
    required this.start,
    required this.due,
    required this.title,
  });

  final DateTime? start;
  final DateTime? due;
  final String title;

  bool get hasDate => start != null || due != null;
}

ParsedQuickAdd? parseQuickAdd(String input, DateTime now) {
  final List<({int start, int end, DateTime value, bool isStart})> marks =
      <({int start, int end, DateTime value, bool isStart})>[];
  for (final RegExpMatch m in _markedPattern.allMatches(input)) {
    final ParsedDue? p = parseDuePhrase(m.group(1)!, now);
    if (p == null) continue;
    marks.add((
      start: m.start,
      end: m.end,
      value: p.due,
      isStart: m.group(0)!.endsWith('开始'),
    ));
  }

  DateTime? start;
  DateTime? due;
  final List<({int start, int end})> spans = <({int start, int end})>[];
  for (final ({int start, int end, DateTime value, bool isStart}) m in marks) {
    if (m.isStart && start == null) {
      start = m.value;
      spans.add((start: m.start, end: m.end));
    } else if (!m.isStart && due == null) {
      due = m.value;
      spans.add((start: m.start, end: m.end));
    }
  }

  // 只有开始标记、没有截止标记：再找一条不在标记区间内的裸短语当截止。
  if (due == null) {
    final ParsedDue? bare = parseDuePhrase(_mask(input, spans), now);
    if (bare != null) {
      due = bare.due;
      spans.add((start: bare.start, end: bare.end));
    }
  }

  if (start == null && due == null) return null;
  return ParsedQuickAdd(start: start, due: due, title: _strip(input, spans));
}

String _mask(String input, List<({int start, int end})> spans) {
  if (spans.isEmpty) return input;
  final List<String> chars = input.split('');
  for (final ({int start, int end}) s in spans) {
    for (int i = s.start; i < s.end && i < chars.length; i++) {
      chars[i] = ' ';
    }
  }
  return chars.join();
}

String _strip(String input, List<({int start, int end})> spans) {
  if (spans.isEmpty) return input.trim();
  final List<({int start, int end})> sorted = List<({int start, int end})>.of(spans)
    ..sort((a, b) => a.start.compareTo(b.start));
  final StringBuffer out = StringBuffer();
  int cursor = 0;
  for (final ({int start, int end}) s in sorted) {
    if (s.start < cursor) continue;
    out.write(input.substring(cursor, s.start));
    cursor = s.end;
  }
  out.write(input.substring(cursor));
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

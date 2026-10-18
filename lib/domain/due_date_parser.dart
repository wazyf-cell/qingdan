/// 快速添加的自然语言日期解析（F1，M1 最小短语集）。
///
/// 纯函数，无 IO；不引入第三方依赖（如 chrono），自实现最小集合。
/// 支持短语：
/// - 相对日：「今天 / 明天 / 后天 / 大后天」「明早 / 今晚 / 明晚」
/// - 星期：「周X / 礼拜X（X=一~六、日、天）」「下周X」「下下周X」
/// - 时刻：「X点 / X点半 / 上午X点 / 下午X点 / 晚上X点 / 中午X点 / 凌晨X点」「H:mm」
/// - 绝对日期：「M月D日」「M/D」
///
/// 约定：
/// - 无显式时刻时默认 09:00（明早 08:00 / 今晚·明晚 20:00）；
/// - 「M月D日 / M/D」若早于今天则顺延一年；「周X」取今天起最近的未来 X；
/// - 只解析第一个日期短语 + 第一个时刻短语，二者合并为一段匹配区间，
///   供调用方从标题中剔除（例如「明早10点交周报」→ 剔除「明早10点」）。
library;

/// 解析结果：[due] 为本地时间；[start]/[end] 为标题中匹配区间的
/// 半开区间下标；[hasExplicitTime] 表示用户显式写了时刻。
class ParsedDue {
  const ParsedDue({
    required this.due,
    required this.start,
    required this.end,
    required this.hasExplicitTime,
    required this.label,
  });

  final DateTime due;
  final int start;
  final int end;
  final bool hasExplicitTime;

  /// 日期部分描述（不含时刻），如「明天(12/24)」「周三(01/07)」「12月25日」。
  final String label;
}

final RegExp _datePattern = RegExp(
  r'大后天|后天|明天|今天|今晚|明晚|明早|'
  r'下下周[一二三四五六日天]|下周[一二三四五六日天]|'
  r'(?:礼拜|周)[一二三四五六日天]|'
  r'\d{1,2}月\d{1,2}日|\d{1,2}/\d{1,2}',
);

final RegExp _timePattern = RegExp(
  r'(上午|早上|凌晨|中午|下午|晚上|傍晚)?\s*(\d{1,2})点(半)?'
  r'|\s*(\d{1,2})[:：](\d{2})',
);

int _weekdayOf(String ch) => switch (ch) {
      '一' => DateTime.monday,
      '二' => DateTime.tuesday,
      '三' => DateTime.wednesday,
      '四' => DateTime.thursday,
      '五' => DateTime.friday,
      '六' => DateTime.saturday,
      _ => DateTime.sunday,
    };


String _md(DateTime d) => '${d.month}/${d.day}';

DateTime _at(DateTime day, int hour, int minute) =>
    DateTime(day.year, day.month, day.day, hour, minute);

/// 从 [input] 解析第一个日期短语（可带时刻）。无匹配返回 null。
ParsedDue? parseDuePhrase(String input, DateTime now) {
  final RegExpMatch? dateMatch = _datePattern.firstMatch(input);
  final RegExpMatch? timeMatch = _timePattern.firstMatch(input);
  if (dateMatch == null && timeMatch == null) return null;

  DateTime baseDay;
  int defaultHour = 9;
  bool dateOnly = false;
  String label = '';

  if (dateMatch == null) {
    baseDay = DateTime(now.year, now.month, now.day);
    dateOnly = true;
  } else {
    final String token = dateMatch.group(0)!;
    (baseDay, defaultHour, label, dateOnly) =
        _resolveDate(token, now, dateMatch.start);
  }

  int hour = defaultHour;
  int minute = 0;
  bool hasExplicitTime = false;

  if (timeMatch != null) {
    final (int h, int m, bool explicit) = _resolveTime(timeMatch);
    if (explicit) {
      hour = h;
      minute = m;
      hasExplicitTime = true;
    }
  }

  final DateTime due = _at(baseDay, hour, minute);

  // 只有时刻短语且它无效（如「25点」）：不视为解析成功，避免误建反馈行。
  if (dateMatch == null && !hasExplicitTime) return null;

  // 匹配区间 = 日期短语与时刻短语的并集（供调用方从标题中剔除）。
  final int start = dateMatch == null
      ? timeMatch!.start
      : timeMatch == null || dateMatch.start < timeMatch.start
          ? dateMatch.start
          : timeMatch.start;
  final int end = dateMatch == null
      ? timeMatch!.end
      : timeMatch == null || dateMatch.end > timeMatch.end
          ? dateMatch.end
          : timeMatch.end;

  return ParsedDue(
    due: due,
    start: start,
    end: end,
    hasExplicitTime: hasExplicitTime,
    label: dateOnly && timeMatch != null
        ? dateOnlyLabel(due, now)
        : label,
  );
}

/// 仅时刻短语（无日期词）时的日期标签。
String dateOnlyLabel(DateTime due, DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime dueDay = DateTime(due.year, due.month, due.day);
  final int days = dueDay.difference(today).inDays;
  if (days == 0) return '今天(${_md(due)})';
  if (days == 1) return '明天(${_md(due)})';
  return _md(due);
}

/// 解析日期 token →（基准日, 默认时刻, 展示标签）。
(DateTime, int, String, bool) _resolveDate(
    String token, DateTime now, int offset) {
  final DateTime today = DateTime(now.year, now.month, now.day);

  switch (token) {
    case '今天':
      return (today, 9, '今天(${_md(today)})', false);
    case '明天':
      final d = today.add(const Duration(days: 1));
      return (d, 9, '明天(${_md(d)})', false);
    case '后天':
      final d = today.add(const Duration(days: 2));
      return (d, 9, '后天(${_md(d)})', false);
    case '大后天':
      final d = today.add(const Duration(days: 3));
      return (d, 9, '大后天(${_md(d)})', false);
    case '明早':
      final d = today.add(const Duration(days: 1));
      return (d, 8, '明天(${_md(d)})', false);
    case '今晚':
      return (today, 20, '今天(${_md(today)})', false);
    case '明晚':
      final d = today.add(const Duration(days: 1));
      return (d, 20, '明天(${_md(d)})', false);
  }

  // 下周X / 下下周X：按日历周（周一为一周之始）——下周X = 下个周一 + (X-1) 天。
  if (token.startsWith('下下周') || token.startsWith('下周')) {
    final int weeks = token.startsWith('下下周') ? 2 : 1;
    final int target = _weekdayOf(token[token.length - 1]);
    int toNextMonday = (DateTime.monday - now.weekday) % 7;
    if (toNextMonday == 0) toNextMonday = 7;
    final DateTime d = today
        .add(Duration(days: toNextMonday + (target - 1) + 7 * (weeks - 1)));
    final String prefix = weeks == 2 ? '下下周' : '下周';
    return (d, 9, '$prefix${_weekdayName(target)}(${_md(d)})', false);
  }

  // 周X / 礼拜X：今天起最近的一个 X（今天命中则取今天）。
  final RegExp weekRe = RegExp(r'[一二三四五六日天]$');
  if (weekRe.hasMatch(token) && (token.contains('周') || token.contains('礼'))) {
    final int target = _weekdayOf(token[token.length - 1]);
    int delta = (target - now.weekday) % 7;
    if (delta < 0) delta += 7;
    final DateTime d = today.add(Duration(days: delta));
    return (d, 9, '${_weekdayName(target)}(${_md(d)})', false);
  }

  // M月D日 / M/D：本年，早于今天则顺延一年。
  final RegExp absolute = RegExp(r'(\d{1,2})月(\d{1,2})日|^(\d{1,2})/(\d{1,2})$');
  final RegExpMatch? m = absolute.firstMatch(token);
  if (m != null) {
    final int month = int.parse(m.group(1) ?? m.group(3)!);
    final int day = int.parse(m.group(2) ?? m.group(4)!);
    DateTime d = DateTime(now.year, month, day);
    if (d.isBefore(today)) d = DateTime(now.year + 1, month, day);
    return (d, 9, '${d.month}月${d.day}日', false);
  }

  // 兜底（不应到达）：当作今天。
  return (today, 9, '今天(${_md(today)})', false);
}

String _weekdayName(int weekday) => switch (weekday) {
      DateTime.monday => '周一',
      DateTime.tuesday => '周二',
      DateTime.wednesday => '周三',
      DateTime.thursday => '周四',
      DateTime.friday => '周五',
      DateTime.saturday => '周六',
      _ => '周日',
    };

/// 解析时刻 token →（时, 分, 是否显式时刻）。
(int, int, bool) _resolveTime(RegExpMatch m) {
  // 形如 H:mm。
  if (m.group(4) != null) {
    final int h = int.parse(m.group(4)!);
    final int min = int.parse(m.group(5)!);
    if (h >= 0 && h <= 23 && min >= 0 && min <= 59) return (h, min, true);
    return (0, 0, false);
  }
  int h = int.parse(m.group(2)!);
  final int min = m.group(3) == '半' ? 30 : 0;
  final String prefix = m.group(1) ?? '';
  if (h > 23) return (0, 0, false);
  switch (prefix) {
    case '下午' || '晚上' || '傍晚':
      if (h < 12) h += 12;
    case '凌晨':
      // 凌晨X点：0–5 原样。
      break;
    case '中午':
      if (h < 11) h += 12; // 中午12点 → 12，中午1点 → 13。
    case '上午' || '早上':
      if (h == 12) h = 0;
  }
  return (h, min, true);
}

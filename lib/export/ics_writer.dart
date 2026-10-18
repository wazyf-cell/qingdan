// 课表 → iCalendar（.ics）文本（M6-D §9.1）。**纯函数，只产字符串、不碰平台**。
//
// 逐周展开而不是 `RRULE`：`BYDAY` + `UNTIL` 在跨学期与「周次不连续」（1-8、12-16 周）
// 时很容易写错，一门 16 周的课就是 16 个 VEVENT（§9.1 定案）。
//
// 三条 RFC 5545 细节全部有单测钉住（§9.3）：
//   1. 行结束符是 CRLF，不是裸 `\n`；
//   2. 单行超过 75 **octet** 要折叠，续行以一个空格开头，且只能按 UTF-8 码点边界断；
//   3. 文本值里的 `\` `,` `;` `:` 与换行要转义。
// 时刻一律写 `DTSTART;TZID=Asia/Shanghai:20261019T080000` 这种**带时区的本地时间**，
// 绝不写 `Z` 结尾的 UTC——很多日历应用会按 UTC 显示，课程会整体偏 8 小时。

import '../domain/course.dart';
import '../domain/section_layout.dart';
import '../domain/semester.dart';
import '../domain/time_table.dart';
import '../domain/week_rule.dart';

/// RFC 5545 §3.1：单行（不含 CRLF）不得超过 75 octet。
const int kIcsMaxOctets = 75;

/// 导出用的固定时区。中国无夏令时，所以 `VTIMEZONE` 只有一个 STANDARD。
const String kIcsTzId = 'Asia/Shanghai';

const List<String> _weekdayText = <String>[
  '周一', '周二', '周三', '周四', '周五', '周六', '周日',
];

/// 一次导出的产物。[skippedNames] 供界面拼
/// 「{N} 门课因节次不在作息表中被跳过」（呼应「绝不静默截断」）。
class IcsExport {
  const IcsExport({
    required this.text,
    required this.eventCount,
    required this.skippedNames,
  });

  final String text;

  /// 实际写出的 VEVENT 个数。
  final int eventCount;

  /// 被跳过的课程名（去重，保持出现顺序）。
  final List<String> skippedNames;

  int get skippedCount => skippedNames.length;
}

/// 把 [courses] 按学期 [semester] 的周次展开成一份 ics 文本。
///
/// [nowUtc] 是 DTSTAMP 用的当前 UTC 时刻（做成参数以便测试拿到确定性输出）；
/// 不传则取 `DateTime.now().toUtc()`。[details] 是该学期的作息表：
/// 起止节次只要有一节不在表上，整门课跳过并计数，**不做任何静默截断**。
IcsExport writeIcs({
  required Semester semester,
  required List<Course> courses,
  required List<TimeDetail> details,
  DateTime? nowUtc,
}) {
  final SectionLayout layout = layoutSections(details);
  final String stamp = 'DTSTAMP:${_utcStamp(nowUtc ?? DateTime.now().toUtc())}';
  final List<String> lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//qingdan//学期课表导出 1.0//CN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${_escapeText(semester.name)}',
    'X-WR-TIMEZONE:$kIcsTzId',
    'BEGIN:VTIMEZONE',
    'TZID:$kIcsTzId',
    'BEGIN:STANDARD',
    'DTSTART:19700101T000000',
    'TZOFFSETFROM:+0800',
    'TZOFFSETTO:+0800',
    'TZNAME:CST',
    'END:STANDARD',
    'END:VTIMEZONE',
  ];

  final List<String> skipped = <String>[];
  int eventCount = 0;
  for (final Course c in courses) {
    if (c.deleted) continue; // 回收站里的课不进日历
    if (layout.missingSections(c.startSection, c.endSection).isNotEmpty) {
      if (!skipped.contains(c.name)) skipped.add(c.name);
      continue;
    }
    for (final int week in c.weeks) {
      lines.addAll(_eventLines(c, week, semester, layout, stamp));
      eventCount++;
    }
  }
  lines.add('END:VCALENDAR');
  return IcsExport(
    text: '${<String>[for (final String l in lines) _foldLine(l)].join('\r\n')}\r\n',
    eventCount: eventCount,
    skippedNames: skipped,
  );
}

/// 一个 (课程, 周) 的全部逻辑行（折叠在写文件时统一做）。
List<String> _eventLines(
  Course c,
  int week,
  Semester semester,
  SectionLayout layout,
  String stamp,
) {
  final DateTime day =
      semester.mondayOfWeek(week).add(Duration(days: c.weekday - 1));
  final ({int startMinutes, int endMinutes}) start =
      layout.timeOf(c.startSection)!;
  final ({int startMinutes, int endMinutes}) end = layout.timeOf(c.endSection)!;
  final String description = <String>[
    '${_weekdayText[c.weekday - 1]} · 第 $week 周',
    '第 ${c.startSection}-${c.endSection} 节 '
        '${formatMinutes(start.startMinutes)}–${formatMinutes(end.endMinutes)}',
    if (c.teacher != null) '老师：${c.teacher}',
    if (c.location != null) '地点：${c.location}',
    '周次：${_weeksText(c)}',
  ].join('\n');

  return <String>[
    'BEGIN:VEVENT',
    // UID 稳定：同一份 ics 重复导入不会产生重复事件（§9.1）。
    'UID:${c.uid}-$week@qingdan',
    stamp,
    'DTSTART;TZID=$kIcsTzId:${_localDateTime(day, start.startMinutes)}',
    'DTEND;TZID=$kIcsTzId:${_localDateTime(day, end.endMinutes)}',
    'SUMMARY:${_escapeText(c.name)}',
    if (c.location != null) 'LOCATION:${_escapeText(c.location!)}',
    'DESCRIPTION:${_escapeText(description)}',
    'END:VEVENT',
  ];
}

/// 周数单元格/描述：有原始写法就用原文，否则由具体周次还原紧凑写法。
String _weeksText(Course c) {
  final String raw = c.rawWeeksText?.trim() ?? '';
  if (raw.isNotEmpty) return raw;
  final String compact = formatWeeks(c.weeks);
  return compact.isEmpty ? '' : '$compact周';
}

/// RFC 5545 文本值转义。先换 `\`，否则会把自己刚插入的反斜杠再转一遍。
String _escapeText(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll(':', r'\:')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n');

/// 把一条逻辑行折成 physical lines（含内部 CRLF）。
///
/// 预算按 **UTF-8 字节数**算：续行开头那个空格占 1 个 octet，所以续行的内容预算
/// 是 74。断点只在码点之间选（逐个 rune 累加字节数），因此中文、emoji 这类
/// 多字节字符不可能被切成两半。
String _foldLine(String logicalLine) {
  final StringBuffer cur = StringBuffer();
  final List<String> physical = <String>[];
  int budget = kIcsMaxOctets;
  int used = 0;
  for (final int rune in logicalLine.runes) {
    final int byteCount = _utf8BytesOfRune(rune);
    if (used + byteCount > budget) {
      physical.add(cur.toString());
      cur.clear();
      cur.write(' '); // 续行以一个空格开头
      used = 0;
      budget = kIcsMaxOctets - 1;
    }
    cur.write(String.fromCharCode(rune));
    used += byteCount;
  }
  physical.add(cur.toString());
  return physical.join('\r\n');
}

/// 码点 → UTF-8 字节数（1/2/3/4）。用它算折行预算，不必真的编码。
int _utf8BytesOfRune(int rune) {
  if (rune < 0x80) return 1;
  if (rune < 0x800) return 2;
  if (rune < 0x10000) return 3;
  return 4;
}

/// 本地日期 + 当日分钟数 → `YYYYMMDDTHHMMSS`（跨零点整时进位到次日）。
String _localDateTime(DateTime date, int minutesOfDay) {
  final DateTime day = date.add(Duration(days: minutesOfDay ~/ 1440));
  final int m = minutesOfDay % 1440;
  return '${_digits(day.year, 4)}${_digits(day.month, 2)}${_digits(day.day, 2)}'
      'T${_digits(m ~/ 60, 2)}${_digits(m % 60, 2)}00';
}

/// UTC 时刻 → `YYYYMMDDTHHMMSSZ`。只有 DTSTAMP 用 UTC（RFC 5545 §3.8.2.5）。
String _utcStamp(DateTime utc) {
  final DateTime u = utc.toUtc();
  return '${_digits(u.year, 4)}${_digits(u.month, 2)}${_digits(u.day, 2)}'
      'T${_digits(u.hour, 2)}${_digits(u.minute, 2)}${_digits(u.second, 2)}Z';
}

String _digits(int value, int width) => '$value'.padLeft(width, '0');

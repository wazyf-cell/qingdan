/// WakeUp 课程表的导出文件（`.wakeup_schedule`）→ 导入向导的原始表。
///
/// **来源声明**（AGENTS.md 禁止事项）：文件形态反推自用户提供的真样本
/// `扩展/<学期>.wakeup_schedule`（2026-10-18，5 段拼接的 JSON）；字段语义对齐
/// WakeUp 反编译产物 `F:\Code\APK-MCP\3-Wakeup\Gradle\app\src\main\java\
/// com\suda\net\schedule_import\bean\` 的 `CourseBaseBean.java:16-21`
/// （courseName / id / tableId）与 `CourseDetailBean.java:17-30`
/// （day / startNode / step / startWeek / endWeek / type / room / teacher）。
/// 只按这些字段名读数据，未拷贝其代码。
///
/// 为什么值得支持它：WakeUp 是成熟应用，它已经把教务页解析对了——同一份课表，
/// 我们的 HTML 抓取要处理「跨节次行重复」，而它直接给 `startNode + step`
/// （例：某门 12 周 1-8 节连排的课 = 一条明细，抓取时会被散成 4 条）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:qingdan/domain/time_table.dart';

import 'schedule_file.dart';

/// 一节的时间（`HH:mm`）。命名记录类型，免得在排序/校验里重复写一遍结构。
typedef WakeupSection = ({int section, String start, String end});

/// 导出文件里**顺带带着**的学期与作息（我们自己的 CSV/xlsx 模板没有这两项）。
///
/// 用途：向导第 3 步**预填并让用户点一下采纳**——不静默覆盖已有学期。
class WakeupMeta {
  const WakeupMeta({
    required this.firstWeekDate,
    required this.totalWeeks,
    required this.sections,
  });

  final DateTime firstWeekDate;
  final int totalWeeks;

  /// 节次号 → 起止时间（`HH:mm`），按节次升序。
  final List<WakeupSection> sections;

  /// 转成作息卡认得的草稿（`id`/`timetableId` 留空即「新建默认作息表」，
  /// 与 `timetable_editor.dart:65` 手工加节的构造同形）。
  List<TimeDetail> toDraft() => <TimeDetail>[
        for (final WakeupSection s in sections)
          TimeDetail(
            id: '',
            timetableId: '',
            section: s.section,
            startMinutes: _minutes(s.start),
            endMinutes: _minutes(s.end),
          ),
      ];

  static int _minutes(String hhmm) {
    final List<String> parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

/// 是不是 WakeUp 导出：三段特征键齐了才算（避免把普通 JSON 误判进来）。
bool isWakeupSchedule(Uint8List bytes) {
  if (bytes.isEmpty || bytes[0] != 0x7B /* { */) return false;
  final String text = utf8.decode(bytes, allowMalformed: true);
  return text.contains('"courseLen"') &&
      text.contains('"courseName"') &&
      text.contains('"startNode"');
}

ScheduleTable readWakeupSchedule(Uint8List bytes) {
  final List<Object?> segments = _jsonSegments(bytes);
  final List<Map<String, Object?>> courses =
      _firstListOf(segments, 'courseName', '课程段');
  final List<Map<String, Object?>> details =
      _firstListOf(segments, 'startNode', '时间明细段');
  final Map<int, Map<String, Object?>> courseById = <int, Map<String, Object?>>{
    for (final Map<String, Object?> c in courses)
      (c['id'] as num).toInt(): c,
  };

  // 同一门课、同一天、同一节次区间、同一教室老师的多条明细 = 周次不连续的
  // 几段（强智页面上就是 `1-6,8-11,13-15(周)` 这种），合并成一行。
  final Map<_Span, List<List<int>>> weeks = <_Span, List<List<int>>>{};
  for (final Map<String, Object?> d in details) {
    final Map<String, Object?>? course = courseById[(d['id'] as num).toInt()];
    if (course == null) continue;
    final int startNode = (d['startNode'] as num).toInt();
    final _Span span = _Span(
      course['courseName'] as String? ?? '',
      (d['day'] as num).toInt(),
      startNode,
      startNode + (d['step'] as num).toInt() - 1,
      d['teacher'] as String? ?? '',
      d['room'] as String? ?? '',
      (d['type'] as num?)?.toInt() ?? 0,
    );
    weeks.putIfAbsent(span, () => <List<int>>[]).add(<int>[
      (d['startWeek'] as num).toInt(),
      (d['endWeek'] as num).toInt(),
    ]);
  }

  final List<_Span> spans = weeks.keys.toList()
    ..sort((_Span a, _Span b) =>
        a.day != b.day ? a.day.compareTo(b.day) : (a.start != b.start
            ? a.start.compareTo(b.start)
            : a.name.compareTo(b.name)));
  return ScheduleTable(
    encoding: FileEncoding.utf8,
    sheetName: 'WakeUp 导出',
    rows: <List<String>>[
      kImportHeader,
      for (final _Span s in spans)
        <String>[
          s.name,
          '${s.day}',
          '${s.start}',
          '${s.end}',
          s.teacher,
          s.room,
          _weeksText(weeks[s]!, s.type),
        ],
    ],
  );
}

/// 从同一份导出里取学期与作息；缺段或日期读不出时返回 null（界面就不显示采纳条）。
WakeupMeta? readWakeupMeta(Uint8List bytes) {
  final List<Object?> segments = _jsonSegments(bytes);
  Map<String, Object?>? view;
  for (final Object? s in segments) {
    if (s is Map && s.containsKey('startDate') && s.containsKey('maxWeek')) {
      view = s.cast<String, Object?>();
      break;
    }
  }
  if (view == null) return null;
  final List<String> ymd =
      (view['startDate'] as String? ?? '').split(RegExp(r'[-/.]'));
  if (ymd.length != 3) return null;
  final DateTime? first = DateTime.tryParse(
      '${ymd[0]}-${ymd[1].padLeft(2, '0')}-${ymd[2].padLeft(2, '0')}');
  if (first == null) return null;
  final int timeTable = (view['timeTable'] as num?)?.toInt() ?? 1;
  // 节次表必须截断：WakeUp 把生成的**整表 60 行**都写进导出，第 12 节起时间
  // 自相重叠（20:50-21:35 / 21:25-22:10 / 21:35-22:20…）。上限取
  // 「课表视图声明的节数」与「课程真正用到的最大节」的较大者。
  int maxUsedNode = 0;
  for (final Object? s in segments) {
    if (s is! List || s.isEmpty || s.first is! Map) continue;
    if (!(s.first as Map).containsKey('startNode')) continue;
    for (final Object? row in s) {
      final Map<String, Object?> r = (row! as Map).cast();
      final int end =
          (r['startNode'] as num).toInt() + (r['step'] as num).toInt() - 1;
      if (end > maxUsedNode) maxUsedNode = end;
    }
  }
  final int declared = (view['nodes'] as num?)?.toInt() ?? 0;
  final int nodeCap = declared > maxUsedNode ? declared : maxUsedNode;
  if (nodeCap <= 0) return null;
  final List<WakeupSection> sections = <WakeupSection>[];
  for (final Object? s in segments) {
    if (s is! List || s.isEmpty || s.first is! Map) continue;
    if (!(s.first as Map).containsKey('node')) continue;
    for (final Object? row in s) {
      final Map<String, Object?> r = (row! as Map).cast();
      if (((r['timeTable'] as num?)?.toInt() ?? 0) != timeTable) continue;
      final int node = (r['node'] as num).toInt();
      if (node > nodeCap) continue;
      sections.add((
        section: node,
        start: r['startTime'] as String? ?? '',
        end: r['endTime'] as String? ?? '',
      ));
    }
    break;
  }
  sections.sort((WakeupSection a, WakeupSection b) =>
      a.section.compareTo(b.section));
  if (sections.any((WakeupSection s) =>
      s.start.length < 5 || s.end.length < 5)) {
    return null;
  }
  return WakeupMeta(
    firstWeekDate: first,
    totalWeeks: (view['maxWeek'] as num?)?.toInt() ?? 20,
    sections: sections,
  );
}

/// 周次文本：`1-6,8-11,13-15(周)`；单双周用 `1-15单` / `1-15双`
/// （`week_rule.dart` 认这种无括号形式，括号版只测过全角）。
String _weeksText(List<List<int>> ranges, int type) {
  ranges.sort((List<int> a, List<int> b) => a[0].compareTo(b[0]));
  final String body = ranges
      .map((List<int> r) => r[0] == r[1] ? '${r[0]}' : '${r[0]}-${r[1]}')
      .join(',');
  return switch (type) {
    1 => '$body单',
    2 => '$body双',
    _ => '$body(周)',
  };
}

/// 文件是**多段 JSON 直接拼接**（不是数组、没有分隔符），按括号配平逐段切出来。
List<Object?> _jsonSegments(Uint8List bytes) {
  final String text = utf8.decode(bytes, allowMalformed: true);
  final List<Object?> out = <Object?>[];
  int i = 0;
  while (true) {
    while (i < text.length &&
        (text[i] == ' ' || text[i] == '\n' || text[i] == '\r' || text[i] == '\t')) {
      i++;
    }
    if (i >= text.length) return out;
    final int end = _endOfSegment(text, i);
    try {
      out.add(jsonDecode(text.substring(i, end)));
    } on FormatException catch (e) {
      throw ScheduleFileException('不是能读的 WakeUp 导出（$e）');
    }
    i = end;
  }
}

int _endOfSegment(String text, int from) {
  final String open = text[from];
  final String close = open == '{' ? '}' : ']';
  int depth = 0;
  bool inString = false, escaped = false;
  for (int i = from; i < text.length; i++) {
    final String ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == open) {
      depth++;
    } else if (ch == close) {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return text.length;
}

List<Map<String, Object?>> _firstListOf(
    List<Object?> segments, String key, String what) {
  for (final Object? s in segments) {
    if (s is List &&
        s.isNotEmpty &&
        s.first is Map &&
        (s.first as Map).containsKey(key)) {
      return s.cast<Map<String, Object?>>();
    }
  }
  throw ScheduleFileException('缺$what（找不到含 "$key" 的段）');
}

class _Span {
  const _Span(this.name, this.day, this.start, this.end, this.teacher, this.room,
      this.type);

  final String name;
  final int day;
  final int start;
  final int end;
  final String teacher;
  final String room;
  final int type;

  @override
  bool operator ==(Object other) => other is _Span &&
      other.name == name &&
      other.day == day &&
      other.start == start &&
      other.end == end &&
      other.teacher == teacher &&
      other.room == room &&
      other.type == type;

  @override
  int get hashCode =>
      Object.hash(name, day, start, end, teacher, room, type);
}

/// 强智教务系统（`/jsxsd/xskb/xskb_list.do`）课表页 HTML → 导入向导的原始表。
///
/// **来源声明**（AGENTS.md 禁止事项）：表格结构取自 2026-10-18 真机抓取样本
/// `jiaowu_1792254054670.html`（本校教务系统，42 个课表单元）。解析骨架对齐
/// WakeUp 的强智系解析器（`F:\Code\APK-MCP\3-Wakeup\...\schedule_parser\`
/// `parser/base/OooOOO0.java:309` 的 `qz` 系：行首 `<th>` 定节次、列序定星期、
/// `<font title=…>` 定字段），**未拷贝其代码**。
///
/// 页面事实（逐条对着样本核过，不猜）：
/// - 主表 `<table id="timetable">`；第一行 `<th>星期一…星期日</th>` 定列；
///   之后每行行首 `<th>` 是节次组，形如「第一二节」「第九十节」「第十一、十二节」。
/// - 每个 `<td>` 里是若干 `<font>`，`title` 标字段：`周次(节次)` / `教室` /
///   `教师` / `教学楼` / `班级` / `备注`；**没有 title 且没有 name 的 font 是课程名**，
///   它是下一节课的起点（同一格可叠多节课，中间用一行 `----------------------` 隔开）。
/// - 同一格还并排放着悬停详情（`周次(节次)` 带 `[01-02节]` 后缀、教师、通知单编号），
///   与简表条目按「课程名+周次+教室」合并，教师从详情取。
/// - 跨多节的课（如 12 周 1-8 节的工训）在每一行都重复出现一次，
///   所以按行导出多条时间明细，与手工 CSV 多行的既有语义一致。
library;

import '../course/schedule_file.dart';

class _QzCourse {
  String name = '';
  String weeks = '';
  String room = '';
  String teacher = '';
}

/// 解析 [html]（可以是整页，也可以是 WebView 递归抓回来的多 iframe 拼接串）。
/// 找不到 `id="timetable"` 时返回空表，由界面提示「请先导航到课表页」。
ScheduleTable parseQzTimetable(String html) {
  final String? table = _timetableHtml(html);
  if (table == null) {
    return const ScheduleTable(rows: <List<String>>[], encoding: FileEncoding.utf8);
  }
  // 强智把跨多节的课（如 12 周 1-8 节的工训）在每个 2 节行里各重复一遍，
  // 直接按行导出会散成 4 条。先按「星期+课+老师+教室+周次」收拢，再把**相邻**
  // 的节次区间并成一条（非相邻的仍各一行，与 WakeUp 导出的 startNode+step 同形）。
  final Map<_Key, List<_Range>> grouped = <_Key, List<_Range>>{};
  for (final RegExpMatch tr in RegExp(r'<tr[^>]*>([\s\S]*?)</tr>').allMatches(table)) {
    final List<String> ths = _tagTexts(r'<th[^>]*>([\s\S]*?)</th>', tr.group(1)!);
    final ({int start, int end})? nodes = ths.isEmpty ? null : _nodes(ths.first);
    if (nodes == null) continue; // 表头行与「备注」图例行
    final List<String> tds = _tagBodies(r'<td[^>]*>([\s\S]*?)</td>', tr.group(1)!);
    for (int day = 1; day <= tds.length; day++) {
      for (final _QzCourse c in _coursesInCell(tds[day - 1])) {
        grouped
            .putIfAbsent(_Key(day, c.name, c.teacher, c.room, c.weeks),
                () => <_Range>[])
            .add(_Range(nodes.start, nodes.end));
      }
    }
  }
  final List<_Key> keys = grouped.keys.toList()
    ..sort((_Key a, _Key b) => a.day != b.day
        ? a.day.compareTo(b.day)
        : a.name.compareTo(b.name));
  return ScheduleTable(
    encoding: FileEncoding.utf8,
    sheetName: '强智课表页',
    rows: <List<String>>[
      kImportHeader,
      for (final _Key k in keys)
        for (final _Range r in _mergeAdjacent(grouped[k]!))
          <String>[k.name, '${k.day}', '${r.start}', '${r.end}', k.teacher, k.room, k.weeks],
    ],
  );
}

/// 相邻（`上一段.end + 1 == 下一段.start`）的节次区间并一条。
List<_Range> _mergeAdjacent(List<_Range> ranges) {
  final List<_Range> sorted = ranges.toList()
    ..sort((_Range a, _Range b) => a.start.compareTo(b.start));
  final List<_Range> out = <_Range>[];
  for (final _Range r in sorted) {
    if (out.isNotEmpty && out.last.end + 1 == r.start) {
      out[out.length - 1] = _Range(out.last.start, r.end);
    } else {
      out.add(r);
    }
  }
  return out;
}

class _Key {
  const _Key(this.day, this.name, this.teacher, this.room, this.weeks);

  final int day;
  final String name;
  final String teacher;
  final String room;
  final String weeks;

  @override
  bool operator ==(Object other) =>
      other is _Key &&
      other.day == day &&
      other.name == name &&
      other.teacher == teacher &&
      other.room == room &&
      other.weeks == weeks;

  @override
  int get hashCode => Object.hash(day, name, teacher, room, weeks);
}

class _Range {
  const _Range(this.start, this.end);

  final int start;
  final int end;
}

/// 深度计数切出 `<table id="timetable">…</table>`。
String? _timetableHtml(String html) {
  final int at = html.indexOf('id="timetable"');
  if (at < 0) return null;
  final int start = html.lastIndexOf('<table', at);
  if (start < 0) return null;
  int depth = 0, i = start;
  while (true) {
    final int open = html.indexOf('<table', i + 1);
    final int close = html.indexOf('</table>', i + 1);
    if (close < 0) break;
    if (0 <= open && open < close) {
      depth++;
      i = open;
    } else {
      if (depth == 0) {
        i = close;
        break;
      }
      depth--;
      i = close;
    }
  }
  return html.substring(start, i);
}

List<String> _tagTexts(String pattern, String src) => RegExp(pattern)
    .allMatches(src)
    .map((Match m) => _clean(m.group(1)!))
    .toList();

List<String> _tagBodies(String pattern, String src) => RegExp(pattern)
    .allMatches(src)
    .map((Match m) => m.group(1)!)
    .toList();

String _clean(String html) =>
    html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').trim();

/// 「第一二节」→1-2；「第九十节」→9-10；「第十一、十二节」→11-12。
({int start, int end})? _nodes(String label) {
  final String body = label.replaceAll(RegExp(r'[第节\s、，,]'), '');
  final List<int> nums = <int>[];
  for (int i = 0; i < body.length; i++) {
    final int? v = _cnDigit(body[i]);
    if (v != null) {
      nums.add(v);
    } else if (body[i] == '十') {
      final int? next = i + 1 < body.length ? _cnDigit(body[i + 1]) : null;
      nums.add(next == null ? 10 : 10 + next);
      i++;
    }
  }
  if (nums.isEmpty || nums.length > 2) return null;
  return (start: nums.first, end: nums.last);
}

int? _cnDigit(String ch) => const <String, int>{
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9,
    }[ch];

/// 一个 `<td>` 里的所有课：按「无 title 无 name 的 font = 课程名」切段，
/// 简表段与悬停详情段按 课程名+周次+教室 合并（详情补老师）。
List<_QzCourse> _coursesInCell(String tdHtml) {
  final List<_QzCourse> out = <_QzCourse>[];
  final Map<String, _QzCourse> byKey = <String, _QzCourse>{};
  _QzCourse? cur;

  void close() {
    if (cur == null) return;
    final _QzCourse c = cur!;
    if (c.name.isNotEmpty) {
      final String key = '${c.name}|${c.weeks}|${c.room}';
      final _QzCourse? known = byKey[key];
      if (known == null) {
        byKey[key] = c;
        out.add(c);
      } else if (known.teacher.isEmpty) {
        known.teacher = c.teacher;
      }
    }
    cur = null;
  }

  for (final RegExpMatch m
      in RegExp(r'<font([^>]*)>([\s\S]*?)</font>').allMatches(tdHtml)) {
    final String attrs = m.group(1)!;
    final String text = _clean(m.group(2)!);
    final String? title = RegExp(r'title="([^"]*)"').firstMatch(attrs)?.group(1);
    final bool named = RegExp(r'name="').hasMatch(attrs);
    if (title == null && !named) {
      if (text.isEmpty) continue;
      close();
      cur = _QzCourse()..name = text;
      continue;
    }
    if (cur == null || text.isEmpty) continue;
    switch (title) {
      case '周次(节次)':
        cur!.weeks = text.replaceAll(RegExp(r'\[[^\]]*节\]'), '').trim();
      case '教师':
        cur!.teacher = text;
      case '教室':
        if (cur!.room.isEmpty) cur!.room = text;
      default:
        break; // 教学楼/班级/备注/通知单编号：导入表里没有对应字段
    }
  }
  close();
  return out;
}

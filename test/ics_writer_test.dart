import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/section_layout.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/export/ics_writer.dart';

/// ics 导出的 RFC 5545 硬要求（M6-D §9.1 / §9.3）。
///
/// 钉住的正是「最容易写错」的几处：CRLF、75 octet 折行且不切断多字节字符、
/// 文本转义、逐周展开的事件个数、节次缺失的跳过计数、带 TZID 的本地时间。
void main() {
  /// 第 1 周周一（2026-10-19 真是周一）；纯日期用 UTC 表示，见 `Semester` 注释。
  final Semester semester = Semester(
    id: 'sem-1',
    name: '2026 秋季学期',
    firstWeekMonday: DateTime.utc(2026, 10, 19),
    totalWeeks: 16,
  );

  /// 从 08:00 起、每节 45 分钟、课间 10 分钟的前 [count] 节。
  List<TimeDetail> sections(int count) => <TimeDetail>[
        for (int s = 1; s <= count; s++)
          TimeDetail(
            id: 'tt-1-$s',
            timetableId: 'tt-1',
            section: s,
            startMinutes: 480 + (s - 1) * 55,
            endMinutes: 525 + (s - 1) * 55,
          ),
      ];

  final List<TimeDetail> fourSections = sections(4);

  Course course({
    String name = '高等数学',
    int weekday = 1,
    int start = 1,
    int end = 2,
    List<int> weeks = const <int>[1],
    String? teacher = '小明',
    String? location = '逸夫楼201',
    String? rawWeeksText,
    bool deleted = false,
  }) =>
      Course(
        id: 'c-$name',
        uid: 'uid-$name-$weekday-$start',
        name: name,
        weekday: weekday,
        startSection: start,
        endSection: end,
        weeks: weeks,
        teacher: teacher,
        location: location,
        rawWeeksText: rawWeeksText,
        semesterId: semester.id,
        deleted: deleted,
      );

  IcsExport export({
    required List<Course> courses,
    List<TimeDetail>? details,
  }) =>
      writeIcs(
        semester: semester,
        courses: courses,
        details: details ?? fourSections,
        nowUtc: DateTime.utc(2026, 10, 17, 1, 2, 3),
      );

  /// 按字节切物理行（**不先整体解码**，才能验出「多字节字符被拦腰截断」）。
  List<List<int>> splitCrlfBytes(List<int> bytes) {
    final List<List<int>> out = <List<int>>[];
    final List<int> cur = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0D && i + 1 < bytes.length && bytes[i + 1] == 0x0A) {
        out.add(List<int>.of(cur));
        cur.clear();
        i++;
        continue;
      }
      cur.add(bytes[i]);
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  /// 反折叠：CRLF + 一个前导空格 == 续行，还原成逻辑行列表。
  List<String> logicalLines(String text) {
    final List<String> out = <String>[];
    for (final String physical in text.split('\r\n')) {
      if (physical.startsWith(' ') && out.isNotEmpty) {
        out[out.length - 1] += physical.substring(1);
      } else if (physical.isNotEmpty) {
        out.add(physical);
      }
    }
    return out;
  }

  String lineStartingWith(String text, String prefix) => logicalLines(text)
      .firstWhere((String l) => l.startsWith(prefix), orElse: () => '<找不到 $prefix>');

  test('行结束符是 CRLF：全文没有裸 LF，末尾也是 CRLF', () {
    final IcsExport out = export(courses: <Course>[course()]);
    final List<int> bytes = utf8.encode(out.text);
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) {
        expect(i > 0 && bytes[i - 1] == 0x0D, isTrue,
            reason: '第 $i 字节是裸 LF，RFC 5545 要求 CRLF');
      }
    }
    expect(out.text.endsWith('\r\n'), isTrue);
    expect(out.text.contains('\n\n'), isFalse, reason: '不允许出现空行');
  });

  test('单行不超 75 octet，续行以一个空格开头，且不在多字节字符中间断开', () {
    final String longName = '高等数学与线性代数综合练习课程甲乙丙丁戊己' * 3; // 18 汉字 ×3 == 54 汉字
    final IcsExport out = export(courses: <Course>[
      course(
        name: longName,
        location: '第一教学楼会议室（很长一个地点名称，专门用来把行撑过 75 字节）',
      ),
    ]);
    final List<List<int>> chunks = splitCrlfBytes(utf8.encode(out.text));
    expect(chunks.length, greaterThan(20), reason: '太短就没进入折行分支');
    for (final List<int> chunk in chunks) {
      expect(chunk.length, lessThanOrEqualTo(kIcsMaxOctets),
          reason: '物理行超了 75 octet：${utf8.decode(chunk, allowMalformed: true)}');
      // 严格解码：只要有一行在多字节字符中间断开，这里必然抛 FormatException。
      expect(() => utf8.decode(chunk), returnsNormally,
          reason: '折行把多字节字符切断了');
    }
    final List<String> physical =
        chunks.map((List<int> b) => utf8.decode(b)).toList(growable: false);
    final List<String> continuations =
        physical.where((String l) => l.startsWith(' ')).toList(growable: false);
    expect(continuations, isNotEmpty, reason: '一条都没折，等于什么都没验');
    expect(continuations.every((String l) => !l.startsWith('  ')), isTrue,
        reason: '续行只允许**一个**前导空格');
    expect(lineStartingWith(out.text, 'SUMMARY:'), 'SUMMARY:$longName');
  });

  test('SUMMARY / LOCATION / DESCRIPTION 转义 , ; : 反斜杠 与换行', () {
    final IcsExport out = export(courses: <Course>[
      course(name: r'数据结构, 离散; 图\论', location: '逸夫楼:201', teacher: '张老师; 李'),
    ]);
    expect(lineStartingWith(out.text, 'SUMMARY:'), r'SUMMARY:数据结构\, 离散\; 图\\论');
    expect(lineStartingWith(out.text, 'LOCATION:'), r'LOCATION:逸夫楼\:201');
    final String desc = lineStartingWith(out.text, 'DESCRIPTION:');
    expect(desc, contains(r'老师：张老师\; 李'));
    expect(desc, contains(r'08\:00'), reason: '时刻里的冒号也要转义');
    expect(desc, contains(r'\n'), reason: '描述内换行要写成字面 \n');
    expect(desc.contains('\n'), isFalse, reason: '转义后不该留真换行');
  });

  test('一门 1-16 周的课 = 16 个 VEVENT，UID 稳定带周号，不用 RRULE', () {
    final Course c = course(weeks: List<int>.generate(16, (int i) => i + 1));
    final IcsExport out = export(courses: <Course>[c]);
    expect(out.eventCount, 16);
    expect('BEGIN:VEVENT'.allMatches(out.text).length, 16);
    expect('END:VEVENT'.allMatches(out.text).length, 16);
    expect(out.text, isNot(contains('RRULE')));
    for (int week = 1; week <= 16; week++) {
      expect(out.text, contains('UID:${c.uid}-$week@qingdan\r\n'));
    }
    expect(out.skippedCount, 0);
  });

  test('周次不连续（1-8、12-16）= 13 个 VEVENT', () {
    final List<int> weeks = <int>[
      ...List<int>.generate(8, (int i) => i + 1),
      ...List<int>.generate(5, (int i) => i + 12),
    ];
    final IcsExport out = export(courses: <Course>[course(weeks: weeks)]);
    expect(out.eventCount, 13);
    expect('BEGIN:VEVENT'.allMatches(out.text).length, 13);
  });

  test('DTSTART 是 TZID 本地时间：日期 = 该周周一 + (星期-1)，绝不写 Z 结尾的 UTC', () {
    final IcsExport out =
        export(courses: <Course>[course(weekday: 3, weeks: const <int>[2])]);
    final List<String> lines = out.text.split('\r\n');
    expect(lines, contains('DTSTART;TZID=Asia/Shanghai:20261028T080000'));
    expect(lines, contains('DTEND;TZID=Asia/Shanghai:20261028T094000'));
    // 只看 VEVENT 内部的时间行，并且**逐行判「不以 Z 收尾」**：
    // ① `DTSTART.*Z` 这类松散正则会被 `TZID` 里那个 Z 误伤（第一版就是这么红的）；
    // ② VTIMEZONE 的 STANDARD 块里也有一行 `DTSTART:19700101T000000`，
    //    那是时区定义的基准时刻，本来就不带 TZID，不能算进事件的账。
    final List<String> eventLines = <String>[];
    bool inEvent = false;
    for (final String line in lines) {
      if (line == 'BEGIN:VEVENT') inEvent = true;
      if (inEvent) eventLines.add(line);
      if (line == 'END:VEVENT') inEvent = false;
    }
    expect(eventLines, isNotEmpty, reason: '一个事件都没导出，下面的断言会空转');
    for (final String line in eventLines) {
      if (line.startsWith('DTSTART') || line.startsWith('DTEND')) {
        expect(line, isNot(endsWith('Z')),
            reason: 'DTSTART/DTEND 写成 UTC 会让课程整体偏 8 小时');
        expect(line, contains('TZID=Asia/Shanghai'),
            reason: '事件时间必须是带 TZID 的本地形式');
      }
    }
    expect(lines, contains('DTSTAMP:20261017T010203Z'), reason: '只有 DTSTAMP 用 UTC');
  });

  test('跨周次日期递增 7 天（第 1/2/3 周周一 = 10-19 / 10-26 / 11-02）', () {
    final IcsExport out =
        export(courses: <Course>[course(weekday: 1, weeks: const <int>[1, 2, 3])]);
    for (final String monday in <String>['20261019', '20261026', '20261102']) {
      expect(out.text, contains('DTSTART;TZID=Asia/Shanghai:${monday}T080000'));
      expect(out.text, contains('DTEND;TZID=Asia/Shanghai:${monday}T094000'));
    }
  });

  test('最小 VTIMEZONE：Asia/Shanghai 只有一个 STANDARD（无 DST）+ X-WR-TIMEZONE', () {
    final IcsExport out = export(courses: <Course>[course()]);
    expect(out.text, contains('BEGIN:VTIMEZONE'));
    expect(out.text, contains('TZID:$kIcsTzId'));
    expect(out.text, contains('X-WR-TIMEZONE:Asia/Shanghai'));
    expect('BEGIN:STANDARD'.allMatches(out.text).length, 1);
    expect(out.text, isNot(contains('BEGIN:DAYLIGHT')));
    expect(out.text, contains('TZOFFSETFROM:+0800'));
    expect(out.text, contains('TZOFFSETTO:+0800'));
    expect(out.text.trimRight().endsWith('END:VCALENDAR'), isTrue);
  });

  test('节次不在作息表的课被跳过并计数，其余课照常导出', () {
    final IcsExport out = export(courses: <Course>[
      course(name: '正常课'),
      course(name: '第 5 节的课', start: 5, end: 5), // 作息表只到 4 节
      course(name: '第 5 节的课', start: 7, end: 8), // 同名第二门：计数按门不按课名
      course(name: '跨节缺节', start: 3, end: 6), // 5、6 节缺失
    ]);
    expect(out.eventCount, 1);
    // 界面那句是「N 门课因节次不在作息表中被跳过」，所以 N 数的是**门**。
    // 真实课表里同名课很常见（数据结构两门不同教室），按课名去重会把 3 门报成 2 门。
    expect(out.skippedCount, 3);
    expect(out.skippedNames, <String>['第 5 节的课', '跨节缺节']);
    expect(out.text, contains('SUMMARY:正常课'));
    expect(out.text, isNot(contains('SUMMARY:第 5 节的课')));
    expect(out.text, isNot(contains('SUMMARY:跨节缺节')));
  });

  test('按门而非按周计数；软删课不进日历；空周次不算跳过', () {
    final IcsExport out = export(courses: <Course>[
      course(name: '回收站课', start: 9, end: 9, deleted: true),
      course(name: '没排周次', weeks: const <int>[]),
    ]);
    expect(out.eventCount, 0);
    expect(out.skippedCount, 0, reason: '空周次是「没排到周」，不是缺节次');
    expect(out.text, isNot(contains('SUMMARY:回收站课')));

    final IcsExport twice = export(courses: <Course>[
      course(name: '同一门', start: 7, end: 7, weeks: const <int>[1, 2, 3]),
    ]);
    expect(twice.skippedNames, <String>['同一门'], reason: '按门计数，不是按周');
  });

  test('0 门课程也是一份合法日历：只有头尾与时区块', () {
    final IcsExport out = export(courses: <Course>[]);
    expect(out.eventCount, 0);
    expect(out.text.split('\r\n').first, 'BEGIN:VCALENDAR');
    expect(out.text, isNot(contains('BEGIN:VEVENT')));
    expect(out.text.trimRight().endsWith('END:VCALENDAR'), isTrue);
  });

  test('描述里的周数：有原始写法照抄，否则由 weeks 还原成 1-16周', () {
    final IcsExport raw = export(courses: <Course>[
      course(
        rawWeeksText: '1-5、7-11单',
        weeks: const <int>[1, 2, 3, 4, 5, 7, 9, 11],
      ),
    ]);
    expect(lineStartingWith(raw.text, 'DESCRIPTION:'), contains('周次：1-5、7-11单'));
    final IcsExport compact = export(
        courses: <Course>[
          course(weeks: List<int>.generate(16, (int i) => i + 1)),
        ]);
    expect(lineStartingWith(compact.text, 'DESCRIPTION:'), contains('周次：1-16周'));
  });

  test('与 layoutSections 的「缺节」判定一致：跨节课程不静默截断', () {
    final SectionLayout layout = layoutSections(fourSections);
    expect(layout.missingSections(3, 6), <int>[5, 6]);
    final IcsExport out = export(courses: <Course>[course(start: 3, end: 6)]);
    expect(out.skippedCount, 1);
    expect(out.eventCount, 0);
  });
}

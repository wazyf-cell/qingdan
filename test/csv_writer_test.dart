import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/export/csv_writer.dart';
import 'package:qingdan/import/course/column_mapping.dart';
import 'package:qingdan/import/course/course_row_parser.dart';
import 'package:qingdan/import/course/schedule_file.dart';

/// CSV 导出（M6-D §9.1 / §9.3）：列头与导入映射一致、UTF-8 带 BOM，
/// 而且**写出来的文件必须能被导入侧原样读回来**——round-trip 两条都真跑。
void main() {
  Course course({
    String name = '高等数学',
    int weekday = 1,
    int start = 1,
    int end = 2,
    List<int> weeks = const <int>[1, 2, 3],
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
        semesterId: 'sem-1',
        deleted: deleted,
      );

  /// 走完整的导入入口：字节 → 表 → 列映射 → 行解析。
  ParseSummary reimport(String text, {int totalWeeks = 16}) {
    final ScheduleTable table =
        readScheduleTable(Uint8List.fromList(utf8.encode(text)));
    final ColumnMapping mapping = guessColumnMapping(table);
    expect(mapping.canImport, isTrue,
        reason: '列头没被认出来：${table.rows.first}');
    return parseCourseRows(table, mapping,
        semesterId: 'sem-1', totalWeeks: totalWeeks);
  }

  test('列头就是导入侧那份 kImportHeader（两处共用常量，不会漂移）', () {
    expect(csvColumns, kImportHeader);
    expect(scheduleRows(<Course>[course()]).first,
        <String>['课程名称', '星期', '开始节数', '结束节数', '老师', '地点', '周数']);
  });

  test('UTF-8 with BOM：前三个字节是 EF BB BF，读回后表头首格不含 BOM 字符', () {
    final String text = writeCsv(courses: <Course>[course()]);
    final List<int> bytes = utf8.encode(text);
    expect(bytes.take(3), <int>[0xEF, 0xBB, 0xBF]);
    expect(text.codeUnitAt(0), 0xFEFF);

    final ScheduleTable t = readScheduleTable(Uint8List.fromList(bytes));
    expect(t.encoding, FileEncoding.utf8Bom, reason: '探测链第一档就要认出 BOM');
    expect(t.rows.first.first, '课程名称');
  });

  test('round-trip（按格子）：readScheduleTable 读回的行数与七个字段逐格一致', () {
    final List<Course> courses = <Course>[
      course(name: '高等数学', weekday: 1, start: 1, end: 2, rawWeeksText: '1-16周'),
      course(name: '线性代数', weekday: 3, start: 3, end: 4, weeks: const <int>[2, 4, 6]),
      course(
          name: '大学英语',
          weekday: 7,
          start: 11,
          end: 12,
          weeks: const <int>[1, 3, 5],
          teacher: null,
          location: null,
          rawWeeksText: '1-15单'),
    ];
    final ScheduleTable t = readScheduleTable(
        Uint8List.fromList(utf8.encode(writeCsv(courses: courses))));
    expect(t.dataRowCount, 3);
    expect(t.columnCount, 7);
    expect(t.rows[1], <String>['高等数学', '1', '1', '2', '小明', '逸夫楼201', '1-16周']);
    // 没有 raw_weeks_text 时由 `formatWeeks` 还原成紧凑写法：[2,4,6] → 「2-6双周」。
    // 这条钉的是导出侧选定的写法；能不能回到同一组周次由下面的语义往返测试管。
    expect(t.rows[2], <String>['线性代数', '3', '3', '4', '小明', '逸夫楼201', '2-6双周']);
    expect(t.rows[3], <String>['大学英语', '7', '11', '12', '', '', '1-15单']);
  });

  test('round-trip（语义）：解析回来的课程名/星期/节次/周次与源课程完全一致，且零错误行', () {
    final List<Course> courses = <Course>[
      course(name: '高等数学', rawWeeksText: '1-5、7-11单、12-16双',
          weeks: const <int>[1, 2, 3, 4, 5, 7, 9, 11, 12, 14, 16]),
      course(name: '体育课', weekday: 5, start: 5, end: 6,
          weeks: List<int>.generate(16, (int i) => i + 1), location: '田径场'),
      course(name: '无周次课', weekday: 6, start: 1, end: 1,
          weeks: const <int>[1, 2, 3], rawWeeksText: null),
    ];
    final ParseSummary summary = reimport(writeCsv(courses: courses));
    expect(summary.errorCount, 0,
        reason: '错误行：${summary.rows.where((ParsedCourseRow r) => r.isError).map((ParsedCourseRow r) => r.messages)}');
    expect(summary.importable.length, courses.length);
    for (int i = 0; i < courses.length; i++) {
      final Course src = courses[i];
      final Course got = summary.importable[i].course!;
      expect(got.name, src.name);
      expect(got.weekday, src.weekday);
      expect(got.startSection, src.startSection);
      expect(got.endSection, src.endSection);
      expect(got.weeks, src.weeks, reason: '${src.name} 的周次没保住');
      expect(got.teacher, src.teacher);
      expect(got.location, src.location);
      // 导入侧不认导出文件里的「uid」（CSV 七列压根没这一列），它是按同一套字段
      // 重算 UID 的。所以要比的是重算结果，而不是测试里那个假的 `src.uid`。
      expect(got.uid,
          courseUidOf(
              name: src.name,
              weekday: src.weekday,
              startSection: src.startSection,
              endSection: src.endSection,
              weeks: src.weeks),
          reason: '往返改变了身份键 → 再导入会被认成另一门课');
    }
  });

  test('周数列：有 raw_weeks_text 照原文，没有则由 weeks 还原成 1-16周', () {
    expect(weeksCell(course(rawWeeksText: '1-5、7-11单', weeks: const <int>[1, 3])),
        '1-5、7-11单');
    expect(weeksCell(course(weeks: List<int>.generate(16, (int i) => i + 1))),
        '1-16周');
    expect(weeksCell(course(weeks: const <int>[2, 4, 6])), '2-6双周');
    expect(weeksCell(course(weeks: const <int>[])), '');
    // 「1-16周」这种写法必须还能被解析器接受（否则往返就断了）。
    final ParseSummary s = reimport(writeCsv(courses: <Course>[
      course(weeks: List<int>.generate(16, (int i) => i + 1)),
    ]));
    expect(s.importable.single.course!.weeks, List<int>.generate(16, (int i) => i + 1));
  });

  test('课程名/地点含逗号与引号：加引号转义后仍能原样读回', () {
    final List<Course> courses = <Course>[
      course(name: '高等数学, 上（第1课堂）', location: 'A1-201, "东楼"'),
      course(name: '形势与政策; 第二讲', weekday: 2, start: 3, end: 4, location: '主楼; 301'),
    ];
    final String text = writeCsv(courses: courses);
    expect(text.split('\r\n')[1], startsWith('"高等数学'));
    final ParseSummary summary = reimport(text);
    expect(summary.errorCount, 0);
    expect(summary.importable.map((ParsedCourseRow r) => r.course!.name).toList(),
        <String>['高等数学, 上（第1课堂）', '形势与政策; 第二讲']);
    expect(summary.importable.first.course!.location, 'A1-201, "东楼"');
  });

  test('软删课程不写出；只剩表头时读回 0 行数据', () {
    final String text = writeCsv(courses: <Course>[
      course(name: '在读的课'),
      course(name: '回收站的课', weekday: 3, start: 5, end: 5, deleted: true),
    ]);
    expect(text, contains('在读的课'));
    expect(text, isNot(contains('回收站的课')));

    final ScheduleTable onlyHeader = readScheduleTable(
        Uint8List.fromList(utf8.encode(writeCsv(courses: <Course>[]))));
    expect(onlyHeader.rows.length, 1);
    expect(onlyHeader.dataRowCount, 0);
    expect(reimport(writeCsv(courses: <Course>[])).rows, isEmpty);
  });

  test('行尾 CRLF 且末尾留一个换行（Excel / 文本编辑器友好）', () {
    final String text = writeCsv(courses: <Course>[course(), course(name: 'B')]);
    expect(text.endsWith('\r\n'), isTrue);
    expect(text.contains('\n\n'), isFalse);
    expect(text.split('\r\n').length, 4); // 表头 + 2 行 + 末尾换行后的空段
  });
}

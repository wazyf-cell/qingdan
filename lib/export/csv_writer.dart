// 课表 → CSV 文本（M6-D §9.1）。**纯函数，只产字符串、不碰平台**。
//
// 列头直接复用导入侧的 [kImportHeader]（`lib/import/course/schedule_file.dart`），
// 两处共用同一份常量才不会漂移；写出的内容必须能被 `readScheduleTable` +
// `guessColumnMapping` + `parseCourseRows` **原样读回**（test/csv_writer_test.dart 跑真往返）。
//
// 编码：**UTF-8 with BOM**（Windows 的 Excel 不带 BOM 会按 GBK 显示成乱码）。
// 导入侧的探测链第一档就认 BOM（`FileEncoding.utf8Bom`）。

import 'package:csv/csv.dart';

import '../domain/course.dart';
import '../domain/week_rule.dart';
import '../import/course/schedule_file.dart';

/// UTF-8 BOM（码位 U+FEFF）。`utf8.encode` 后就是 `EF BB BF` 三个字节。
/// 用码位而不是字面量，避免源码里肉眼不可见（同 `_stripBom` 的理由）。
const String kUtf8Bom = '\uFEFF';

/// 一行七列：**就是导入侧那份 [kImportHeader]**，别名只为让导出层读起来顺。
const List<String> csvColumns = kImportHeader;

/// 表头 + 数据行（未删除的课程各一行）。单独暴露，便于界面统计与单测逐格断言。
List<List<String>> scheduleRows(List<Course> courses) => <List<String>>[
      csvColumns,
      for (final Course c in courses)
        if (!c.deleted)
          <String>[
            c.name,
            '${c.weekday}',
            '${c.startSection}',
            '${c.endSection}',
            c.teacher ?? '',
            c.location ?? '',
            weeksCell(c),
          ],
    ];

/// 「周数」列：有原始写法就照抄，没有则由具体周次还原成 `1-16周` 这种紧凑写法。
///
/// 两种写法都在导入解析器的接受范围内（`parseWeekRule` 会剥掉「周」字），
/// 所以这一列能保证往返。
String weeksCell(Course c) {
  final String raw = c.rawWeeksText?.trim() ?? '';
  if (raw.isNotEmpty) return raw;
  final String compact = formatWeeks(c.weeks);
  return compact.isEmpty ? '' : '$compact周';
}

/// 导出 CSV 文本（带 BOM、CRLF 行尾）。
///
/// 含 `,` `"` 换行的单元格由 `csv` 包按 RFC 4180 加引号转义，读回时自动去引号，
/// 因此课程名/地点里带逗号也不会串列。
String writeCsv({required List<Course> courses}) =>
    Csv(addBom: true).encode(scheduleRows(courses)) + '\r\n';

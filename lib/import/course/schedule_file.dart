import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:enough_convert/gbk.dart';
import 'package:excel/excel.dart';

import 'wakeup_schedule_file.dart';

/// 课表文件的读取与编码探测（导入向导步骤 1，设计稿 §3.1）。
///
/// 只负责「字节 → 字符串行列」，**不做任何业务判断**（列映射在
/// column_mapping.dart，行解析在 course_row_parser.dart）。
///
/// xlsx 的解析语义参考 WakeUp 的 Excel 导入路径（`ImportViewModel.kt:734-742`
/// 的编码二选一），本项目改为显式探测链且**结果可展示可切换**（§3.3.3）。

/// 探测到的文本编码。xlsx 是 zip+UTF-8 XML，不走编码链，故 [FileEncoding.xlsx]。
enum FileEncoding { xlsx, utf8, utf8Bom, gbk }

/// 读取失败（空文件 / 空 sheet / 编码全不匹配）。
class ScheduleFileException implements Exception {
  const ScheduleFileException(this.message);
  final String message;

  @override
  String toString() => '课表文件读取失败：$message';
}

/// 一张原始表：行列都是**已 trim 的字符串**（xlsx 里数字常是共享字符串，
/// 见 `相关来源或素材/课表模板.xlsx` 实测，所以统一按文本取，数值转换留给上层）。
class ScheduleTable {
  const ScheduleTable({
    required this.rows,
    required this.encoding,
    this.sheetName,
  });

  final List<List<String>> rows;
  final FileEncoding encoding;
  final String? sheetName;

  int get columnCount =>
      rows.fold(0, (int m, List<String> r) => r.length > m ? r.length : m);

  /// 数据行数（不含表头，也不含空行）。§3.2 的「检测到 N 列、M 行数据」用它。
  int get dataRowCount {
    final int filled = rows.where(_hasContent).length;
    return (rows.isNotEmpty && _hasContent(rows.first)) ? filled - 1 : filled;
  }

  bool get isEmpty => rows.every((List<String> r) => !_hasContent(r));

  static bool _hasContent(List<String> row) =>
      row.any((String c) => c.trim().isNotEmpty);
}

/// 各抓取/解析源统一产出的表头：**这七个名字是列猜测器认得的**（见
/// `column_mapping.dart` 的规则表），所以用户进向导就是「已识别」，零重映射。
/// 节次必须是**两列纯数字**——`course_row_parser._parseInt` 用 `double.tryParse`，
/// 写成 `1-2节` 会整行判 ✗。
const List<String> kImportHeader = <String>[
  '课程名称', '星期', '开始节数', '结束节数', '老师', '地点', '周数',
];

/// 读 [bytes]。[fileName] 只作提示，**真实类型按魔术字节判**（用户常把
/// xlsx 改名成 .csv 或反之）。[forceEncoding] 用于界面上手动切换编码重读。
ScheduleTable readScheduleTable(Uint8List bytes,
    {String? fileName, FileEncoding? forceEncoding}) {
  if (bytes.isEmpty) throw const ScheduleFileException('文件为 0 字节');
  if (forceEncoding == null && isWakeupSchedule(bytes)) {
    return readWakeupSchedule(bytes);
  }
  final bool looksLikeXlsx =
      bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  if (forceEncoding == FileEncoding.xlsx || (looksLikeXlsx && forceEncoding == null)) {
    return _readXlsx(bytes);
  }
  return _readCsv(bytes, forceEncoding);
}

ScheduleTable _readXlsx(Uint8List bytes) {
  final Excel book;
  try {
    book = Excel.decodeBytes(bytes);
  } catch (e) {
    throw ScheduleFileException('xlsx 无法解析（$e）');
  }
  if (book.sheets.isEmpty) {
    throw const ScheduleFileException('文件里没有任何工作表');
  }
  // 取第一个**有内容**的 sheet（用户常留一个空 Sheet1 在前）。
  for (final MapEntry<String, Sheet> entry in book.sheets.entries) {
    final Sheet sheet = entry.value;
    final List<List<String>> rows = <List<String>>[
      for (int r = 0; r < sheet.maxRows; r++)
        <String>[
          for (final Data? cell in sheet.row(r)) _cellText(cell),
        ],
    ];
    if (rows.any(ScheduleTable._hasContent)) {
      return ScheduleTable(
          rows: rows, encoding: FileEncoding.xlsx, sheetName: entry.key);
    }
  }
  throw const ScheduleFileException('所有工作表都是空的');
}

/// 单元格 → 文本。数字/日期都取 `toString()`，由上层再做数值归一；
/// Excel 把 `3-15` 自动转成**真日期**的情况也走这条路（`A月B日` 规则兜底）。
String _cellText(Data? cell) {
  final CellValue? value = cell?.value;
  if (value == null) return '';
  return value.toString().trim();
}

ScheduleTable _readCsv(Uint8List bytes, FileEncoding? force) {
  final FileEncoding chosen = force ?? detectEncoding(bytes);
  final String text;
  try {
    text = switch (chosen) {
      FileEncoding.xlsx => throw const ScheduleFileException('xlsx 不走编码链'),
      FileEncoding.utf8Bom => utf8.decode(bytes.sublist(3)),
      FileEncoding.utf8 => utf8.decode(bytes),
      FileEncoding.gbk => gbk.decode(bytes),
    };
  } on ScheduleFileException {
    rethrow;
  } on FormatException catch (e) {
    // 解码失败要说清可以切换编码，而不是抛一个裸的 FormatException 让界面显示天书。
    throw ScheduleFileException(
        '按 ${describeEncoding(chosen)} 解码失败（${e.message}），请在界面上切换编码重读');
  }
  final List<List<dynamic>> parsed = Csv().decode(_stripBom(text));
  final List<List<String>> rows = <List<String>>[
    for (final List<dynamic> row in parsed)
      <String>[for (final dynamic cell in row) '${cell ?? ''}'.trim()],
  ];
  if (rows.isEmpty || !rows.any(ScheduleTable._hasContent)) {
    throw const ScheduleFileException('CSV 内容为空');
  }
  return ScheduleTable(rows: rows, encoding: chosen);
}

/// 探测顺序（§3.1 定死）：**UTF-8 带 BOM → UTF-8 → GBK**。
///
/// 判据是「严格解码能否成功」而不是「中文占比」：UTF-8 的字节序列约束很强，
/// GBK 文本几乎必然在非法位置触发 UTF-8 异常，反之 UTF-8 文本用 GBK 解一定乱码
/// 但不会报错——所以 UTF-8 必须先试。
FileEncoding detectEncoding(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return FileEncoding.utf8Bom;
  }
  try {
    utf8.decode(bytes);
    return FileEncoding.utf8;
  } on FormatException {
    return FileEncoding.gbk;
  }
}

/// 剥掉解码后残留的 BOM 字符（U+FEFF）。用码位而不是字面量，避免肉眼不可见。
String _stripBom(String text) =>
    text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF
        ? text.substring(1)
        : text;

/// 给界面展示「已按 GBK 读取」这类结论（§3.1 要求显式展示且可切换）。
String describeEncoding(FileEncoding e) => switch (e) {
      FileEncoding.xlsx => 'xlsx（内部 UTF-8）',
      FileEncoding.utf8Bom => 'UTF-8（带 BOM）',
      FileEncoding.utf8 => 'UTF-8',
      FileEncoding.gbk => 'GBK',
    };

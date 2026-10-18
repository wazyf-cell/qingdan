import 'schedule_file.dart';

/// 列映射（导入向导步骤 2，设计稿 §3.2）。
///
/// 两级策略：**表头关键词字典**优先，认不出才用**内容启发式**。
/// 与 WakeUp 的关键差别：WakeUp 把列下标硬编码 0-6、列序错了就**静默错位导入**
/// （`CSVParser.kt:50-57`），本项目要求必需字段齐备、错位拒绝（§3.3.3）。

/// 文件里的一列可以对应到的目标字段。
enum CourseField {
  name,
  weekday,
  startSection,
  endSection,
  teacher,
  location,
  weeks,
  ignore,
}

String describeField(CourseField f) => switch (f) {
      CourseField.name => '课程名称',
      CourseField.weekday => '星期',
      CourseField.startSection => '开始节数',
      CourseField.endSection => '结束节数',
      CourseField.teacher => '老师 (可选)',
      CourseField.location => '地点 (可选)',
      CourseField.weeks => '周数',
      CourseField.ignore => '忽略',
    };

/// 猜中来源，界面上对应 ✓ / ⚠ / ✗ 三档置信色。
enum GuessConfidence { header, content, none }

/// 文件某一列的映射结果。[field] 可被用户改（下拉框）。
class ColumnAssignment {
  ColumnAssignment({
    required this.index,
    required this.header,
    required this.field,
    required this.confidence,
  });

  final int index;
  final String header;
  CourseField field;

  /// 猜中来源；内容启发式命中时在 [guessColumnMapping] 里回填。
  GuessConfidence confidence;
}

class ColumnMapping {
  ColumnMapping(this.columns);

  final List<ColumnAssignment> columns;

  /// 必需字段：缺任何一个都停在步骤 2（2026-10-10 定案：不硬要 7 列，按映射判定）。
  static const List<CourseField> required = <CourseField>[
    CourseField.name,
    CourseField.weekday,
    CourseField.startSection,
    CourseField.endSection,
    CourseField.weeks,
  ];

  int? indexOf(CourseField field) {
    for (final ColumnAssignment c in columns) {
      if (c.field == field) return c.index;
    }
    return null;
  }

  List<CourseField> missingRequired() =>
      required.where((CourseField f) => indexOf(f) == null).toList();

  bool get canImport => missingRequired().isEmpty;

  /// 用户手动改映射。目标字段已被别的列占用时，**把那一列自动改为忽略**并返回
  /// 提示文案（§3.2：每个目标字段只能被映射一次）。
  String? assign(int index, CourseField field) {
    ColumnAssignment? target;
    for (final ColumnAssignment c in columns) {
      if (c.index == index) target = c;
    }
    if (target == null) return null;
    String? notice;
    if (field != CourseField.ignore) {
      for (final ColumnAssignment c in columns) {
        if (c.index != index && c.field == field) {
          c.field = CourseField.ignore;
          notice = '「${describeField(field)}」已由第 ${c.index + 1} 列映射，'
              '该列已改为忽略';
        }
      }
    }
    target.field = field;
    return notice;
  }
}

/// 表头关键词字典。**顺序即优先级**：「星期」必须排在「周」之前，
/// 否则「星期」列会被 `周数|周次` 抢走（§3.2 点名的最容易错处）。
final List<List<Object>> _headerRules = <List<Object>>[
  <Object>[RegExp(r'课程名称|课程|课名|name', caseSensitive: false), CourseField.name],
  <Object>[RegExp(r'星期|周几|weekday|day', caseSensitive: false), CourseField.weekday],
  <Object>[RegExp(r'开始.?节|起.?节|起始节|start', caseSensitive: false), CourseField.startSection],
  <Object>[RegExp(r'结束.?节|止.?节|终止节|end', caseSensitive: false), CourseField.endSection],
  <Object>[RegExp(r'老师|教师|讲师|teacher', caseSensitive: false), CourseField.teacher],
  <Object>[RegExp(r'地点|教室|位置|location|room', caseSensitive: false), CourseField.location],
  <Object>[RegExp(r'周数|周次|weeks?', caseSensitive: false), CourseField.weeks],
];

final RegExp _weekLike =
    RegExp(r'^[\d、,，;；~\-—–到至单双月日第周\s·/]+$');

/// 猜列：先按表头字典，未覆盖的必需字段再用内容启发式补。
ColumnMapping guessColumnMapping(ScheduleTable table) {
  if (table.rows.isEmpty) return ColumnMapping(<ColumnAssignment>[]);
  final List<String> header = table.rows.first;
  final List<List<String>> body = table.rows.skip(1).toList();
  final int width = table.columnCount;

  final List<ColumnAssignment> columns = <ColumnAssignment>[];
  final Set<CourseField> taken = <CourseField>{};
  for (int i = 0; i < width; i++) {
    final String h = i < header.length ? header[i] : '';
    CourseField field = CourseField.ignore;
    GuessConfidence confidence = GuessConfidence.none;
    for (final List<Object> rule in _headerRules) {
      if (h.isNotEmpty && (rule[0] as RegExp).hasMatch(h)) {
        final CourseField candidate = rule[1] as CourseField;
        if (!taken.contains(candidate)) {
          field = candidate;
          confidence = GuessConfidence.header;
          break;
        }
      }
    }
    if (field != CourseField.ignore) taken.add(field);
    columns.add(ColumnAssignment(
        index: i, header: h, field: field, confidence: confidence));
  }

  // 第二级：必需字段仍有缺口时，用内容启发式在未认领的列里猜。
  for (final CourseField missing in ColumnMapping.required) {
    if (columns.any((ColumnAssignment c) => c.field == missing)) continue;
    final ColumnAssignment? best = _bestContentMatch(columns, body, missing);
    if (best != null) {
      best.field = missing;
      best.confidence = GuessConfidence.content;
    }
  }
  return ColumnMapping(columns);
}

/// 内容启发式：对每列前 5 行打分（§3.2 第二级）。
ColumnAssignment? _bestContentMatch(List<ColumnAssignment> columns,
    List<List<String>> body, CourseField field) {
  ColumnAssignment? best;
  int bestScore = 0;
  for (final ColumnAssignment c in columns) {
    if (c.field != CourseField.ignore) continue;
    final List<String> values = <String>[
      for (final List<String> row in body.take(5))
        if (c.index < row.length) row[c.index],
    ];
    final int score = _scoreFor(values, field);
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  return bestScore >= 2 ? best : null;
}

int _scoreFor(List<String> values, CourseField field) {
  if (values.isEmpty) return 0;
  final List<String> filled =
      values.where((String v) => v.trim().isNotEmpty).toList();
  if (filled.isEmpty) return 0;
  bool allNumIn(int lo, int hi) => filled.every((String v) {
        final int? n = int.tryParse(v.trim());
        return n != null && n >= lo && n <= hi;
      });
  return switch (field) {
    // 星期：值全在 1~7。
    CourseField.weekday => allNumIn(1, 7) ? filled.length : 0,
    // 节次：值全在 1~20 的整数（起始与结束共用该判据）。
    CourseField.startSection ||
    CourseField.endSection => allNumIn(1, 20) ? filled.length : 0,
    CourseField.weeks => filled
            .every((String v) => v.contains(_weekLike) && v.length > 1)
        ? filled.length
        : 0,
    // 课名：自由文本（含非数字字符）。
    CourseField.name => filled
            .every((String v) => RegExp(r'\D').hasMatch(v.trim()))
        ? filled.length
        : 0,
    _ => 0,
  };
}

import '../../domain/course.dart';
import '../../domain/course_conflict.dart';
import '../../domain/course_uid.dart';
import '../../domain/week_rule.dart';
import 'column_mapping.dart';
import 'schedule_file.dart';

// 行解析（导入向导步骤 4 的核心，设计稿 §3.4 的策略表逐条落地）。
//
// 三态：**错误（✗）必须被修正或忽略才能继续**，警告（⚠）可带病通过（§3.1 闸门）。
// 本文件不写库、不弹窗，只产出「行模型」，供桌面表格与移动卡片共用
// （`方案设计-课表域-界面.md` §4.3 的形态决策）。

/// 一行的状态。顺序即严重度：error > warning > ok。
enum RowStatus { ok, warning, error }

/// 一行文件的解析结果。[course] 仅在非 error 时有值。
class ParsedCourseRow {
  ParsedCourseRow({
    required this.rowNumber,
    required this.cells,
    required this.status,
    this.messages = const <String>[],
    this.course,
  });

  /// 文件里的行号（1 起），校正界面用它定位。
  final int rowNumber;
  final List<String> cells;
  RowStatus status;
  final List<String> messages;
  Course? course;

  bool get isError => status == RowStatus.error;
}

/// 一次解析的汇总（结果页与闸门判断用）。
class ParseSummary {
  ParseSummary(this.rows) {
    for (final ParsedCourseRow r in rows) {
      switch (r.status) {
        case RowStatus.error:
          errorCount++;
        case RowStatus.warning:
          warningCount++;
        case RowStatus.ok:
          okCount++;
      }
    }
  }

  final List<ParsedCourseRow> rows;
  int okCount = 0;
  int warningCount = 0;
  int errorCount = 0;

  /// 闸门：还有未处理的错误行就不许落库（§3.1）。
  bool get canImport => errorCount == 0;
  List<ParsedCourseRow> get importable =>
      rows.where((ParsedCourseRow r) => !r.isError).toList(growable: false);
}

/// 跨行「时间重叠」提示（§3.4：同槽两条课**允许落库**，只在预览里黄字提示；
/// §4.3 规则 7 要求解释必须点名冲突对象，不写「存在冲突」这种废话）。
///
/// 只看槽位不看周次交集——两门课分周上也是重叠，这正是样本第 2、3 行的情形。
void annotateOverlaps(List<ParsedCourseRow> rows) {
  final Map<int, List<ParsedCourseRow>> byDay = <int, List<ParsedCourseRow>>{};
  for (final ParsedCourseRow r in rows) {
    final Course? c = r.course;
    if (c == null) continue; // 错误行没有课，也不参与重叠判定
    byDay.putIfAbsent(c.weekday, () => <ParsedCourseRow>[]).add(r);
  }
  byDay.forEach((int weekday, List<ParsedCourseRow> group) {
    final List<Course> courses =
        <Course>[for (final ParsedCourseRow r in group) r.course!];
    for (final OverlapGroup g in groupByOverlap(courses)) {
      if (g.courses.length < 2) continue;
      for (final ParsedCourseRow r in group) {
        final Course self = r.course!;
        final String others = g.courses
            .where((Course o) => o != self)
            .map((Course o) => '「${o.name}」')
            .join('、');
        r.status = r.status == RowStatus.error
            ? RowStatus.error
            : RowStatus.warning;
        r.messages.add('时间重叠：与$others '
            '${weekdayName(weekday)} 第${self.startSection}-${self.endSection}节重叠');
      }
    }
  });
}

/// 星期数字 → 中文名（与校正界面、周视图同一套叫法）。
String weekdayName(int weekday) => const <String>[
      '周一', '周二', '周三', '周四', '周五', '周六', '周日',
    ][weekday - 1];

/// 星期文本 → 1~7（§3.4：`周日/周天/星期日/Sun` 都要收）。
const Map<String, int> _weekdayNames = <String, int>{
  '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6,
  '日': 7, '天': 7,
  'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
};

ParseSummary parseCourseRows(
  ScheduleTable table,
  ColumnMapping mapping, {
  required String semesterId,
  required int totalWeeks,
}) {
  final List<ParsedCourseRow> rows = <ParsedCourseRow>[];
  for (int i = 1; i < table.rows.length; i++) {
    final List<String> cells = table.rows[i];
    if (!cells.any((String c) => c.trim().isNotEmpty)) continue; // 空行直接跳过
    rows.add(_parseRow(i + 1, cells, mapping,
        semesterId: semesterId, totalWeeks: totalWeeks));
  }
  annotateOverlaps(rows);
  return ParseSummary(rows);
}

ParsedCourseRow _parseRow(
  int rowNumber,
  List<String> cells,
  ColumnMapping mapping, {
  required String semesterId,
  required int totalWeeks,
}) {
  final List<String> messages = <String>[];
  bool hasError = false;
  bool hasWarning = false;

  String cell(CourseField field) {
    final int? idx = mapping.indexOf(field);
    return (idx == null || idx >= cells.length) ? '' : cells[idx].trim();
  }

  void fail(String message) {
    messages.add(message);
    hasError = true;
  }

  void warn(String message) {
    messages.add(message);
    hasWarning = true;
  }

  final String name = cell(CourseField.name);
  if (name.isEmpty) fail('课程名称为空');

  // 星期：先挡「星期和节次挤在一列」的变体（首版明确不做，§3.2）。
  final String weekdayText = cell(CourseField.weekday);
  int? weekday;
  if (RegExp(r'^周[一二三四五六日天].*[0-9]').hasMatch(weekdayText)) {
    fail('检测到星期和节次在同一列（「$weekdayText」），请改用标准模板');
  } else {
    weekday = _parseWeekday(weekdayText, warn, fail);
  }

  final int? start = _parseInt(cell(CourseField.startSection), '开始节数', fail);
  final int? end = _parseInt(cell(CourseField.endSection), '结束节数', fail);
  if (start != null && end != null) {
    if (start < 1 || end < 1) {
      fail('节次必须从 1 开始（$start-$end）');
    } else if (start > end) {
      // 报错不交换：静默钳位会显示成一节莫名其妙的课（§3.3.3）。
      fail('起始节 $start 大于结束节 $end，请核对文件');
    }
  }

  final String weeksText = cell(CourseField.weeks);
  List<int>? weeks;
  try {
    final WeekRuleOutcome outcome =
        parseWeekRule(weeksText, totalWeeks: totalWeeks);
    weeks = outcome.weeks;
    if (outcome.warning == WeekRuleWarning.emptyFilledAllWeeks) {
      warn('该行周次为空，已按全学期（1-$totalWeeks 周）处理');
    }
    final int overflow =
        weeks.where((int w) => w > totalWeeks).length;
    if (overflow > 0) {
      // 绝不静默截断，交用户在 §3.4 的三选一里决定。
      warn('有 $overflow 个周次超出学期总周数 $totalWeeks');
    }
  } on WeekRuleFormatException catch (e) {
    fail('周次「$weeksText」解析失败：${e.reason}');
  }

  if (hasError) {
    return ParsedCourseRow(
      rowNumber: rowNumber,
      cells: cells,
      status: RowStatus.error,
      messages: messages,
    );
  }

  final Course course = Course(
    id: '',
    uid: courseUidOf(
      name: name,
      weekday: weekday!,
      startSection: start!,
      endSection: end!,
      weeks: weeks!,
    ),
    name: name,
    teacher: Course.blankToNull(cell(CourseField.teacher)),
    location: Course.blankToNull(cell(CourseField.location)),
    weekday: weekday,
    startSection: start,
    endSection: end,
    weeks: weeks,
    rawWeeksText: weeksText.isEmpty ? null : weeksText,
    semesterId: semesterId,
    origin: CourseOrigin.import,
  );
  return ParsedCourseRow(
    rowNumber: rowNumber,
    cells: cells,
    status: hasWarning ? RowStatus.warning : RowStatus.ok,
    messages: messages,
    course: course,
  );
}

int? _parseWeekday(
    String text, void Function(String) warn, void Function(String) fail) {
  if (text.isEmpty) {
    fail('星期为空');
    return null;
  }
  final int? numeric = int.tryParse(text);
  if (numeric != null) {
    if (numeric == 0) {
      // WakeUp 惯例里周日可能是 0 或 7，两个都收（§3.4）。
      warn('星期为 0，已按周日处理');
      return 7;
    }
    if (numeric < 0 || numeric > 7) {
      fail('星期「$text」不在 0~7 范围内');
      return null;
    }
    return numeric;
  }
  // 依次尝试：整词命中 → 剥前缀 → 再剥尾缀。「周日」剥掉「周」就是「日」，
  // 不能再把尾缀「日」也剥掉，否则查表必然落空。
  final String lower = text.trim().toLowerCase();
  int? named = _weekdayNames[lower];
  if (named == null) {
    final String stripped =
        lower.replaceFirst(RegExp(r'^(星期|周|礼拜)'), '');
    named = _weekdayNames[stripped] ??
        _weekdayNames[stripped.replaceAll(RegExp(r'[日号]$'), '')];
  }
  if (named == null) fail('无法识别星期「$text」');
  return named;
}

int? _parseInt(String text, String label, void Function(String) fail) {
  if (text.isEmpty) {
    fail('$label 为空');
    return null;
  }
  final double? asDouble = double.tryParse(text);
  if (asDouble == null) {
    fail('$label「$text」不是数字');
    return null;
  }
  return asDouble.round();
}

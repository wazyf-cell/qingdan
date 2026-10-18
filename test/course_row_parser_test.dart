import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/import/course/column_mapping.dart';
import 'package:qingdan/import/course/course_row_parser.dart';
import 'package:qingdan/import/course/schedule_file.dart';

/// 行解析三态（导入向导步骤 4，§3.4 策略表 + §3.1 落库闸门）。
void main() {
  const List<String> header = <String>[
    '课程名称', '星期', '开始节数', '结束节数', '老师', '地点', '周数',
  ];

  ParseSummary parse(List<List<String>> body, {int totalWeeks = 16}) {
    final ScheduleTable t = ScheduleTable(
        rows: <List<String>>[header, ...body], encoding: FileEncoding.utf8);
    return parseCourseRows(t, guessColumnMapping(t),
        semesterId: 'sem1', totalWeeks: totalWeeks);
  }

  List<String> row({
    String name = '高等数学',
    String weekday = '1',
    String start = '1',
    String end = '2',
    String teacher = '小明',
    String location = '逸夫楼201',
    String weeks = '1-5',
  }) =>
      <String>[name, weekday, start, end, teacher, location, weeks];

  test('样本三行：全部可导入，同槽不同周次的两门课都保住且 UID 不同', () {
    final ParseSummary s = parse(<List<String>>[
      row(name: '高等数学', weekday: '1', weeks: '1-5、7-11单、12-16双'),
      row(name: '线性代数', weekday: '2', start: '3', end: '4', weeks: '1-16'),
      row(name: '大学英语', weekday: '2', start: '3', end: '4', weeks: '2、5、8'),
    ]);
    expect(s.errorCount, 0);
    expect(s.canImport, isTrue);
    expect(s.importable, hasLength(3));
    // §3.4：同槽两条课**允许落库**，但必须黄字提示，且点名冲突对象（§4.3 规则 7）。
    expect(s.warningCount, 2, reason: '线代与大英互相重叠，两条都要标 ⚠');
    final ParsedCourseRow eng = s.rows
        .firstWhere((ParsedCourseRow r) => r.course!.name == '大学英语');
    expect(eng.messages.join(), contains('与「线性代数」'));
    expect(eng.messages.join(), contains('周二 第3-4节'));
    final List<String> uids = s.importable
        .map((ParsedCourseRow r) => r.course!.uid)
        .toList();
    expect(uids.toSet().length, 3, reason: '同槽不同周次不得算成同一门课');
    final Course math = s.importable.first.course!;
    expect(math.weeks, <int>[1, 2, 3, 4, 5, 7, 9, 11, 12, 14, 16]);
    expect(math.origin, CourseOrigin.import);
    expect(math.rawWeeksText, '1-5、7-11单、12-16双'); // 原样留作展示
    expect(math.semesterId, 'sem1');
  });

  test('起始节大于结束节 → 错误，且不自动交换', () {
    final ParseSummary s = parse(<List<String>>[row(start: '5', end: '3')]);
    expect(s.errorCount, 1);
    expect(s.canImport, isFalse, reason: '闸门：有错误行不许落库');
    expect(s.rows.single.messages.single, contains('大于结束节'));
  });

  test('星期 0 按周日处理并警告；8 直接报错', () {
    final ParseSummary zero = parse(<List<String>>[row(weekday: '0')]);
    expect(zero.rows.single.status, RowStatus.warning);
    expect(zero.importable.single.course!.weekday, 7);

    final ParseSummary eight = parse(<List<String>>[row(weekday: '8')]);
    expect(eight.errorCount, 1);
    expect(eight.rows.single.messages.single, contains('不在 0~7'));
  });

  test('星期写成「周日」「星期一」也能认', () {
    expect(parse(<List<String>>[row(weekday: '周日')]).importable.single.course!.weekday, 7);
    expect(parse(<List<String>>[row(weekday: '星期三')]).importable.single.course!.weekday, 3);
  });

  test('周次整列为空 → 按全学期填充并警告（可带病通过）', () {
    final ParseSummary s = parse(<List<String>>[row(weeks: '')]);
    expect(s.rows.single.status, RowStatus.warning);
    expect(s.canImport, isTrue);
    expect(s.importable.single.course!.weeks,
        List<int>.generate(16, (int i) => i + 1));
  });

  test('周次超出学期总周数 → 警告而非静默截断', () {
    final ParseSummary s =
        parse(<List<String>>[row(weeks: '1-20')], totalWeeks: 16);
    expect(s.rows.single.status, RowStatus.warning);
    expect(s.rows.single.messages.single, contains('超出学期总周数'));
    expect(s.importable.single.course!.weeks, hasLength(20));
  });

  test('周次里有乱段 → 错误并带上原文，供校正界面定位', () {
    final ParseSummary s = parse(<List<String>>[row(weeks: '1-5、约、7-11单')]);
    expect(s.errorCount, 1);
    expect(s.rows.single.messages.single, contains('约'));
  });

  test('星期和节次挤在一列 → 明确报错（首版不做半吊子解析）', () {
    final ParseSummary s = parse(<List<String>>[row(weekday: '周一1-2节')]);
    expect(s.errorCount, 1);
    expect(s.rows.single.messages.single, contains('同一列'));
  });

  test('老师/地点为空是正常情况，不算警告（大学常写「待定」）', () {
    final ParseSummary s =
        parse(<List<String>>[row(teacher: '', location: '   ')]);
    expect(s.rows.single.status, RowStatus.ok);
    expect(s.importable.single.course!.teacher, isNull);
    expect(s.importable.single.course!.location, isNull);
  });

  test('完全空行被跳过，不进校正列表', () {
    final ParseSummary s = parse(<List<String>>[
      row(),
      <String>['', '', '', '', '', '', ''],
    ]);
    expect(s.rows, hasLength(1));
  });

  test('混合批次：错误行被闸门拦下，其余照常可导入', () {
    // 三行刻意排在**不同槽位**：本用例验的是三态计数与闸门，不是重叠警告
    // （重叠由上面「样本三行」那条专门管）。同槽会被额外标 ⚠，计数就串味了。
    final ParseSummary s = parse(<List<String>>[
      row(name: '好课', weekday: '1'),
      row(name: '坏课', weekday: '2', start: '9', end: '2'),
      row(name: '警告课', weekday: '3', weeks: ''),
    ]);
    expect(s.okCount, 1);
    expect(s.warningCount, 1);
    expect(s.errorCount, 1);
    expect(s.canImport, isFalse);
    expect(
        s.importable.map((ParsedCourseRow r) => r.course!.name).toList(),
        <String>['好课', '警告课']);
  });
}

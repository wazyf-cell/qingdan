import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/import/course/column_mapping.dart';
import 'package:qingdan/import/course/schedule_file.dart';

/// 列映射（导入向导步骤 2）。
///
/// 核心立场：WakeUp 把列下标硬编码 0-6、列序错了就**静默错位导入**
/// （`CSVParser.kt:50-57`），本项目必须按表头/内容判定，错位拒绝。
void main() {
  ScheduleTable table(List<List<String>> rows) =>
      ScheduleTable(rows: rows, encoding: FileEncoding.utf8);

  const List<String> standardHeader = <String>[
    '课程名称', '星期', '开始节数', '结束节数', '老师', '地点', '周数',
  ];
  const List<String> row1 = <String>[
    '高等数学', '1', '1', '2', '小明', '逸夫楼201', '1-5',
  ];

  CourseField fieldOf(ColumnMapping m, int index) =>
      m.columns.firstWhere((ColumnAssignment c) => c.index == index).field;

  test('标准 7 列表头：五个必需字段齐备，置信为表头命中', () {
    final ColumnMapping m =
        guessColumnMapping(table(<List<String>>[standardHeader, row1]));
    expect(m.canImport, isTrue, reason: m.missingRequired().join(','));
    expect(fieldOf(m, 0), CourseField.name);
    expect(fieldOf(m, 1), CourseField.weekday);
    expect(fieldOf(m, 2), CourseField.startSection);
    expect(fieldOf(m, 3), CourseField.endSection);
    expect(fieldOf(m, 4), CourseField.teacher);
    expect(fieldOf(m, 5), CourseField.location);
    expect(fieldOf(m, 6), CourseField.weeks);
    expect(m.columns.every((ColumnAssignment c) =>
        c.confidence == GuessConfidence.header), isTrue);
  });

  test('「星期」必须优先于「周」被匹配（§3.2 点名的最容易错处）', () {
    final ColumnMapping m = guessColumnMapping(table(<List<String>>[
      <String>['课程名称', '星期', '起始节', '终止节', '周次'],
      <String>['高数', '1', '1', '2', '1-5'],
    ]));
    expect(fieldOf(m, 1), CourseField.weekday);
    expect(fieldOf(m, 4), CourseField.weeks);
    // 必须是表头命中，而不是靠内容启发式兜回来的——否则说明字典顺序错了。
    expect(m.columns[1].confidence, GuessConfidence.header);
    expect(m.columns[4].confidence, GuessConfidence.header);
  });

  test('「周几」与「周次」同时出现时各归各位（真正的碰撞点）', () {
    final ColumnMapping m = guessColumnMapping(table(<List<String>>[
      <String>['课程名称', '周几', '开始节数', '结束节数', '周次'],
      <String>['高数', '1', '1', '2', '1-5'],
    ]));
    expect(fieldOf(m, 1), CourseField.weekday,
        reason: '「周几」是星期，不能被「周」字头的周数规则抢走');
    expect(fieldOf(m, 4), CourseField.weeks);
    expect(m.columns[1].confidence, GuessConfidence.header);
    expect(m.columns[4].confidence, GuessConfidence.header);
  });

  test('列序打乱仍按表头映射，不按位置硬套（错位拒绝）', () {
    final ColumnMapping m = guessColumnMapping(table(<List<String>>[
      <String>['周数', '老师', '课程名称', '地点', '星期', '结束节数', '开始节数'],
      <String>['1-5', '小明', '高等数学', '逸夫楼201', '1', '2', '1'],
    ]));
    expect(fieldOf(m, 0), CourseField.weeks);
    expect(fieldOf(m, 2), CourseField.name);
    expect(fieldOf(m, 4), CourseField.weekday);
    expect(fieldOf(m, 6), CourseField.startSection);
  });

  test('多余列自动忽略，不影响导入', () {
    final ColumnMapping m = guessColumnMapping(table(<List<String>>[
      <String>[...standardHeader, '备注'],
      <String>[...row1, '换教室了'],
    ]));
    expect(fieldOf(m, 7), CourseField.ignore);
    expect(m.canImport, isTrue);
  });

  test('缺周数列 → 停在步骤 2，并说明缺什么', () {
    final ColumnMapping m = guessColumnMapping(table(<List<String>>[
      <String>['课程名称', '星期', '开始节数', '结束节数'],
      <String>['高数', '1', '1', '2'],
    ]));
    expect(m.canImport, isFalse);
    expect(m.missingRequired(), contains(CourseField.weeks));
  });

  test('无表头（第一行就是数据）→ 内容启发式补齐必需字段', () {
    final ColumnMapping m = guessColumnMapping(table(<List<String>>[
      <String>['高等数学', '1', '1', '2', '1-5'],
      <String>['线性代数', '2', '3', '4', '1-16'],
      <String>['大学英语', '3', '5', '6', '2、5、8'],
    ]));
    expect(fieldOf(m, 0), CourseField.name);
    expect(fieldOf(m, 1), CourseField.weekday);
    expect(fieldOf(m, 2), CourseField.startSection);
    expect(fieldOf(m, 3), CourseField.endSection);
    expect(fieldOf(m, 4), CourseField.weeks);
    expect(m.columns.first.confidence, GuessConfidence.content);
    expect(m.canImport, isTrue);
  });

  test('手动改映射：目标字段被占用时，原列自动改忽略并给出提示', () {
    final ColumnMapping m =
        guessColumnMapping(table(<List<String>>[standardHeader, row1]));
    final String? notice = m.assign(5, CourseField.name); // 把「地点」列改判成课名
    expect(notice, contains('已由第 1 列映射'));
    expect(fieldOf(m, 5), CourseField.name);
    expect(fieldOf(m, 0), CourseField.ignore);
  });

  test('describeField 用于下拉框文案', () {
    expect(describeField(CourseField.weeks), '周数');
    expect(describeField(CourseField.teacher), contains('可选'));
  });
}

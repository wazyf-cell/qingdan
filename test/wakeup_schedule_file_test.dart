import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/domain/week_rule.dart';
import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/import/course/wakeup_schedule_file.dart';

/// 一份 WakeUp 导出的课表样本。**形状取自用户自己导出的那份 2026 秋课表**
/// （原文件在 `.gitignore` 排除的 `扩展/` 里、不随仓库发布），5 段拼接 JSON、
/// 9 门课 / 38 条明细 / 节次表整表 60 行一位都没动；**课程名、教师、教室、
/// 表名全部换成合成值**（仓库是 public，真实课表属于个人数据）。
///
/// 内联而不读盘还有个更要紧的理由：以前这个测试读工作区外那份用户自己的导出文件
/// （在 `.gitignore` 里），别人 clone 下来那个文件不存在，`flutter test` 当场红，
/// 而 CI 把 `flutter test` 排在构建前面——新人第一步就挂。现在这份夹具自带数据，
/// 不碰工作区外的任何东西。
const String kWakeupSample = r'''
{"courseLen":45,"id":1,"name":"默认","sameBreakLen":false,"sameLen":true,"theBreakLen":10}
[
{"endTime":"08:45","node":1,"startTime":"08:00","timeTable":1},{"endTime":"09:40","node":2,"startTime":"08:55","timeTable":1},{"endTime":"10:45","node":3,"startTime":"10:00","timeTable":1},{"endTime":"11:40","node":4,"startTime":"10:55","timeTable":1},{"endTime":"14:45","node":5,"startTime":"14:00","timeTable":1},{"endTime":"15:40","node":6,"startTime":"14:55","timeTable":1},
{"endTime":"16:45","node":7,"startTime":"16:00","timeTable":1},{"endTime":"17:40","node":8,"startTime":"16:55","timeTable":1},{"endTime":"19:45","node":9,"startTime":"19:00","timeTable":1},{"endTime":"20:40","node":10,"startTime":"19:55","timeTable":1},{"endTime":"21:35","node":11,"startTime":"20:50","timeTable":1},{"endTime":"22:10","node":12,"startTime":"21:25","timeTable":1},
{"endTime":"22:20","node":13,"startTime":"21:35","timeTable":1},{"endTime":"22:30","node":14,"startTime":"21:45","timeTable":1},{"endTime":"22:40","node":15,"startTime":"21:55","timeTable":1},{"endTime":"22:50","node":16,"startTime":"22:05","timeTable":1},{"endTime":"23:00","node":17,"startTime":"22:15","timeTable":1},{"endTime":"23:10","node":18,"startTime":"22:25","timeTable":1},
{"endTime":"23:20","node":19,"startTime":"22:35","timeTable":1},{"endTime":"23:30","node":20,"startTime":"22:45","timeTable":1},{"endTime":"23:40","node":21,"startTime":"22:55","timeTable":1},{"endTime":"23:50","node":22,"startTime":"23:05","timeTable":1},{"endTime":"00:00","node":23,"startTime":"23:15","timeTable":1},{"endTime":"00:00","node":24,"startTime":"23:25","timeTable":1},
{"endTime":"00:00","node":25,"startTime":"23:35","timeTable":1},{"endTime":"00:00","node":26,"startTime":"23:45","timeTable":1},{"endTime":"00:00","node":27,"startTime":"23:51","timeTable":1},{"endTime":"00:00","node":28,"startTime":"23:56","timeTable":1},{"endTime":"00:45","node":29,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":30,"startTime":"00:00","timeTable":1},
{"endTime":"00:45","node":31,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":32,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":33,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":34,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":35,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":36,"startTime":"00:00","timeTable":1},
{"endTime":"00:45","node":37,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":38,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":39,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":40,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":41,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":42,"startTime":"00:00","timeTable":1},
{"endTime":"00:45","node":43,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":44,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":45,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":46,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":47,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":48,"startTime":"00:00","timeTable":1},
{"endTime":"00:45","node":49,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":50,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":51,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":52,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":53,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":54,"startTime":"00:00","timeTable":1},
{"endTime":"00:45","node":55,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":56,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":57,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":58,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":59,"startTime":"00:00","timeTable":1},{"endTime":"00:45","node":60,"startTime":"00:00","timeTable":1}
]
{"background":"","courseTextColor":-1,"id":2,"itemAlpha":50,"itemHeight":64,"itemTextSize":12,"maxWeek":20,"nodes":11,"showOtherWeekCourse":false,"showSat":true,"showSun":true,"showTime":false,"startDate":"2026-8-31","strokeColor":-2130706433,"sundayFirst":false,"tableName":"示例学期","textColor":-16777216,"timeTable":1,"type":0,"widgetCourseTextColor":-1,"widgetItemAlpha":50,"widgetItemHeight":64,"widgetItemTextSize":12,"widgetStrokeColor":-2130706433,"widgetTextColor":-16777216}
[
{"color":"#ffff1744","courseName":"课程甲","credit":0.0,"id":0,"note":"","tableId":2},
{"color":"#fffa6278","courseName":"课程乙B","credit":0.0,"id":1,"note":"","tableId":2},
{"color":"#ff2979ff","courseName":"课程丙","credit":0.0,"id":2,"note":"","tableId":2},
{"color":"#ff1de9b6","courseName":"课程丁","credit":0.0,"id":3,"note":"","tableId":2},
{"color":"#ffa375ff","courseName":"课程戊","credit":0.0,"id":4,"note":"","tableId":2},
{"color":"#ffff9100","courseName":"课程己","credit":0.0,"id":5,"note":"","tableId":2},
{"color":"#ffff3d00","courseName":"课程庚","credit":0.0,"id":6,"note":"","tableId":2},
{"color":"#ff2196f3","courseName":"课程辛","credit":0.0,"id":7,"note":"","tableId":2},
{"color":"#ff005caf","courseName":"课程壬","credit":0.0,"id":8,"note":"","tableId":2}
]
[
{"day":1,"endTime":"","endWeek":6,"id":0,"level":0,"ownTime":false,"room":"T101","startNode":1,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"张老师","type":0},
{"day":1,"endTime":"","endWeek":11,"id":0,"level":0,"ownTime":false,"room":"T101","startNode":1,"startTime":"","startWeek":8,"step":2,"tableId":2,"teacher":"张老师","type":0},
{"day":1,"endTime":"","endWeek":15,"id":0,"level":0,"ownTime":false,"room":"T101","startNode":1,"startTime":"","startWeek":13,"step":2,"tableId":2,"teacher":"张老师","type":0},
{"day":1,"endTime":"","endWeek":12,"id":1,"level":0,"ownTime":false,"room":"测试楼411","startNode":1,"startTime":"","startWeek":12,"step":8,"tableId":2,"teacher":"李老师","type":0},
{"day":2,"endTime":"","endWeek":3,"id":0,"level":0,"ownTime":false,"room":"T201","startNode":1,"startTime":"","startWeek":3,"step":2,"tableId":2,"teacher":"张老师","type":0},
{"day":2,"endTime":"","endWeek":9,"id":0,"level":0,"ownTime":false,"room":"T201","startNode":1,"startTime":"","startWeek":7,"step":2,"tableId":2,"teacher":"张老师","type":0},
{"day":2,"endTime":"","endWeek":15,"id":0,"level":0,"ownTime":false,"room":"T201","startNode":1,"startTime":"","startWeek":14,"step":2,"tableId":2,"teacher":"张老师","type":0},
{"day":2,"endTime":"","endWeek":12,"id":1,"level":0,"ownTime":false,"room":"测试楼411","startNode":1,"startTime":"","startWeek":12,"step":8,"tableId":2,"teacher":"李老师","type":0},
{"day":3,"endTime":"","endWeek":8,"id":2,"level":0,"ownTime":false,"room":"T202","startNode":1,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"外籍教师示例","type":0},
{"day":3,"endTime":"","endWeek":12,"id":1,"level":0,"ownTime":false,"room":"测试楼411","startNode":1,"startTime":"","startWeek":12,"step":8,"tableId":2,"teacher":"李老师","type":0},
{"day":3,"endTime":"","endWeek":19,"id":3,"level":0,"ownTime":false,"room":"T204","startNode":1,"startTime":"","startWeek":14,"step":2,"tableId":2,"teacher":"赵老师","type":0},
{"day":4,"endTime":"","endWeek":10,"id":4,"level":0,"ownTime":false,"room":"测试楼309","startNode":1,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"钱老师","type":0},
{"day":4,"endTime":"","endWeek":12,"id":1,"level":0,"ownTime":false,"room":"测试楼411","startNode":1,"startTime":"","startWeek":12,"step":8,"tableId":2,"teacher":"李老师","type":0},
{"day":5,"endTime":"","endWeek":3,"id":5,"level":0,"ownTime":false,"room":"T201","startNode":1,"startTime":"","startWeek":3,"step":2,"tableId":2,"teacher":"孙老师","type":0},
{"day":5,"endTime":"","endWeek":6,"id":5,"level":0,"ownTime":false,"room":"T201","startNode":1,"startTime":"","startWeek":6,"step":2,"tableId":2,"teacher":"孙老师","type":0},
{"day":5,"endTime":"","endWeek":9,"id":5,"level":0,"ownTime":false,"room":"T201","startNode":1,"startTime":"","startWeek":8,"step":2,"tableId":2,"teacher":"孙老师","type":0},
{"day":5,"endTime":"","endWeek":12,"id":1,"level":0,"ownTime":false,"room":"测试楼411","startNode":1,"startTime":"","startWeek":12,"step":8,"tableId":2,"teacher":"李老师","type":0},
{"day":1,"endTime":"","endWeek":8,"id":6,"level":0,"ownTime":false,"room":"T203","startNode":3,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"周老师","type":0},
{"day":1,"endTime":"","endWeek":19,"id":3,"level":0,"ownTime":false,"room":"T204","startNode":3,"startTime":"","startWeek":14,"step":2,"tableId":2,"teacher":"赵老师","type":0},
{"day":2,"endTime":"","endWeek":10,"id":4,"level":0,"ownTime":false,"room":"测试楼309","startNode":3,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"钱老师","type":0},
{"day":3,"endTime":"","endWeek":6,"id":0,"level":0,"ownTime":false,"room":"T105","startNode":3,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"张老师","type":0},
{"day":3,"endTime":"","endWeek":11,"id":0,"level":0,"ownTime":false,"room":"T105","startNode":3,"startTime":"","startWeek":8,"step":2,"tableId":2,"teacher":"张老师","type":0},
{"day":3,"endTime":"","endWeek":15,"id":0,"level":0,"ownTime":false,"room":"T105","startNode":3,"startTime":"","startWeek":13,"step":2,"tableId":2,"teacher":"张老师","type":0},
{"day":4,"endTime":"","endWeek":6,"id":6,"level":0,"ownTime":false,"room":"T402","startNode":3,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"周老师","type":0},
{"day":4,"endTime":"","endWeek":9,"id":6,"level":0,"ownTime":false,"room":"T402","startNode":3,"startTime":"","startWeek":8,"step":2,"tableId":2,"teacher":"周老师","type":0},
{"day":5,"endTime":"","endWeek":8,"id":5,"level":0,"ownTime":false,"room":"T501","startNode":3,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"孙老师","type":0},
{"day":5,"endTime":"","endWeek":17,"id":3,"level":0,"ownTime":false,"room":"T204","startNode":3,"startTime":"","startWeek":14,"step":2,"tableId":2,"teacher":"赵老师","type":0},
{"day":1,"endTime":"","endWeek":8,"id":7,"level":0,"ownTime":false,"room":"T503","startNode":5,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"吴老师","type":0},
{"day":2,"endTime":"","endWeek":5,"id":4,"level":0,"ownTime":false,"room":"T608/10","startNode":5,"startTime":"","startWeek":5,"step":2,"tableId":2,"teacher":"钱老师","type":0},
{"day":2,"endTime":"","endWeek":9,"id":4,"level":0,"ownTime":false,"room":"T608/10","startNode":5,"startTime":"","startWeek":7,"step":2,"tableId":2,"teacher":"钱老师","type":0},
{"day":3,"endTime":"","endWeek":8,"id":7,"level":0,"ownTime":false,"room":"T504","startNode":5,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"吴老师","type":0},
{"day":5,"endTime":"","endWeek":11,"id":8,"level":0,"ownTime":false,"room":"T603/5","startNode":5,"startTime":"","startWeek":10,"step":2,"tableId":2,"teacher":"郑老师","type":0},
{"day":5,"endTime":"","endWeek":14,"id":8,"level":0,"ownTime":false,"room":"T603/5","startNode":5,"startTime":"","startWeek":13,"step":2,"tableId":2,"teacher":"郑老师","type":0},
{"day":1,"endTime":"","endWeek":8,"id":5,"level":0,"ownTime":false,"room":"T502","startNode":7,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"孙老师","type":0},
{"day":3,"endTime":"","endWeek":5,"id":7,"level":0,"ownTime":false,"room":"T608/10","startNode":7,"startTime":"","startWeek":3,"step":2,"tableId":2,"teacher":"吴老师","type":0},
{"day":3,"endTime":"","endWeek":7,"id":7,"level":0,"ownTime":false,"room":"T608/10","startNode":7,"startTime":"","startWeek":7,"step":2,"tableId":2,"teacher":"吴老师","type":0},
{"day":5,"endTime":"","endWeek":11,"id":8,"level":0,"ownTime":false,"room":"T505","startNode":7,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"郑老师","type":0},
{"day":5,"endTime":"","endWeek":14,"id":8,"level":0,"ownTime":false,"room":"T505","startNode":7,"startTime":"","startWeek":14,"step":2,"tableId":2,"teacher":"郑老师","type":0}
]''';

/// 与真文件读进来的字节同形（`readAsBytesSync` 的替代品）。
final Uint8List kReal = utf8.encode(kWakeupSample);

List<String> rowOf(ScheduleTable t, String name, String day) => t.rows
    .firstWhere((List<String> r) => r[0] == name && r[1] == day)
    .toList();

void main() {
  group('识别与路由', () {
    test('WakeUp 导出被认出来，csv/xlsx 不受影响', () {
      expect(isWakeupSchedule(kReal), isTrue);
      expect(
          isWakeupSchedule(
              utf8.encode('课程名称,星期\n高等数学,1')),
          isFalse);
    });

    test('readScheduleTable 自动走 WakeUp 分支（用户只需选文件）', () {
      final ScheduleTable t = readScheduleTable(kReal);
      expect(t.sheetName, 'WakeUp 导出');
      expect(t.rows.first, kImportHeader);
    });

    test('缺课程段时给出可执行的错', () {
      expect(
          () => readWakeupSchedule(
              utf8.encode('{"courseLen":45}\n[{"startNode":1}]')),
          throwsA(isA<ScheduleFileException>()));
    });
  });

  group('样本解析（9 门课 / 38 条明细 → 25 行）', () {
    final ScheduleTable t = readWakeupSchedule(kReal);

    test('明细按「同课同日同节次同教室」把不连续周次并成一条', () {
      expect(t.rows.length - 1, 25);
      expect(rowOf(t, '课程甲', '1')[6], '1-6,8-11,13-15(周)');
      expect(rowOf(t, '课程甲', '1')[4], '张老师');
      expect(rowOf(t, '课程甲', '1')[5], 'T101');
    });

    test('startNode + step 还原成起止节数（跨 8 节的那门不再散成 4 条）', () {
      final List<String> g = rowOf(t, '课程乙B', '1');
      expect(g[2], '1');
      expect(g[3], '8');
      expect(g[6], '12(周)');
      expect(t.rows.where((List<String> r) => r[0] == '课程乙B').length, 5);
    });

    test('每一行的周次文本都能被周次解析器接受（产出的格式不跑偏）', () {
      for (final List<String> r in t.rows.skip(1)) {
        expect(() => parseWeekRule(r[6], totalWeeks: 20), returnsNormally,
            reason: '${r[0]} 的周数「${r[6]}」解析失败');
      }
    });
  });

  group('导出文件顺带带的学期与作息', () {
    test('样本给出 2026-8-31 起 · 20 周 · 11 节，时间是当日分钟数', () {
      final WakeupMeta? meta = readWakeupMeta(kReal);
      expect(meta, isNotNull);
      expect(meta!.firstWeekDate, DateTime(2026, 8, 31));
      expect(meta.totalWeeks, 20);
      // 导出里的节次表有 **60 行**（WakeUp 生成的整表，第 12 节起时间自相重叠），
      // 必须按「视图声明节数 / 课程用到的最大节」取大者截断，否则作息会被灌成 60 节。
      expect(meta.sections.length, 11);
      expect(meta.sections.last.section, 11);
      expect(meta.sections.last.start, '20:50');
      final List<TimeDetail> draft = meta.toDraft();
      expect(draft.first.section, 1);
      expect(draft.first.startMinutes, 8 * 60);
      expect(draft.first.endMinutes, 8 * 60 + 45);
      expect(draft.last.section, 11);
      // 作息草稿走的是与手工加节同样的构造：id 留空 = 新建默认表
      expect(draft.every((TimeDetail d) => d.id.isEmpty), isTrue);
    });

    test('没有 startDate 段时返回 null（界面不出现采纳条）', () {
      expect(
          readWakeupMeta(utf8.encode(
              '{"courseLen":45}\n[{"courseName":"x","id":0}]\n[{"startNode":1,"node":1,"step":2,"day":1,"id":0,"startWeek":1,"endWeek":2}]')),
          isNull);
    });
  });

  group('单双周', () {
    test('type 1/2 产出「…单」「…双」，且周次解析器认', () {
      final ScheduleTable t = readWakeupSchedule(
          utf8.encode('''
{"courseLen":45,"id":1,"name":"默认","sameBreakLen":false,"sameLen":true,"theBreakLen":10}
[{"endTime":"08:45","node":1,"startTime":"08:00","timeTable":1}]
{"maxWeek":20,"nodes":12,"startDate":"2026-8-31","timeTable":1}
[{"color":"#ff0000","courseName":"体育","credit":1.0,"id":3,"note":"","tableId":2}]
[{"day":2,"endTime":"","endWeek":15,"id":3,"level":0,"ownTime":false,"room":"操场","startNode":3,"startTime":"","startWeek":1,"step":2,"tableId":2,"teacher":"王","type":1}]
'''));
      final List<String> r = t.rows.last;
      expect(r[0], '体育');
      expect(r[2], '3');
      expect(r[3], '4');
      expect(r[6], '1-15单');
      expect(() => parseWeekRule(r[6], totalWeeks: 20), returnsNormally);
    });
  });
}

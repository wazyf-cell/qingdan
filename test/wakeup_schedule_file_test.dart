import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/domain/week_rule.dart';
import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/import/course/wakeup_schedule_file.dart';

/// 真样本：用户从 WakeUp 导出的 2026 秋课表（`扩展/本学期.wakeup_schedule`）。
final Uint8List kReal = File('扩展/本学期.wakeup_schedule').readAsBytesSync();

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

  group('真样本解析（9 门课 / 38 条明细 → 25 行）', () {
    final ScheduleTable t = readWakeupSchedule(kReal);

    test('明细按「同课同日同节次同教室」把不连续周次并成一条', () {
      expect(t.rows.length - 1, 25);
      expect(rowOf(t, '计算机网络', '1')[6], '1-6,8-11,13-15(周)');
      expect(rowOf(t, '计算机网络', '1')[4], '张老师');
      expect(rowOf(t, '计算机网络', '1')[5], 'A101');
    });

    test('startNode + step 还原成起止节数（跨 8 节的工训不再散成 4 条）', () {
      final List<String> g = rowOf(t, '工艺训练B', '1');
      expect(g[2], '1');
      expect(g[3], '8');
      expect(g[6], '12(周)');
      expect(t.rows.where((List<String> r) => r[0] == '工艺训练B').length, 5);
    });

    test('每一行的周次文本都能被周次解析器接受（产出的格式不跑偏）', () {
      for (final List<String> r in t.rows.skip(1)) {
        expect(() => parseWeekRule(r[6], totalWeeks: 20), returnsNormally,
            reason: '${r[0]} 的周数「${r[6]}」解析失败');
      }
    });
  });

  group('导出文件顺带带的学期与作息', () {
    test('真样本给出 2026-8-31 起 · 20 周 · 11 节，时间是当日分钟数', () {
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

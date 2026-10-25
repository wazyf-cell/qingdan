import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/features/widgets/widget_snapshot.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

/// 桌面小组件的数据快照（v1.0.6）：筛谁、怎么排、时间怎么格式化、失败态怎么表达。
///
/// 危害形状：快照把「已完成」「明天到期」也算进今天，桌面就会挂着一条早做完
/// 或还不该出现的任务 —— 而小组件没有下拉刷新，用户只能去删卡片。
void main() {
  final DateTime now = DateTime(2026, 10, 24, 10, 30); // 周六

  Task task(String id, String title, DateTime? due, {bool done = false}) =>
      Task(id: id, title: title, dueDate: due, completed: done);

  Semester semester() => Semester(
        id: 's1',
        name: '大三上',
        firstWeekMonday: DateTime.utc(2026, 8, 31),
        totalWeeks: 20,
      );

  TimeDetail detail(int section, int start, int end) => TimeDetail(
        id: 'd$section',
        timetableId: 'tt',
        section: section,
        startMinutes: start,
        endMinutes: end,
      );

  Course course(String name, int start, int end,
          {String? room, List<int> weeks = const <int>[8]}) =>
      Course(
        id: name,
        uid: name,
        name: name,
        weekday: 6,
        startSection: start,
        endSection: end,
        weeks: weeks,
        location: room,
      );

  group('今天', () {
    test('只留未完成、到期早于明天；按到期时间升序；时间格式 HH:mm', () {
      final Map<String, Object?> snap = buildTodaySnapshot(
        allActive: <Task>[
          task('late', '晚一点', DateTime(2026, 10, 24, 20, 5)),
          task('done', '做完了', DateTime(2026, 10, 24, 9), done: true),
          task('tomorrow', '明天', DateTime(2026, 10, 25, 8)),
          task('nodue', '没到期', null),
          task('early', '早一点', DateTime(2026, 10, 24, 8, 0)),
        ],
        now: now,
      );

      expect(snap['date'], '2026-10-24');
      expect(snap['weekday'], '周六');
      expect(snap['total'], 2);
      final List<Map<String, Object?>> rows =
          (snap['tasks']! as List<Object?>).cast<Map<String, Object?>>();
      expect(<Object?>[for (final Map<String, Object?> r in rows) r['title']],
          <String>['早一点', '晚一点']);
      expect(rows.first['due'], '08:00');
      expect(rows.first['id'], 'early');
    });

    test('空列表也给出完整形状（原生不用判 null）', () {
      final Map<String, Object?> snap =
          buildTodaySnapshot(allActive: const <Task>[], now: now);
      expect(snap['total'], 0);
      expect(snap['tasks'], isEmpty);
      expect(snap['weekday'], isA<String>());
    });
  });

  group('课表', () {
    final List<TimeDetail> details = <TimeDetail>[
      detail(1, 8 * 60, 9 * 60 + 40),
      detail(2, 10 * 60, 11 * 60 + 40),
      detail(3, 14 * 60, 15 * 60 + 40),
    ];

    test('没有学期：state=no_semester，不伪造课程', () {
      final Map<String, Object?> snap = buildCourseSnapshot(
        semester: null,
        courses: const <Course>[],
        details: details,
        now: now,
      );
      expect(snap['state'], 'no_semester');
      expect(snap['courses'], isEmpty);
    });

    test('学期外：state=outside_semester', () {
      final Map<String, Object?> snap = buildCourseSnapshot(
        semester: semester(),
        courses: const <Course>[],
        details: details,
        now: DateTime(2026, 7, 1),
      );
      expect(snap['state'], 'outside_semester');
    });

    test('按节次换算起止时间，并指出「下一节」', () {
      final Map<String, Object?> snap = buildCourseSnapshot(
        semester: semester(),
        // 第一节 08:00–11:40（含 20 分钟大课间）已上完，14:00 那门是下一节。
        courses: <Course>[
          course('网络及其计算', 1, 2, room: 'C203'),
          course('软件质量保证', 3, 3, room: 'F202'),
        ],
        details: details,
        now: DateTime(2026, 10, 24, 12, 0),
      );

      expect(snap['state'], 'ok');
      expect(snap['week'], 8);
      expect(snap['semester'], '大三上');
      final List<Map<String, Object?>> rows =
          (snap['courses']! as List<Object?>).cast<Map<String, Object?>>();
      expect(rows.length, 2);
      expect(rows.first['start'], '08:00');
      expect(rows.first['end'], '11:40',
          reason: '第 2 节 10:00 开始、含 20 分钟大课间；结束时间按作息表算，不按臆测');
      expect(rows.first['section'], '第 1-2 节');
      expect(rows.first['room'], 'C203');
      expect(rows[1]['start'], '14:00');
      expect(rows[1]['section'], '第 3 节',
          reason: '单节课不该显示成 3-3');
      expect(snap['nextIndex'], 1, reason: '10:30 时第二门（14:00）才是下一节');
    });

    test('今天的课都上完了：nextIndex = -1', () {
      final Map<String, Object?> snap = buildCourseSnapshot(
        semester: semester(),
        courses: <Course>[course('网络及其计算', 1, 2)],
        details: details,
        now: DateTime(2026, 10, 24, 23, 0),
      );
      expect(snap['nextIndex'], -1);
    });

    test('今天没课：state 仍是 ok、列表为空（与「没有学期」分开）', () {
      final Map<String, Object?> snap = buildCourseSnapshot(
        semester: semester(),
        courses: const <Course>[],
        details: details,
        now: now,
      );
      expect(snap['state'], 'ok');
      expect(snap['courses'], isEmpty);
    });
  });

  group('学习通', () {
    ChaoxingTask item(String id,
            {String title = '作业一', DateTime? due, bool done = false,
            bool ongoing = true, bool upcoming = false}) =>
        ChaoxingTask(
          id: id,
          courseId: 'c1',
          courseName: '软件建模技术',
          title: title,
          kind: '作业',
          ongoing: ongoing,
          dueAt: due,
          serverDone: done,
          startAt: upcoming ? now.add(const Duration(days: 2)) : null,
        );

    test('没刷新过：fetched=false、计数 0（不能显示成「没有待办」）', () {
      final Map<String, Object?> snap = buildChaoxingSnapshot(
        tasks: <ChaoxingTask>[item('a', due: now.add(const Duration(hours: 3)))],
        hidden: const <String>{},
        now: now,
        fetchedAt: null,
      );
      expect(snap['fetched'], isFalse);
      expect(snap['count'], 0);
      expect(snap['todos'], isEmpty);
    });

    test('已交 / 已结束 / 被隐藏 / 未开始 都不进待办；按截止时间升序', () {
      final ChaoxingTask soon =
          item('soon', title: '快到期', due: now.add(const Duration(hours: 2)));
      final Map<String, Object?> snap = buildChaoxingSnapshot(
        tasks: <ChaoxingTask>[
          item('later', title: '更晚', due: now.add(const Duration(days: 3))),
          soon,
          item('done', done: true, due: now.add(const Duration(hours: 1))),
          item('ended', ongoing: false, due: now.add(const Duration(hours: 1))),
          item('upcoming', upcoming: true),
          item('hidden', due: now.add(const Duration(hours: 1))),
          item('nodue', title: '无截止'),
        ],
        hidden: <String>{'c1|hidden'},
        now: now,
        fetchedAt: now,
      );

      final List<Map<String, Object?>> rows =
          (snap['todos']! as List<Object?>).cast<Map<String, Object?>>();
      expect(<Object?>[for (final Map<String, Object?> r in rows) r['title']],
          <String>['快到期', '更晚', '无截止']);
      expect(snap['count'], 3);
      expect(snap['dueSoon'], 1, reason: '只有 2 小时后那条在 24 小时内');
      expect(rows.first['due'], soon.dueAt!.millisecondsSinceEpoch);
      expect(rows.first['color'], courseColorIndex('软件建模技术'),
          reason: '颜色按课名派生，与课表同一套 8 色');
    });
  });
}

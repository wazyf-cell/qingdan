import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

/// 课表域纯数据与规则测试（§1.1 / §2.1~§2.3）。无 IO。
void main() {
  group('学期与周次（§2.1）', () {
    Semester semester({int totalWeeks = 16}) => Semester(
          id: 's1',
          name: '2025-2026-1',
          firstWeekMonday: DateTime.utc(2025, 9, 1),
          totalWeeks: totalWeeks,
        );

    test('mondayOf 把任意日期归到该周周一（含周日）', () {
      // 2025-09-01 是周一。
      expect(Semester.mondayOf(DateTime.utc(2025, 9, 1)), DateTime.utc(2025, 9, 1));
      expect(Semester.mondayOf(DateTime.utc(2025, 9, 3)), DateTime.utc(2025, 9, 1));
      expect(Semester.mondayOf(DateTime.utc(2025, 9, 7)), DateTime.utc(2025, 9, 1));
      expect(Semester.mondayOf(DateTime.utc(2025, 9, 8)), DateTime.utc(2025, 9, 8));
    });

    test('mondayOf 丢弃时分，只看日期', () {
      expect(
        Semester.mondayOf(DateTime.utc(2025, 9, 3, 23, 59, 59)),
        DateTime.utc(2025, 9, 1),
      );
    });

    test('weekOf：第 1 周与跨周', () {
      final Semester s = semester();
      expect(s.weekOf(DateTime.utc(2025, 9, 1)), 1);
      expect(s.weekOf(DateTime.utc(2025, 9, 7)), 1);
      expect(s.weekOf(DateTime.utc(2025, 9, 8)), 2);
    });

    test('weekOf：开学前与学期外返回 null（不返回 0 或负数冒充第 1 周）', () {
      final Semester s = semester(totalWeeks: 3);
      expect(s.weekOf(DateTime.utc(2025, 8, 31)), isNull);
      expect(s.weekOf(DateTime.utc(2025, 9, 22)), isNull); // 第 4 周，超总周数
      expect(s.weekOf(DateTime.utc(2025, 9, 15)), 3);
    });

    test('mondayOfWeek(n) 与 weekOf 互逆', () {
      final Semester s = semester();
      for (int w = 1; w <= 16; w++) {
        expect(s.weekOf(s.mondayOfWeek(w)), w, reason: '第 $w 周');
      }
    });

    test('学期落库按「纯日期 UTC 零点」，不受设备时区影响（§1.2）', () {
      final Semester s = semester();
      final Map<String, Object?> map = s.toMap();
      final Semester back = Semester.fromMap(map);
      expect(back.firstWeekMonday, DateTime.utc(2025, 9, 1));
      expect(back.firstWeekMonday.isUtc, isTrue);
      expect(back.totalWeeks, 16);
      expect(back.isActive, isTrue);
    });
  });

  group('作息表（§2.2 / §2.3）', () {
    TimeDetail d(int section, int start, int end) => TimeDetail(
        id: 'd$section',
        timetableId: 't1',
        section: section,
        startMinutes: start,
        endMinutes: end);

    test('校验通过：递增且不重叠，允许零课间', () {
      expect(
          validateTimeDetails(<TimeDetail>[d(1, 480, 525), d(2, 525, 570)]),
          isNull);
    });

    test('校验失败：结束不晚于开始 / 时间重叠 / 节次小于 1', () {
      expect(validateTimeDetails(<TimeDetail>[d(1, 480, 480)]), contains('晚于'));
      expect(
          validateTimeDetails(<TimeDetail>[d(1, 480, 530), d(2, 525, 570)]),
          contains('重叠'));
      expect(validateTimeDetails(<TimeDetail>[d(0, 480, 525)]), contains('1 开始'));
    });

    test('快速生成：45 分钟/节、课间 10、3 节', () {
      final List<TimeDetail> out = generateTimeDetails(
          timetableId: 't1',
          firstStartMinutes: 480,
          lessonMinutes: 45,
          breakMinutes: 10,
          sectionCount: 3);
      expect(out.map((TimeDetail e) => e.startMinutes), <int>[480, 535, 590]);
      expect(out.map((TimeDetail e) => e.endMinutes), <int>[525, 580, 635]);
      expect(out.map((TimeDetail e) => e.section), <int>[1, 2, 3]);
    });

    test('快速生成：午休在指定节次后插入', () {
      final List<TimeDetail> out = generateTimeDetails(
          timetableId: 't1',
          firstStartMinutes: 480,
          lessonMinutes: 45,
          breakMinutes: 10,
          sectionCount: 3,
          lunchAfterSection: 2,
          lunchMinutes: 90);
      expect(out[2].startMinutes, 590 + 90);
    });

    test('改第 1 节后：其后整体顺移、该节不动、课间保持（§2.3 最常见诉求）', () {
      final List<TimeDetail> base = <TimeDetail>[
        d(1, 480, 525), d(2, 535, 580), d(3, 590, 635),
      ];
      final List<TimeDetail> out = shiftSectionsAfter(base, 1, 20);
      expect(out[0].startMinutes, 480);
      expect(out[1].startMinutes, 555);
      expect(out[1].endMinutes, 600);
      expect(out[2].startMinutes, 610);
      expect(out[2].endMinutes - out[1].endMinutes, 635 - 580); // 课间没被毁

      // 改第 2 节只动它之后的节。
      final List<TimeDetail> out2 = shiftSectionsAfter(base, 2, -10);
      expect(out2[0].startMinutes, 480);
      expect(out2[1].startMinutes, 535);
      expect(out2[2].startMinutes, 580);
    });

    test('删除中间一节后节次号补位重排', () {
      final List<TimeDetail> out = renumber(<TimeDetail>[d(1, 480, 525), d(3, 590, 635)]);
      expect(out.map((TimeDetail e) => e.section), <int>[1, 2]);
    });
  });

  group('课程（§1.1 / §3.4）', () {
    Course course({
      String name = '高等数学',
      int weekday = 1,
      int start = 1,
      int end = 2,
      List<int> weeks = const <int>[1, 2, 3],
      String? teacher,
      String? location,
      int? colorIndex,
    }) =>
        Course(
          id: 'c1',
          uid: 'u1',
          name: name,
          weekday: weekday,
          startSection: start,
          endSection: end,
          weeks: weeks,
          teacher: teacher,
          location: location,
          colorIndex: colorIndex,
        );

    test('构造即排序去重（渲染与 UID 都依赖它）', () {
      final Course c = course(weeks: <int>[3, 1, 3, 2]);
      expect(c.weeks, <int>[1, 2, 3]);
    });

    test('空字符串归一为 null，不做「待定」文案', () {
      expect(Course.blankToNull('   '), isNull);
      expect(Course.blankToNull('王老师'), '王老师');
      expect(course(teacher: '  ', location: '')
          .toMap()['teacher'], isNull);
    });

    test('weeks 落库为 JSON 数组字符串并可还原', () {
      final Course c = course(weeks: <int>[1, 3, 5]);
      expect(c.toMap()['weeks'], '[1,3,5]');
      expect(Course.fromMap(c.toMap()).weeks, <int>[1, 3, 5]);
      expect(Course.decodeWeeks(null), <int>[]);
      expect(Course.decodeWeeks(''), <int>[]);
    });

    test('origin 与 deleted 的 0/1 与字符串映射', () {
      final Course c = course().copyWith(
          origin: CourseOrigin.import, importBatchId: 'b1', deleted: true);
      final Map<String, Object?> map = c.toMap();
      expect(map['origin'], 'import');
      expect(map['deleted'], 1);
      final Course back = Course.fromMap(map);
      expect(back.origin, CourseOrigin.import);
      expect(back.importBatchId, 'b1');
      expect(back.deleted, isTrue);
    });

    test('同槽判定：同星期 + 区间相交 + 有共同周次才算重叠', () {
      expect(course().overlaps(course()), isTrue);
      // 样本第 2、3 行：同槽但周次不相交 → 不算重叠，两门都要显示。
      expect(course(weeks: <int>[1, 2]).overlaps(course(weeks: <int>[3, 4])),
          isFalse);
      expect(course(weekday: 2).overlaps(course()), isFalse);
      expect(course(start: 5, end: 6).overlaps(course()), isFalse);
    });

    test('配色：没手动选过就按课名派生；选过的落库（M6-D §十改了这条）', () {
      // 旧契约是「颜色不落库」，D 批加了可空列 `color_index` 之后：
      // null = 跟随课名自动配色（跨设备稳定），非 null = 用户显式选过。
      expect(course().colorIndex, isNull, reason: '默认没有显式配色');
      expect(course().effectiveColorIndex, courseColorIndex('高等数学'),
          reason: '没选过时实际用的就是课名派生值');
      expect(course().toMap()['color_index'], isNull,
          reason: '列存在但值为空，渲染端据此回落到自动配色');

      final Course picked = course(colorIndex: 5);
      expect(picked.toMap()['color_index'], 5);
      expect(picked.effectiveColorIndex, 5);
      expect(Course.fromMap(picked.toMap()).colorIndex, 5,
          reason: '往返要能把选过的颜色带回来');
      // 「恢复自动配色」必须能把列清回 null——copyWith 的 `??` 会吞掉这件事。
      expect(picked.copyWith(name: '改名了').colorIndex, 5);
      expect(picked.copyWith(clearColor: true).colorIndex, isNull);
    });
  });
}

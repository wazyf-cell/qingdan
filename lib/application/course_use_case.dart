import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_uid.dart';
import 'package:qingdan/domain/semester.dart';

/// 课程用例（F28 手工录入 / F31 查询）。所有写操作的唯一入口。
///
/// UID 在这里算：`uid = sha1(normalize(name)|weekday|start|end|weeks)`（§3.5），
/// 所以**改键字段就是改 UID**，覆盖导入时表现为「一删一增」，汇总页如实报告。
class CourseUseCase {
  CourseUseCase(this._services);

  final AppServices _services;

  /// 手工新建一门课（[CourseOrigin.manual]）。
  Future<Course> create({
    required String name,
    required int weekday,
    required int startSection,
    required int endSection,
    required List<int> weeks,
    String? teacher,
    String? location,
    String? rawWeeksText,
    String? semesterId,
  }) async {
    _validate(
      name: name,
      weekday: weekday,
      startSection: startSection,
      endSection: endSection,
      weeks: weeks,
    );
    final String uid = courseUidOf(
      name: name,
      weekday: weekday,
      startSection: startSection,
      endSection: endSection,
      weeks: weeks,
    );
    return _services.courseDao.insert(Course(
      id: '',
      uid: uid,
      name: name.trim(),
      teacher: Course.blankToNull(teacher),
      location: Course.blankToNull(location),
      weekday: weekday,
      startSection: startSection,
      endSection: endSection,
      weeks: weeks,
      rawWeeksText: rawWeeksText,
      semesterId: semesterId,
      origin: CourseOrigin.manual,
    ));
  }

  /// 保存面板产出的课程：`id` 为空 → 新建；否则更新。UID 一律重算。
  ///
  /// 导入向导（S5）与手工录入共用这一条落库路径。
  Future<Course> save(Course course) async {
    if (course.id.isEmpty) {
      return create(
        name: course.name,
        weekday: course.weekday,
        startSection: course.startSection,
        endSection: course.endSection,
        weeks: course.weeks,
        teacher: course.teacher,
        location: course.location,
        rawWeeksText: course.rawWeeksText,
        semesterId: course.semesterId,
      );
    }
    await update(course);
    return course;
  }

  /// 编辑课程：键字段可能变，因此**总是重算 UID**。
  Future<void> update(Course course) async {
    _validate(
      name: course.name,
      weekday: course.weekday,
      startSection: course.startSection,
      endSection: course.endSection,
      weeks: course.weeks,
    );
    await _services.courseDao.update(course.copyWith(
      uid: courseUidOf(
        name: course.name,
        weekday: course.weekday,
        startSection: course.startSection,
        endSection: course.endSection,
        weeks: course.weeks,
      ),
    ));
  }

  /// 软删除（课程不进回收站，见 v4 表注释）。
  Future<void> delete(String id) => _services.courseDao.softDelete(id);

  Future<List<Course>> activeCourses({String? semesterId, int? weekday}) =>
      _services.courseDao.findActive(
          semesterId: semesterId, weekday: weekday);

  Future<List<Course>> coursesOnWeek(int week, {String? semesterId}) =>
      _services.courseDao.findOnWeek(week, semesterId: semesterId);

  /// 某天要上的课（F34「打开应用即可看到今天要上的课」）。
  ///
  /// 周次换算与渲染共用 [Semester.weekOf] 这一个纯函数（§6.3.2）。
  /// 没有激活学期、或该日在学期外，都返回空列表而不是抛错——这是首页常态。
  Future<List<Course>> coursesOn(DateTime date) async {
    final Semester? semester = await _services.semesterDao.findActive();
    if (semester == null) return const <Course>[];
    final int? week = semester.weekOf(date);
    if (week == null) return const <Course>[];
    final List<Course> onDay = await _services.courseDao
        .findActive(semesterId: semester.id, weekday: date.weekday);
    return onDay.where((Course c) => c.isOn(week)).toList(growable: false);
  }

  Future<List<Course>> coursesToday() => coursesOn(DateTime.now());

  void _validate({
    required String name,
    required int weekday,
    required int startSection,
    required int endSection,
    required List<int> weeks,
  }) {
    if (name.trim().isEmpty) throw ArgumentError('课程名称不能为空');
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError('星期必须是 1~7（1 == 周一），收到 $weekday');
    }
    if (startSection < 1) throw ArgumentError('起始节必须 ≥ 1，收到 $startSection');
    if (endSection < startSection) {
      throw ArgumentError('结束节 $endSection 不得早于起始节 $startSection');
    }
    if (weeks.isEmpty) throw ArgumentError('至少要有一个周次');
  }
}

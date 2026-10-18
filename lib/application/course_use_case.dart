import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/data/semester_dao.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/course_freshness.dart';
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

  /// 顶部「上次更新 / 导入时间」的读数（M6-A A8，M6-D §八 补学期维度）。只读。
  ///
  /// 取「**该学期**最近一次导入」与「本学期最后编辑」里较新的那个：导入完又手改
  /// 过一门课，显示导入时间就是在骗人。v6 给 `import_batches` 加了
  /// `semester_id` 后，导进 A 学期的批次不再让 B 学期显示「N 分钟前导入」；
  /// 老批次（归属 NULL）不参与任何学期的导入读数，只在历史面板里以
  /// 「（学期未知）」出现。
  Future<CourseFreshness> freshness(String semesterId) async {
    final ImportBatchEntry? latest =
        await _services.courseDao.latestBatch(semesterId);
    final List<ImportBatchEntry> batches =
        await _services.courseDao.recentBatches();
    final DateTime? edited =
        await _services.courseDao.lastCourseModified(semesterId);
    if (latest != null &&
        (edited == null || !latest.batch.importedAt.isBefore(edited))) {
      return CourseFreshness(
        at: latest.batch.importedAt,
        kind: CourseFreshnessKind.import,
        fileName: latest.batch.fileName,
        imported: latest.batch.countImported,
        updated: latest.batch.countUpdated,
        skipped: latest.batch.countSkipped,
        batches: batches,
      );
    }
    if (edited == null) return CourseFreshness(batches: batches);
    return CourseFreshness(
        at: edited, kind: CourseFreshnessKind.edit, batches: batches);
  }

  /// 把**指定学期**（导入向导选中的那个，不一定是当前学期）的总周数抬到
  /// [needed]（M6-D §7.5：扩周必须落在选中的学期上）。
  ///
  /// 只抬不缩（缩周数让已有课程翻不到，那是用户在学期设置里自己做的事）；
  /// 读的是库内**现值**再写回，不拿调用方的旧快照（学期保存「后一次写盖掉
  /// 前一次」就是旧快照整行写回栽的坑）。无需改动或学期不存在返回 null。
  Future<Semester?> raiseSemesterWeeks(String semesterId, int needed) async {
    final Semester? s = await _services.semesterDao.findSemester(semesterId);
    if (s == null || s.totalWeeks >= needed) return null;
    final int target =
        needed > Semester.maxTotalWeeks ? Semester.maxTotalWeeks : needed;
    final Semester next = s.copyWith(totalWeeks: target);
    await _services.semesterDao.update(next);
    return next;
  }

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

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

/// 学期与作息用例（F28 / F30 的配置部分）。
///
/// UI 层只能调这里（AGENTS.md 铁律）。写库与记 op-log 由 DAO 在同一事务内完成。
class SemesterUseCase {
  SemesterUseCase(this._services);

  final AppServices _services;

  Future<Semester?> activeSemester() => _services.semesterDao.findActive();

  Future<List<Semester>> allSemesters() => _services.semesterDao.findAll();

  /// 新建学期。[firstWeekDate] 可以是开学第一周的**任意一天**，
  /// 由 DAO 归一化到该周周一（§2.1）。周数越界直接拒绝，不静默夹取。
  Future<Semester> createSemester({
    required String name,
    required DateTime firstWeekDate,
    int totalWeeks = Semester.defaultTotalWeeks,
  }) async {
    _check(name, totalWeeks);
    return _services.semesterDao.insert(
      name: name.trim(),
      firstWeekMonday: firstWeekDate,
      totalWeeks: totalWeeks,
    );
  }

  /// 保存学期配置（名称 + 开学周 + 总周数），**一次 UPDATE 写完**。
  ///
  /// 不要退回成「三个 setter 依次调」：每个 setter 都拿**同一份旧快照**
  /// `copyWith` 后整行写回，于是后一次把前一次的改动原样盖回去——用户改了总周数
  /// 点保存，库里最后只剩开学日期是新值。2026-10-18 用户报「点了像没点到」
  /// 就是这个（`course_setup.dart` 与向导步 3 两处都踩了）。
  Future<Semester> saveSemester(
    Semester semester, {
    required String name,
    required DateTime firstWeekDate,
    required int totalWeeks,
  }) async {
    _check(name, totalWeeks);
    final Semester next = semester.copyWith(
      name: name.trim(),
      firstWeekMonday: Semester.mondayOf(firstWeekDate),
      totalWeeks: totalWeeks,
    );
    await _services.semesterDao.update(next);
    return next;
  }

  /// 把学期总周数**抬到** [needed]（导入发现课程周次超出学期长度时用）。
  ///
  /// 只抬不缩：缩周数会让已有课程翻不到，那属于用户自己要在学期设置里做的事。
  /// 返回真正生效的学期；无需改动（或还没有学期）返回 null。
  Future<Semester?> raiseTotalWeeks(int needed) async {
    final Semester? s = await activeSemester();
    if (s == null || s.totalWeeks >= needed) return null;
    final int target =
        needed > Semester.maxTotalWeeks ? Semester.maxTotalWeeks : needed;
    final Semester next = s.copyWith(totalWeeks: target);
    await _services.semesterDao.update(next);
    return next;
  }

  void _check(String name, int totalWeeks) {
    if (name.trim().isEmpty) throw ArgumentError('学期名称不能为空');
    if (totalWeeks < Semester.minTotalWeeks ||
        totalWeeks > Semester.maxTotalWeeks) {
      throw ArgumentError('学期总周数必须在 ${Semester.minTotalWeeks}~'
          '${Semester.maxTotalWeeks}，收到 $totalWeeks');
    }
  }

  /// 默认作息表，没有就建一张（当前版本恒为 `semester_id IS NULL` 那一张）。
  Future<TimeTable> ensureDefaultTimetable() async {
    final TimeTable? existing = await _services.semesterDao.findDefaultTimetable();
    return existing ??
        await _services.semesterDao.createTimetable(name: '默认作息');
  }

  /// 默认作息表的节次，按节次升序。
  Future<List<TimeDetail>> loadDefaultDetails() async {
    final TimeTable table = await ensureDefaultTimetable();
    return _services.semesterDao.findDetails(table.id);
  }

  /// 保存作息表。**返回 null 表示成功**，否则是可直接展示的校验错误摘要
  /// （§2.3：时间必须递增、不重叠；校验不过**一行都不写**）。
  Future<String?> saveDefaultTimetable(List<TimeDetail> details) async {
    final String? error = validateTimeDetails(details);
    if (error != null) return error;
    final TimeTable table = await ensureDefaultTimetable();
    await _services.semesterDao.replaceDetails(
      table.id,
      <TimeDetail>[
        for (final TimeDetail d in details)
          d.timetableId == table.id ? d : _retarget(d, table.id),
      ],
    );
    return null;
  }

  static TimeDetail _retarget(TimeDetail d, String timetableId) => TimeDetail(
        id: d.id,
        timetableId: timetableId,
        section: d.section,
        startMinutes: d.startMinutes,
        endMinutes: d.endMinutes,
      );
}

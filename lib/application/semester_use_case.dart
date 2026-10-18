import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/data/semester_dao.dart';
import 'package:qingdan/domain/default_timetable.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

/// 学期用例（M6-D §6.1，F28 / F30 的配置部分）。
///
/// UI 层只能调这里（AGENTS.md 铁律）。写库与记 op-log 由 DAO 在同一事务内完成；
/// 作息**模板库**的部分拆到 `timetable_use_case.dart`。
class SemesterUseCase {
  SemesterUseCase(this._services);

  final AppServices _services;

  SemesterDao get _dao => _services.semesterDao;

  Future<Semester?> activeSemester() => _dao.findActive();

  Future<List<Semester>> allSemesters() => _dao.findAll();

  /// 新建学期：同事务「插学期 → 建该学期专属作息 → 从 [templateId] 复制全部
  /// 节次快照」（§6.1，顺序即 `kEntityTypes` 的外键顺序）。改模板不影响已建
  /// 学期，改学期作息不污染模板——复制的就是快照。
  ///
  /// [firstWeekDate] 可以是开学第一周的**任意一天**，归一化到该周周一（§2.1）。
  /// [templateId] 缺省为内置模板——契约签名是 required，但既有 features 调用点
  /// 在 M6-D §7 界面并行改造前还不带该参数，给默认值让它们保持可编译。
  /// [setActive] 默认 true（§7.2「创建后设为当前学期」默认开）。
  Future<Semester> createSemester({
    required String name,
    required DateTime firstWeekDate,
    int totalWeeks = Semester.defaultTotalWeeks,
    String templateId = kBuiltInTimetableId,
    bool setActive = true,
  }) async {
    _check(name, totalWeeks);
    final ({Semester semester, TimeTable timetable}) created =
        await _dao.insertSemesterWithTemplate(
      name: name.trim(),
      firstWeekMonday: firstWeekDate,
      totalWeeks: totalWeeks,
      templateId: templateId,
      setActive: setActive,
    );
    return created.semester;
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
    await _dao.update(next);
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
    await _dao.update(next);
    return next;
  }

  /// 切换当前学期。**不记 op-log**：`is_active` 是设备本地列、上云被剔除
  /// （§四），记意图只会产生一条被剔成空白的变更，白跑一轮同步。
  Future<void> setActiveSemester(String id) => _dao.setActiveSemester(id);

  /// 删除学期：同事务物理删 courses → time_details → timetables → semesters，
  /// 每步 append delete 意图（§6.1，四类都是同步实体，漏一步另一端留着）。
  /// 课程**不进回收站**（回收站只管待办任务），确认框文案由 UI 负责写清
  /// 「无法撤销」并带上 `courseCountForDeletion` 的连带数量。
  ///
  /// 只剩一个学期时拒删（`StateError('至少保留一个学期')`）：删光了
  /// `findActive()` 返回 null，整个课表页空白且无从恢复。
  /// 删的是当前学期 → 把剩下的 `created_time` 最新一个置为 active
  /// （走 `setActiveSemester`，不记 op-log）。
  Future<void> deleteSemester(String id) async {
    final List<Semester> all = await _dao.findAll();
    if (all.length <= 1) throw StateError('至少保留一个学期');
    final Semester? target =
        all.where((Semester s) => s.id == id).firstOrNull;
    if (target == null) return;
    final bool wasActive = target.isActive;
    await _dao.deleteSemesterCascade(id);
    if (!wasActive) return;
    final List<Semester> rest = await _dao.findAll();
    if (rest.isEmpty) return;
    Semester newest = rest.first;
    for (final Semester s in rest) {
      final DateTime a = s.createdTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime b =
          newest.createdTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (a.isAfter(b)) newest = s;
    }
    await _dao.setActiveSemester(newest.id);
  }

  /// 该学期课程条数（含软删），给删除确认框写「会连带删除 N 门课程」用。
  Future<int> courseCountForDeletion(String semesterId) =>
      _dao.countCoursesForSemester(semesterId);

  void _check(String name, int totalWeeks) {
    if (name.trim().isEmpty) throw ArgumentError('学期名称不能为空');
    if (totalWeeks < Semester.minTotalWeeks ||
        totalWeeks > Semester.maxTotalWeeks) {
      throw ArgumentError('学期总周数必须在 ${Semester.minTotalWeeks}~'
          '${Semester.maxTotalWeeks}，收到 $totalWeeks');
    }
  }

  // ---- 旧「匿名默认作息」路径（v6 前的形状，features 并行改造期继续可用）----

  /// 默认作息表，没有就建一张（当前版本恒为 `semester_id IS NULL` 那一张）。
  Future<TimeTable> ensureDefaultTimetable() async {
    final TimeTable? existing = await _dao.findDefaultTimetable();
    return existing ?? await _dao.createTimetable(name: '默认作息');
  }

  /// 默认作息表的节次，按节次升序。
  ///
  /// **只给「还没有学期」与老库回落用**。课表页 / 向导步 3 / 「学期与作息」弹层
  /// 这些**已经按学期**的地方一律用 [loadDetailsForSemester]——2026-10-19 真机
  /// 就是栽在这里：写路径 M6-D 起按学期，读路径还恒读这张匿名表，于是两个学期
  /// 各自的 12 节永远读不到，课表页说「作息表还是空的」。
  Future<List<TimeDetail>> loadDefaultDetails() async {
    final TimeTable table = await ensureDefaultTimetable();
    return _dao.findDetails(table.id);
  }

  /// [semesterId] 那个学期**该用哪张作息表**：先取它自己的行（M6-D 建学期时
  /// 从模板复制出来的那一份），没有就回落到老的匿名默认表。
  ///
  /// 回落是给**v6 之前建的学期**用的：那时作息只有一张、`semester_id IS NULL`，
  /// 老库升级上来的学期根本没有配套作息行。不回落的话这些学期的课表页会直接
  /// 空掉——比修之前更糟，所以这条回落由 `semester_timetable_read_test.dart`
  /// 单独钉住，不许哪天当成多余的兜底删掉。
  Future<TimeTable> timetableForSemester(String semesterId) async {
    final TimeTable? own = await _dao.findTimetableForSemester(semesterId);
    return own ?? await ensureDefaultTimetable();
  }

  /// [semesterId] 那个学期的节次，按节次升序；[semesterId] 为 null（还没建
  /// 学期）时读匿名默认表。**读写必须共用 [timetableForSemester] 这一张表**，
  /// 否则就是「显示本学期的、保存写进老表」——用户点完保存重读还是旧值。
  Future<List<TimeDetail>> loadDetailsForSemester(String? semesterId) async {
    if (semesterId == null) return loadDefaultDetails();
    final TimeTable table = await timetableForSemester(semesterId);
    return _dao.findDetails(table.id);
  }

  /// 整表保存 [semesterId] 那一学期的作息（表解析同 [timetableForSemester]）。
  ///
  /// **返回 null 表示成功**，否则是可直接展示的校验错误摘要（§2.3，
  /// 校验不过一行都不写）。[semesterId] 为 null = 写匿名默认表（老库形状）。
  Future<String?> saveDetailsForSemester(
    String? semesterId,
    List<TimeDetail> details,
  ) async {
    final String? error = validateTimeDetails(details);
    if (error != null) return error;
    final TimeTable table = semesterId == null
        ? await ensureDefaultTimetable()
        : await timetableForSemester(semesterId);
    await _dao.replaceDetails(
      table.id,
      <TimeDetail>[
        for (final TimeDetail d in details)
          d.timetableId == table.id ? d : _retarget(d, table.id),
      ],
    );
    return null;
  }

  /// 保存匿名默认作息（v6 前的老路径；[semesterId] 已知时改用
  /// [saveDetailsForSemester]，别把新学期的节次写进这张公用表）。
  Future<String?> saveDefaultTimetable(List<TimeDetail> details) =>
      saveDetailsForSemester(null, details);

  static TimeDetail _retarget(TimeDetail d, String timetableId) => TimeDetail(
        id: d.id,
        timetableId: timetableId,
        section: d.section,
        startMinutes: d.startMinutes,
        endMinutes: d.endMinutes,
      );
}

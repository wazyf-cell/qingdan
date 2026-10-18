import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/data/semester_dao.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

/// 作息模板库用例（M6-D §6.2）。
///
/// 模板 = `semester_id IS NULL AND is_template = 1` 的作息表行；用户自建的
/// 模板**参与同步**（`timetable` / `time_detail` 本就是同步实体，两台设备都
/// 该看到），只有 `is_builtin = 1` 那份不同步——靠「永不给它记意图」实现
/// （见 `migration_v6.dart`），本用例的所有写路径都先过内置守卫。
///
/// UI 层只能调这里（AGENTS.md 铁律）；写库与记 op-log 由 DAO 在同一事务内完成。
class TimetableUseCase {
  TimetableUseCase(this._services);

  final AppServices _services;

  SemesterDao get _dao => _services.semesterDao;

  /// 模板列表（内置排最前，其余按创建时间）。
  Future<List<TimeTable>> templates() => _dao.findTemplates();

  /// 新建模板。三种来源按优先级取一：
  /// [copyFromId] 复制现有模板（含内置——复制出来的是**新行**，与原模板此
  /// 后互不影响，这就是「复制为自定义」的路径）；否则用 [generated]
  /// （快速生成表单的产物，先过 `validateTimeDetails`，非法直接拒）；
  /// 都缺省 = 空白模板。
  Future<TimeTable> createTemplate({
    required String name,
    String? copyFromId,
    List<TimeDetail>? generated,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('模板名称不能为空');
    if (copyFromId == null && generated != null) {
      final String? error = validateTimeDetails(generated);
      if (error != null) throw ArgumentError(error);
    }
    final TimeTable table =
        await _dao.insertTimetable(trimmed, isTemplate: true);
    final List<TimeDetail> source = copyFromId != null
        ? await _dao.findDetails(copyFromId)
        : (generated ?? const <TimeDetail>[]);
    if (source.isNotEmpty) {
      await _dao.replaceDetails(table.id, _fresh(table.id, source));
    }
    return table;
  }

  /// 模板改名。**内置模板不允许**（用户裁决：改名会让「大学默认」在两台
  /// 设备不一致，而它又不同步）；想改就「复制为自定义」。
  Future<void> renameTemplate(String id, String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('模板名称不能为空');
    final TimeTable table = await _requireTemplate(id);
    if (table.isBuiltin) throw StateError('内置模板不可改名');
    await _dao.renameTimetable(id, trimmed);
  }

  /// 删除模板（连同节次）。`is_builtin == 1` 抛 `StateError('内置模板不可删除')`。
  Future<void> deleteTemplate(String id) async {
    final TimeTable table = await _requireTemplate(id);
    if (table.isBuiltin) throw StateError('内置模板不可删除');
    await _dao.deleteTimetableCascade(id);
  }

  /// 模板节次，按节次升序。
  Future<List<TimeDetail>> templateDetails(String id) => _dao.findDetails(id);

  /// 整表保存模板节次。**返回 null 表示成功**，否则是可直接展示的校验错误
  /// 摘要（校验不过一行都不写，与 `saveDefaultTimetable` 同形）。
  Future<String?> saveTemplateDetails(
    String id,
    List<TimeDetail> next,
  ) async {
    final TimeTable table = await _requireTemplate(id);
    if (table.isBuiltin) {
      throw StateError('内置模板不可修改，请用「复制为自定义」后再编辑');
    }
    final String? error = validateTimeDetails(next);
    if (error != null) return error;
    await _dao.replaceDetails(id, _fresh(id, next));
    return null;
  }

  /// 「使用」= **复制快照**（§6.2）：把模板的节次时间写进该学期自己的作息行。
  /// 走 `replaceDetails` 的**按节次复用原 id**——同步侧才不会把「改了时间」
  /// 看成「一删一增」。复制后该学期作息与模板再无关系。
  ///
  /// 学期还没有专属作息行（v6 之前的老学期）时顺手补建一张
  /// `'<学期名> 作息'`，再灌内容。
  Future<void> applyTemplateToSemester({
    required String semesterId,
    required String templateId,
  }) async {
    final TimeTable template = await _requireExisting(templateId);
    final List<TimeDetail> source = await _dao.findDetails(template.id);
    TimeTable? target = await _dao.findTimetableForSemester(semesterId);
    if (target == null) {
      final Semester? semester = await _dao.findSemester(semesterId);
      if (semester == null) throw StateError('学期 $semesterId 不存在');
      target = await _dao.insertTimetable(
        '${semester.name} 作息',
        semesterId: semesterId,
      );
    }
    await _dao.replaceDetails(target.id, _fresh(target.id, source));
  }

  /// 取模板行并确认它是模板库条目（学期专属作息不许从这里删改）。
  Future<TimeTable> _requireTemplate(String id) async {
    final TimeTable table = await _requireExisting(id);
    if (!table.isTemplate || table.semesterId != null) {
      throw StateError('作息表 $id 不是模板库条目');
    }
    return table;
  }

  Future<TimeTable> _requireExisting(String id) async {
    final TimeTable? table = await _dao.findTimetableById(id);
    if (table == null) throw StateError('作息表 $id 不存在');
    return table;
  }

  /// 复制成挂在 [timetableId] 下的**新行**（id 一律清空交给 DAO 生成：
  /// 带着源行 id 去插会撞主键，而节次已存在的行走 `replaceDetails` 的
  /// update 分支、id 本来就会被复用，不经过这里）。
  static List<TimeDetail> _fresh(String timetableId, List<TimeDetail> src) =>
      <TimeDetail>[
        for (final TimeDetail d in src)
          TimeDetail(
            id: '',
            timetableId: timetableId,
            section: d.section,
            startMinutes: d.startMinutes,
            endMinutes: d.endMinutes,
          ),
      ];
}

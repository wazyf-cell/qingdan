part of 'semester_dao.dart';

/// M6-D §6.1/§6.2：模板库查询 + 学期级联事务（`SemesterDao` 的延伸实现）。
///
/// 拆成 part 文件的原因：`semester_dao.dart` 本体已 267 行、逼近 AGENTS.md 的
/// 300 行红线；这些方法需要同一库内的 `_db` / `_opLog` 私有字段，所以用
/// `part` 而不是第三个类。语义铁律与本体相同：**写库与 append op-log 必须
/// 在同一事务**；`is_builtin = 1` 的行**永不记意图**（内置模板不参与同步的
/// 实现手段，见 migration_v6.dart 文件头）。
extension SemesterDaoTermOps on SemesterDao {
  // ---- 查询 ----

  /// 模板库：`semester_id IS NULL AND is_template = 1`，内置模板排最前。
  Future<List<TimeTable>> findTemplates() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'timetables',
      where: 'semester_id IS NULL AND is_template = 1',
      orderBy: 'is_builtin DESC, created_time ASC',
    );
    return [for (final Map<String, Object?> r in rows) TimeTable.fromMap(r)];
  }

  Future<TimeTable?> findTimetableById(String id) async {
    final List<Map<String, Object?>> rows = await _db.query('timetables',
        where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : TimeTable.fromMap(rows.first);
  }

  /// 某学期自己的作息行（`is_template = 0`）。老库的学期可能还没有，调用方
  /// 拿到 null 时自行补建（`applyTemplateToSemester` 就走这条路）。
  Future<TimeTable?> findTimetableForSemester(String semesterId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'timetables',
      where: 'semester_id = ? AND is_template = 0',
      whereArgs: <Object?>[semesterId],
      orderBy: 'created_time ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : TimeTable.fromMap(rows.first);
  }

  Future<Semester?> findSemester(String id) async {
    final List<Map<String, Object?>> rows = await _db.query('semesters',
        where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : Semester.fromMap(rows.first);
  }

  // ---- 作息表行 / 模板的写 ----

  /// 建一张作息表行（模板或学期作息），事务内 insert + create 意图。
  Future<TimeTable> insertTimetable(
    String name, {
    String? semesterId,
    bool isTemplate = false,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final TimeTable table = TimeTable(
      id: IdGenerator.next(),
      name: name,
      semesterId: semesterId,
      isTemplate: isTemplate,
      createdTime: now,
      modifiedTime: now,
    );
    await _db.transaction((Transaction txn) async {
      await txn.insert('timetables', table.toMap());
      await _opLog.append(txn,
          entityType: OpLogEntityType.timetable,
          entityId: table.id,
          operation: OpLogOperation.create,
          changes: createChanges(table.toMap()));
    });
    return table;
  }

  /// 改作息表行名（模板改名 / 学期作息改名共用）。名字没变则整趟跳过，
  /// 不产生空意图。调用方负责内置行的改名拒绝（用例层守卫）。
  Future<void> renameTimetable(String id, String name) async {
    final TimeTable? existing = await findTimetableById(id);
    if (existing == null) throw StateError('作息表 $id 不存在');
    if (existing.name == name) return;
    final TimeTable next =
        existing.copyWith(name: name, modifiedTime: DateTime.now().toUtc());
    await _db.transaction((Transaction txn) async {
      await txn.update('timetables', next.toMap(),
          where: 'id = ?', whereArgs: <Object?>[id]);
      await _opLog.append(txn,
          entityType: OpLogEntityType.timetable,
          entityId: id,
          operation: OpLogOperation.update,
          changes: <FieldChange>[
            FieldChange(
                field: 'name', oldValue: existing.name, newValue: name),
          ]);
    });
  }

  /// 删一张作息表连同其节次，逐步 append delete 意图（timetable/time_detail
  /// 都是同步实体，漏一步另一台设备就留着孤儿行）。内置行带刀拒删——守卫
  /// 放在离写最近的地方，UI 忘了拦也不会把内置模板同步掉。
  Future<void> deleteTimetableCascade(String id) =>
      _db.transaction<void>((Transaction txn) => _deleteTimetableIn(txn, id));

  Future<void> _deleteTimetableIn(DatabaseExecutor txn, String timetableId) async {
    final List<Map<String, Object?>> rows = await txn.query('timetables',
        where: 'id = ?', whereArgs: <Object?>[timetableId], limit: 1);
    if (rows.isEmpty) return;
    if ((rows.first['is_builtin'] as int? ?? 0) == 1) {
      throw StateError('内置模板不可删除');
    }
    final List<TimeDetail> details = [
      for (final Map<String, Object?> r in await txn.query('time_details',
          where: 'timetable_id = ?', whereArgs: <Object?>[timetableId]))
        TimeDetail.fromMap(r),
    ];
    for (final TimeDetail d in details) {
      await txn.delete('time_details', where: 'id = ?', whereArgs: <Object?>[d.id]);
      await _opLog.append(txn,
          entityType: OpLogEntityType.timeDetail,
          entityId: d.id,
          operation: OpLogOperation.delete,
          changes: <FieldChange>[
            FieldChange(field: 'section', oldValue: d.section, newValue: null),
          ]);
    }
    await txn.delete('timetables', where: 'id = ?', whereArgs: <Object?>[timetableId]);
    await _opLog.append(txn,
        entityType: OpLogEntityType.timetable,
        entityId: timetableId,
        operation: OpLogOperation.delete,
        changes: <FieldChange>[
          FieldChange(
              field: 'name', oldValue: rows.first['name'] as String?, newValue: null),
        ]);
  }

  // ---- 学期级联（§6.1）----

  /// 新建学期：插学期 → 建该学期专属作息 → 从 [templateId] 复制全部节次，
  /// **三步在同一事务**、按 `kEntityTypes` 的外键顺序
  /// semester → timetable → time_detail 写入并逐条记意图。
  ///
  /// [setActive] 为 true 且库里已有学期时，同一事务里先清掉别人的 `is_active`
  /// （本地列，清标记不记 op-log）。模板内容在事务内读，避免「读时模板还在、
  /// 写时被删」留下半截学期。
  Future<({Semester semester, TimeTable timetable})> insertSemesterWithTemplate({
    required String name,
    required DateTime firstWeekMonday,
    required int totalWeeks,
    required String templateId,
    required bool setActive,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final bool isFirst = (await _db.query('semesters', limit: 1)).isEmpty;
    final bool active = setActive || isFirst;
    final Semester semester = Semester(
      id: IdGenerator.next(),
      name: name,
      firstWeekMonday: Semester.mondayOf(firstWeekMonday),
      totalWeeks: totalWeeks,
      isActive: active,
      createdTime: now,
      modifiedTime: now,
    );
    final TimeTable timetable = TimeTable(
      id: IdGenerator.next(),
      name: '$name 作息',
      semesterId: semester.id,
      createdTime: now,
      modifiedTime: now,
    );
    await _db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> tpl = await txn.query('timetables',
          where: 'id = ?', whereArgs: <Object?>[templateId], limit: 1);
      if (tpl.isEmpty) throw StateError('作息模板「$templateId」不存在');
      final List<TimeDetail> source = [
        for (final Map<String, Object?> r in await txn.query('time_details',
            where: 'timetable_id = ?',
            whereArgs: <Object?>[templateId],
            orderBy: 'section ASC'))
          TimeDetail.fromMap(r),
      ];
      if (active && !isFirst) {
        await txn.rawUpdate('UPDATE semesters SET is_active = 0');
      }
      await txn.insert('semesters', semester.toMap());
      await _opLog.append(txn,
          entityType: OpLogEntityType.semester,
          entityId: semester.id,
          operation: OpLogOperation.create,
          changes: createChanges(semester.toMap()));
      await txn.insert('timetables', timetable.toMap());
      await _opLog.append(txn,
          entityType: OpLogEntityType.timetable,
          entityId: timetable.id,
          operation: OpLogOperation.create,
          changes: createChanges(timetable.toMap()));
      for (final TimeDetail d in source) {
        final TimeDetail copy = TimeDetail(
          id: IdGenerator.next(),
          timetableId: timetable.id,
          section: d.section,
          startMinutes: d.startMinutes,
          endMinutes: d.endMinutes,
          createdTime: now,
          modifiedTime: now,
        );
        await txn.insert('time_details', copy.toMap());
        await _opLog.append(txn,
            entityType: OpLogEntityType.timeDetail,
            entityId: copy.id,
            operation: OpLogOperation.create,
            changes: createChanges(copy.toMap()));
      }
    });
    return (semester: semester, timetable: timetable);
  }

  /// 该学期的课程条数（含软删的），给「删除学期」确认框写连带数量用。
  Future<int> countCoursesForSemester(String semesterId) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM courses WHERE semester_id = ?',
        <Object?>[semesterId]);
    return rows.first['c']! as int;
  }

  /// 删除学期（§6.1）：**同一事务**里 courses（物理删，回收站只管任务）→
  /// 该学期作息的 time_details → 该学期的 timetables 行 → semesters 行，
  /// 每一步都 append delete 意图——四类都是同步实体，漏一步另一端就留着。
  /// 不能依赖 `ON DELETE SET NULL`：那会留下 `semester_id` 被清空的孤儿作息，
  /// 混进 `findDefaultTimetable()` 的视野。
  Future<void> deleteSemesterCascade(String semesterId) =>
      _db.transaction<void>((Transaction txn) async {
        final List<Map<String, Object?>> srow = await txn.query('semesters',
            where: 'id = ?', whereArgs: <Object?>[semesterId], limit: 1);
        if (srow.isEmpty) return;
        final List<Map<String, Object?>> courses = await txn.query('courses',
            where: 'semester_id = ?', whereArgs: <Object?>[semesterId]);
        for (final Map<String, Object?> c in courses) {
          await txn.delete('courses',
              where: 'id = ?', whereArgs: <Object?>[c['id']]);
          await _opLog.append(txn,
              entityType: OpLogEntityType.course,
              entityId: c['id']! as String,
              operation: OpLogOperation.delete,
              changes: <FieldChange>[
                FieldChange(
                    field: 'name',
                    oldValue: c['name'] as String?,
                    newValue: null),
              ]);
        }
        final List<Map<String, Object?>> tables = await txn.query('timetables',
            where: 'semester_id = ? AND is_builtin = 0',
            whereArgs: <Object?>[semesterId]);
        for (final Map<String, Object?> t in tables) {
          await _deleteTimetableIn(txn, t['id']! as String);
        }
        await txn.delete('semesters',
            where: 'id = ?', whereArgs: <Object?>[semesterId]);
        await _opLog.append(txn,
            entityType: OpLogEntityType.semester,
            entityId: semesterId,
            operation: OpLogOperation.delete,
            changes: <FieldChange>[
              FieldChange(
                  field: 'name',
                  oldValue: srow.first['name'] as String?,
                  newValue: null),
            ]);
      });
}

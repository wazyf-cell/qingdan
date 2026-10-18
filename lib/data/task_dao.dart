import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/field_change.dart';
import '../domain/ids.dart';
import '../domain/op_log_entry.dart';
import '../domain/task.dart';
import '../domain/task_priority.dart';
import 'op_log_writer.dart';
import 'row_diff.dart';

/// 任务 DAO（F2/F3/F4/F8/F9/F10）。
///
/// 写方法均持有独立事务并同步写 op-log（F38）。
/// 回收站语义（F4）：普通查询过滤 `deleted = 0`；移入回收站为
/// `deleted = 1` 状态变更（走 [update] 记流水）；彻底删除才物理 DELETE，
/// 其子任务由外键 CASCADE 清除。业务规则（如「完成后刷新 modifiedTime」）
/// 属用例层，DAO 只忠实落库。
class TaskDao {
  /// [opLog] 由 AppServices 注入（带本地写回调，M3 同步触发源）；
  /// 省略时退回无回调的 const 实例（既有调用点与测试不受影响）。
  TaskDao(this._db, {OpLogWriter? opLog})
      : _opLog = opLog ?? const OpLogWriter();

  final Database _db;
  final OpLogWriter _opLog;

  /// 未完成任务，按清单 + 手动排序（F8/F9 最高频路径）。
  /// [listId] 为 null 表示收集箱（`list_id IS NULL`，SQL 三值逻辑下 `= NULL` 永假）。
  Future<List<Task>> findActiveByList(String? listId) => listId == null
      ? _queryTasks(
          where: 'deleted = 0 AND completed = 0 AND list_id IS NULL',
          orderBy: 'sort_order ASC, modified_time DESC',
        )
      : _queryTasks(
          where: 'deleted = 0 AND completed = 0 AND list_id = ?',
          whereArgs: <Object?>[listId],
          orderBy: 'sort_order ASC, modified_time DESC',
        );

  /// 回收站（F4）：仅 deleted = 1。
  Future<List<Task>> findTrashed() => _queryTasks(
        where: 'deleted = 1',
        orderBy: 'deleted_time DESC',
      );

  /// 已完成历史（F8 智能清单「已完成」）。
  Future<List<Task>> findCompleted() => _queryTasks(
        where: 'deleted = 0 AND completed = 1',
        orderBy: 'completed_time DESC',
      );

  /// 全部未删除任务（F8 智能清单「所有」）。
  Future<List<Task>> findAllActive() => _queryTasks(
        where: 'deleted = 0',
        orderBy: 'sort_order ASC, modified_time DESC',
      );

  /// 标题 / 备注关键词搜索（F10）；空关键词返回空结果。
  Future<List<Task>> search(String keyword) {
    if (keyword.isEmpty) return Future<List<Task>>.value(<Task>[]);
    return _queryTasks(
      where: "deleted = 0 AND (title LIKE ? ESCAPE '\\' OR note LIKE ? ESCAPE '\\')",
      whereArgs: <Object?>['%${_escapeLike(keyword)}%', '%${_escapeLike(keyword)}%'],
      orderBy: 'modified_time DESC',
    );
  }

  Future<Task?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  /// 新建任务并记 create op-log。
  Future<Task> insert({
    required String title,
    String note = '',
    TaskPriority priority = TaskPriority.none,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? dueDate,
    String? listId,
    int sortOrder = 0,
    String? id,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final Task task = Task(
      id: id ?? IdGenerator.next(),
      title: title,
      note: note,
      priority: priority,
      startDate: startDate,
      endDate: endDate,
      dueDate: dueDate,
      listId: listId,
      createdTime: now,
      modifiedTime: now,
      sortOrder: sortOrder,
    );
    await _db.transaction((Transaction txn) async {
      await txn.insert('tasks', task.toMap());
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.task,
        entityId: task.id,
        operation: OpLogOperation.create,
        changes: createChanges(task.toMap()),
      );
    });
    return task;
  }

  /// 整体更新并记字段级 update op-log（含完成/取消完成、移入回收站、恢复）。
  Future<void> update(Task task) async {
    final Map<String, Object?>? before = await _rawRow(task.id);
    if (before == null) {
      throw StateError('Task ${task.id} not found');
    }
    final Map<String, Object?> after = task.toMap();
    final List<FieldChange> changes = diffRowMaps(before, after);
    if (changes.isEmpty) return;

    await _db.transaction((Transaction txn) async {
      await txn.update(
        'tasks',
        after,
        where: 'id = ?',
        whereArgs: <Object?>[task.id],
      );
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.task,
        entityId: task.id,
        operation: OpLogOperation.update,
        changes: changes,
      );
    });
  }

  /// 移入回收站（F4）并记 update op-log。
  Future<void> moveToTrash(String id, {DateTime? deletedTime}) async {
    final Task? task = await findById(id);
    if (task == null) return;
    await update(task.copyWith(
      deleted: true,
      deletedTime: deletedTime ?? DateTime.now().toUtc(),
    ));
  }

  /// 彻底删除（F4）并记 delete op-log；子任务随外键 CASCADE 清除。
  Future<void> deleteForever(String id) async {
    final Map<String, Object?>? row = await _rawRow(id);
    if (row == null) return;
    await _db.transaction((Transaction txn) async {
      await txn.delete('tasks', where: 'id = ?', whereArgs: <Object?>[id]);
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.task,
        entityId: id,
        operation: OpLogOperation.delete,
        changes: <FieldChange>[
          FieldChange(
              field: 'title', oldValue: row['title'] as String?, newValue: null),
        ],
      );
    });
  }

  Future<List<Task>> _queryTasks({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'tasks',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
    return [for (final Map<String, Object?> r in rows) Task.fromMap(r)];
  }

  Future<Map<String, Object?>?> _rawRow(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// LIKE 通配符转义（配合 ESCAPE '\\'，避免用户输入 % _ 被当通配符）。
  static String _escapeLike(String input) =>
      input.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}

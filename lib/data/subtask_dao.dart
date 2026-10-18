import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/field_change.dart';
import '../domain/ids.dart';
import '../domain/op_log_entry.dart';
import '../domain/task.dart';
import 'op_log_writer.dart';
import 'row_diff.dart';

/// 子任务 DAO（F5，单层检查事项）。
///
/// 写方法均持有独立事务并同步写 op-log（F38）。
/// 子任务随父任务彻底删除（外键 CASCADE）；父任务移入回收站不连带删子任务。
/// 进度统计（「1/3」）属用例层职责，DAO 不做规则判断。
class SubtaskDao {
  /// [opLog] 由 AppServices 注入（带本地写回调，M3 同步触发源）；
  /// 省略时退回无回调的 const 实例（既有调用点与测试不受影响）。
  SubtaskDao(this._db, {OpLogWriter? opLog})
      : _opLog = opLog ?? const OpLogWriter();

  final Database _db;
  final OpLogWriter _opLog;

  /// 父任务的子任务列表，按 sort_order 升序。
  Future<List<Subtask>> findByTask(String taskId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'subtasks',
      where: 'task_id = ?',
      whereArgs: <Object?>[taskId],
      orderBy: 'sort_order ASC',
    );
    return [for (final Map<String, Object?> r in rows) Subtask.fromMap(r)];
  }

  Future<Subtask?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'subtasks',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Subtask.fromMap(rows.first);
  }

  /// 新建子任务并记 create op-log。
  Future<Subtask> insert({
    required String taskId,
    required String title,
    int sortOrder = 0,
    String? id,
  }) async {
    final Subtask subtask = Subtask(
      id: id ?? IdGenerator.next(),
      taskId: taskId,
      title: title,
      sortOrder: sortOrder,
      modifiedTime: DateTime.now().toUtc(),
    );
    await _db.transaction((Transaction txn) async {
      await txn.insert('subtasks', subtask.toMap());
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.subtask,
        entityId: subtask.id,
        operation: OpLogOperation.create,
        changes: createChanges(subtask.toMap()),
      );
    });
    return subtask;
  }

  /// 更新（勾选 / 改标题 / 排序）并记字段级 update op-log。
  Future<void> update(Subtask subtask) async {
    final List<Map<String, Object?>> before = await _db.query(
      'subtasks',
      where: 'id = ?',
      whereArgs: <Object?>[subtask.id],
      limit: 1,
    );
    if (before.isEmpty) {
      throw StateError('Subtask ${subtask.id} not found');
    }
    final Map<String, Object?> after = subtask.toMap();
    final List<FieldChange> changes = diffRowMaps(before.first, after);
    if (changes.isEmpty) return;

    await _db.transaction((Transaction txn) async {
      await txn.update(
        'subtasks',
        after,
        where: 'id = ?',
        whereArgs: <Object?>[subtask.id],
      );
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.subtask,
        entityId: subtask.id,
        operation: OpLogOperation.update,
        changes: changes,
      );
    });
  }

  /// 物理删除子任务并记 delete op-log。
  Future<void> delete(String id) async {
    final List<Map<String, Object?>> before = await _db.query(
      'subtasks',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (before.isEmpty) return;
    await _db.transaction((Transaction txn) async {
      await txn
          .delete('subtasks', where: 'id = ?', whereArgs: <Object?>[id]);
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.subtask,
        entityId: id,
        operation: OpLogOperation.delete,
        changes: <FieldChange>[
          FieldChange(
            field: 'title',
            oldValue: before.first['title'] as String?,
            newValue: null,
          ),
        ],
      );
    });
  }
}

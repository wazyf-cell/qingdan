import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/field_change.dart';
import '../domain/ids.dart';
import '../domain/op_log_entry.dart';
import '../domain/task_list.dart';
import 'op_log_writer.dart';
import 'row_diff.dart';

/// 清单 DAO（F6）。
///
/// 写方法均持有独立事务并同步写 op-log（F38）。
/// 清单删除为物理删除（回收站语义只针对任务，见迁移 v2 注释）。
class TaskListDao {
  /// [opLog] 由 AppServices 注入（带本地写回调，M3 同步触发源）；
  /// 省略时退回无回调的 const 实例（既有调用点与测试不受影响）。
  TaskListDao(this._db, {OpLogWriter? opLog})
      : _opLog = opLog ?? const OpLogWriter();

  final Database _db;
  final OpLogWriter _opLog;

  /// 全部清单，按 sort_order 升序（F6 侧栏排序）。
  Future<List<TaskList>> findAll() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'lists',
      orderBy: 'sort_order ASC, name ASC',
    );
    return [for (final Map<String, Object?> r in rows) TaskList.fromMap(r)];
  }

  Future<TaskList?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'lists',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : TaskList.fromMap(rows.first);
  }

  /// 新建清单并记 create op-log。
  Future<TaskList> insert({
    required String name,
    int sortOrder = 0,
    String? id,
  }) async {
    final TaskList list = TaskList(
      id: id ?? IdGenerator.next(),
      name: name,
      sortOrder: sortOrder,
      createdTime: DateTime.now().toUtc(),
      modifiedTime: DateTime.now().toUtc(),
    );
    await _db.transaction((Transaction txn) async {
      await txn.insert('lists', list.toMap());
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.list,
        entityId: list.id,
        operation: OpLogOperation.create,
        changes: createChanges(list.toMap()),
      );
    });
    return list;
  }

  /// 重命名 / 改排序并记字段级 update op-log。
  Future<void> update(TaskList list) async {
    final List<Map<String, Object?>> before = await _db.query(
      'lists',
      where: 'id = ?',
      whereArgs: <Object?>[list.id],
      limit: 1,
    );
    if (before.isEmpty) {
      throw StateError('TaskList ${list.id} not found');
    }
    final Map<String, Object?> after = list.toMap();
    final List<FieldChange> changes =
        diffRowMaps(before.first, after);
    if (changes.isEmpty) return;

    await _db.transaction((Transaction txn) async {
      await txn.update(
        'lists',
        after,
        where: 'id = ?',
        whereArgs: <Object?>[list.id],
      );
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.list,
        entityId: list.id,
        operation: OpLogOperation.update,
        changes: changes,
      );
    });
  }

  /// 物理删除清单并记 delete op-log。
  /// 关联任务由外键 ON DELETE SET NULL 移入收集箱（不删任务）。
  Future<void> delete(String id) async {
    final TaskList? existing = await findById(id);
    if (existing == null) return;
    await _db.transaction((Transaction txn) async {
      await txn.delete('lists', where: 'id = ?', whereArgs: <Object?>[id]);
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.list,
        entityId: id,
        operation: OpLogOperation.delete,
        changes: <FieldChange>[
          FieldChange(field: 'name', oldValue: existing.name, newValue: null),
        ],
      );
    });
  }
}

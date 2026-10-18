import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/field_change.dart';
import '../domain/ids.dart';
import '../domain/op_log_entry.dart';
import '../domain/tag.dart';
import 'op_log_writer.dart';
import 'row_diff.dart';

/// 标签 DAO 与任务↔标签关联 DAO（F11，P1：表与 DAO 在 M1 就位，暂无用例/UI）。
class TagDao {
  /// [opLog] 由 AppServices 注入（带本地写回调，M3 同步触发源）；
  /// 省略时退回无回调的 const 实例（既有调用点与测试不受影响）。
  TagDao(this._db, {OpLogWriter? opLog})
      : _opLog = opLog ?? const OpLogWriter();

  final Database _db;
  final OpLogWriter _opLog;

  Future<List<Tag>> findAll() async {
    final List<Map<String, Object?>> rows =
        await _db.query('tags', orderBy: 'name ASC');
    return [for (final Map<String, Object?> r in rows) Tag.fromMap(r)];
  }

  Future<Tag?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'tags',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Tag.fromMap(rows.first);
  }

  /// 某任务的全部标签（F11 详情展示）。
  Future<List<Tag>> findByTask(String taskId) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery('''
      SELECT t.* FROM tags t
      JOIN task_tags tt ON tt.tag_id = t.id
      WHERE tt.task_id = ?
      ORDER BY t.name ASC
    ''', <Object?>[taskId]);
    return [for (final Map<String, Object?> r in rows) Tag.fromMap(r)];
  }

  /// 挂标签到任务（幂等：已存在则跳过）。
  Future<void> attachToTask({required String taskId, required String tagId}) async {
    final int count = _countFirst(await _db.query(
      'task_tags',
      where: 'task_id = ? AND tag_id = ?',
      whereArgs: <Object?>[taskId, tagId],
      limit: 1,
    ));
    if (count > 0) return;
    final TaskTag link = TaskTag(taskId: taskId, tagId: tagId);
    await _db.transaction((Transaction txn) async {
      await txn.insert('task_tags', link.toMap());
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.taskTag,
        entityId: '$taskId:$tagId',
        operation: OpLogOperation.create,
        changes: <FieldChange>[
          FieldChange(field: 'tagId', oldValue: null, newValue: tagId),
        ],
      );
    });
  }

  /// 从任务摘除标签（幂等）。
  Future<void> detachFromTask({
    required String taskId,
    required String tagId,
  }) async {
    final int count = _countFirst(await _db.query(
      'task_tags',
      where: 'task_id = ? AND tag_id = ?',
      whereArgs: <Object?>[taskId, tagId],
      limit: 1,
    ));
    if (count == 0) return;
    await _db.transaction((Transaction txn) async {
      await txn.delete(
        'task_tags',
        where: 'task_id = ? AND tag_id = ?',
        whereArgs: <Object?>[taskId, tagId],
      );
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.taskTag,
        entityId: '$taskId:$tagId',
        operation: OpLogOperation.delete,
        changes: <FieldChange>[],
      );
    });
  }

  /// 新建标签并记 create op-log。
  Future<Tag> insert({required String name, String? color, String? id}) async {
    final Tag tag = Tag(
      id: id ?? IdGenerator.next(),
      name: name,
      color: color,
      modifiedTime: DateTime.now().toUtc(),
    );
    await _db.transaction((Transaction txn) async {
      await txn.insert('tags', tag.toMap());
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.tag,
        entityId: tag.id,
        operation: OpLogOperation.create,
        changes: createChanges(tag.toMap()),
      );
    });
    return tag;
  }

  /// 更新标签并记字段级 update op-log。
  Future<void> update(Tag tag) async {
    final List<Map<String, Object?>> before = await _db.query(
      'tags',
      where: 'id = ?',
      whereArgs: <Object?>[tag.id],
      limit: 1,
    );
    if (before.isEmpty) {
      throw StateError('Tag ${tag.id} not found');
    }
    final Map<String, Object?> after = tag.toMap();
    final List<FieldChange> changes = diffRowMaps(before.first, after);
    if (changes.isEmpty) return;

    await _db.transaction((Transaction txn) async {
      await txn.update(
        'tags',
        after,
        where: 'id = ?',
        whereArgs: <Object?>[tag.id],
      );
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.tag,
        entityId: tag.id,
        operation: OpLogOperation.update,
        changes: changes,
      );
    });
  }

  /// 物理删除标签并记 delete op-log；关联行由外键 CASCADE 清除。
  Future<void> delete(String id) async {
    final Tag? existing = await findById(id);
    if (existing == null) return;
    await _db.transaction((Transaction txn) async {
      await txn.delete('tags', where: 'id = ?', whereArgs: <Object?>[id]);
      await _opLog.append(
        txn,
        entityType: OpLogEntityType.tag,
        entityId: id,
        operation: OpLogOperation.delete,
        changes: <FieldChange>[
          FieldChange(field: 'name', oldValue: existing.name, newValue: null),
        ],
      );
    });
  }

  static int _countFirst(List<Map<String, Object?>> rows) => rows.isEmpty ? 0 : 1;
}

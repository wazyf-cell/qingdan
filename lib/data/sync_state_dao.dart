import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

/// sync_state 表的一行：某实体的同步基线。
class SyncStateRow {
  const SyncStateRow({
    required this.entityType,
    required this.entityId,
    required this.rev,
    required this.syncedAt,
    this.baseJson,
    this.baseEtag,
    this.deviceId,
  });

  factory SyncStateRow.fromMap(Map<String, Object?> row) => SyncStateRow(
        entityType: row['entity_type']! as String,
        entityId: row['entity_id']! as String,
        baseJson: row['base_json'] as String?,
        baseEtag: row['base_etag'] as String?,
        rev: row['rev']! as int,
        deviceId: row['device_id'] as String?,
        syncedAt: row['synced_at']! as int,
      );

  final String entityType;
  final String entityId;

  /// 上次同步成功的实体快照 JSON（三路合并的 base）。
  /// 可为 null：拉取到远端实体但尚未形成本地基线的中间态。
  final String? baseJson;

  /// 远端裸 etag（CAS 用，见方案设计 §5.2）。
  final String? baseEtag;
  final int rev;
  final String? deviceId;
  final int syncedAt;
}

/// 同步基线 DAO（M2，方案设计 §5.1 / §5.4）。
///
/// 设计要点：
/// - 本 DAO **不写 op-log**：落基线是系统动作不是用户操作，混入 op-log 会
///   污染审计语义（v1.4 定案，方案设计 §5.4 第 4 步）；
/// - **所有写都是显式 SQL upsert/UPDATE**，不走领域模型 copyWith：实体模型的
///   `copyWith(lastSyncedJson: null)` 是 no-op（`??` 合并缺陷），而
///   「清空基线（远端权威覆盖本地 / 实体已删但基线待墓碑化）」必须能真把
///   base_json 写成 NULL——SQL 层面传 null 就是 null，缺陷自动绕过；
/// - 将来「落基线 + 标 op-log uploaded」必须由调用方在同一事务内完成，
///   故暴露 `upsertBaseIn` / `clearBaseIn` 的 executor 版本供事务内复用。
class SyncStateDao {
  SyncStateDao(this._db);

  final Database _db;

  static const String _table = 'sync_state';

  Future<SyncStateRow?> find(String entityType, String entityId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
      limit: 1,
    );
    return rows.isEmpty ? null : SyncStateRow.fromMap(rows.first);
  }

  /// 读某类型全部基线（同步引擎按域批量比较 base vs current 用）。
  Future<Map<String, SyncStateRow>> findAllFor(String entityType) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _table,
      where: 'entity_type = ?',
      whereArgs: <Object?>[entityType],
    );
    return <String, SyncStateRow>{
      for (final Map<String, Object?> r in rows)
        r['entity_id']! as String: SyncStateRow.fromMap(r),
    };
  }

  /// 上传成功后落基线：rev 由本 DAO 内部读-改-写自增（每设备单调递增，
  /// 是并发检测依据，见方案设计 §5.4），调用方不必关心 rev 取值。
  Future<void> upsertBase({
    required String entityType,
    required String entityId,
    required String baseJson,
    String? baseEtag,
    required String deviceId,
  }) =>
      upsertBaseIn(
        _db,
        entityType: entityType,
        entityId: entityId,
        baseJson: baseJson,
        baseEtag: baseEtag,
        deviceId: deviceId,
      );

  /// [upsertBase] 的事务版本：落基线 + 标记 op-log uploaded 必须同事务
  /// （方案设计 §5.4 第 4 步），同步引擎在 txn 内调用本方法。
  Future<void> upsertBaseIn(
    DatabaseExecutor db, {
    required String entityType,
    required String entityId,
    required String baseJson,
    String? baseEtag,
    required String deviceId,
  }) async {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final int rev = await nextRevIn(db, entityType, entityId);
    await db.insert(
      _table,
      <String, Object?>{
        'entity_type': entityType,
        'entity_id': entityId,
        'base_json': baseJson,
        'base_etag': baseEtag,
        'rev': rev,
        'device_id': deviceId,
        'synced_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 显式清空基线（base_json = NULL），不走 copyWith（见类注释）。
  Future<void> clearBase(String entityType, String entityId) =>
      clearBaseIn(_db, entityType, entityId);

  /// [clearBase] 的事务版本，语义同 [upsertBaseIn]。
  ///
  /// 只清 base_json，保留 base_etag/rev/device_id/synced_at：
  /// rev 是「本设备写过几次基线」的计数，清快照不应归零（否则并发检测退化）。
  Future<void> clearBaseIn(
    DatabaseExecutor db,
    String entityType,
    String entityId,
  ) async {
    await db.update(
      _table,
      <String, Object?>{'base_json': null},
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
    );
  }

  /// 取该实体下一个 rev：现有行 rev + 1，无行从 1 起。
  Future<int> nextRev(String entityType, String entityId) =>
      nextRevIn(_db, entityType, entityId);

  Future<int> nextRevIn(
    DatabaseExecutor db,
    String entityType,
    String entityId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      _table,
      columns: <String>['rev'],
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
      limit: 1,
    );
    return rows.isEmpty ? 1 : (rows.first['rev']! as int) + 1;
  }
}

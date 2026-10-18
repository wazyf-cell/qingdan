/// 同步专用本地写入与读取层（**刻意不写 op-log**）。
///
/// ★ 为什么同步下载不走 DAO：
///   项目铁律「写实体 + 写 op-log 同事务」约束的是**用户操作**路径（DAO /
///   用例层）；同步下载是系统动作，方案设计 §5.4 已定调「上传成功是系统
///   动作不是用户操作」，本层据此把对应写路径也定为系统动作：实体表更新 +
///   sync_state 落基线在**同一事务**内完成，**不写 op-log**。
///   理由有三：
///     a) op-log 是审计日志，记录「用户干了什么」，机器合并不属于之；
///     b) 若写 op-log，下轮同步的意图推导会再消费这批「变更」（自反馈循环，
///        同步幂等被破坏）；
///     c) 原子性由 sqflite 事务保证——实体写成功而基线写失败会被整体回滚，
///        下一轮 sync 的 base-vs-current diff 不会把半同步状态再推一遍。
///   绕过 DAO 直接写表是刻意的：复用 DAO 必然带上 op-log（铁律在 DAO 内部
///   实现），那就只能靠「写完再删 op-log」这种更脆的方式维持审计语义。
library;

import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../data/sync_state_dao.dart';
import '../data/row_diff.dart' show camelFieldName;
import 'sync_serializer.dart';

/// 同步侧的本地表访问器。无状态（每次调用都从参数拿 db），便于测试直接构造。
class SyncStateWriter {
  const SyncStateWriter();

  /// merged / remote（camelCase 同步 JSON）→ 实体表行（snake_case）并 UPSERT，
  /// 与落基线同事务。rev / deviceId / sortOrder 不写入业务表：
  /// rev/deviceId 是同步元数据（sync_state 持有），sortOrder 走 order 实体。
  Future<void> writeRemoteState({
    required Database db,
    required SyncStateDao stateDao,
    required String type,
    required String entityId,
    required Map<String, Object?> merged,
    required String? baseEtag,
    required String deviceId,
  }) async {
    final String table = kEntityTable[type]!;
    final Map<String, Object?> row = toEntityRow(merged);
    row['id'] = entityId;
    final String baseJson = jsonEncodeLegacy(merged);
    await db.transaction((Transaction txn) async {
      if (table == 'semesters') {
        // 「当前学期」是设备本地状态，上云时被剔除（见 local_only_columns），
        // 所以 merged 里永远不会有它。而这里是 `INSERT OR REPLACE`——
        // **不显式给值就会吃到 DDL 的 `DEFAULT 1`**，拉一次对端学期本地就多一个
        // active，课表页读哪个学期变成看运气。读回本地原值是最保守的做法。
        final List<Map<String, Object?>> old = await txn.query(table,
            columns: <String>['is_active'],
            where: 'id = ?',
            whereArgs: <Object?>[entityId],
            limit: 1);
        row['is_active'] = old.isEmpty ? 0 : old.first['is_active'];
      }
      await txn.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await stateDao.upsertBaseIn(
        txn,
        entityType: type,
        entityId: entityId,
        baseJson: baseJson,
        baseEtag: baseEtag,
        deviceId: deviceId,
      );
    });
  }

  /// 远端新实体首次插入：插表 + 落基线（base = 远端 JSON，etag = 本次 get
  /// 的 etag）同事务。下一步不需要再上传它。
  Future<void> insertRemote({
    required Database db,
    required SyncStateDao stateDao,
    required String type,
    required Map<String, Object?> remote,
    required String deviceId,
    required String? etag,
  }) async {
    final String table = kEntityTable[type]!;
    final Map<String, Object?> row = toEntityRow(remote);
    row['id'] = remote['id']?.toString() ?? row['id'];
    if (table == 'semesters') {
      // 远端新学期一律「非当前」：本地已经有自己的当前学期，凭什么被另一台设备
      // 的浏览动作改掉（M6-D §四.2）。同 `INSERT OR REPLACE` 的 DEFAULT 1 陷阱。
      row['is_active'] = 0;
    }
    final String baseJson = jsonEncodeLegacy(remote);
    await db.transaction((Transaction txn) async {
      await txn.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await stateDao.upsertBaseIn(
        txn,
        entityType: type,
        entityId: row['id']! as String,
        baseJson: baseJson,
        baseEtag: etag,
        deviceId: deviceId,
      );
    });
  }

  /// 本地物理删（消费远端墓碑）：删行 + 清基线同事务，不写 op-log。
  Future<void> deleteLocal(
    Database db,
    SyncStateDao stateDao,
    String type,
    String entityId,
  ) async {
    final String table = kEntityTable[type]!;
    await db.transaction((Transaction txn) async {
      await txn.delete(table, where: 'id = ?', whereArgs: <Object?>[entityId]);
      await stateDao.clearBaseIn(txn, type, entityId);
    });
  }

  /// 只落基线（不上传、不改实体行的场景，如推送成功后的收尾）。
  Future<void> writeBase({
    required Database db,
    required SyncStateDao stateDao,
    required String entityType,
    required String entityId,
    required String baseJson,
    required String? baseEtag,
    required String deviceId,
  }) =>
      stateDao.upsertBaseIn(
        db,
        entityType: entityType,
        entityId: entityId,
        baseJson: baseJson,
        baseEtag: baseEtag,
        deviceId: deviceId,
      );

  /// 读单行实体（不存在返回 null）。
  Future<Map<String, Object?>?> readRow(
    Database db,
    String type,
    String entityId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      kEntityTable[type]!,
      where: 'id = ?',
      whereArgs: <Object?>[entityId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 读某类型全部实体行，按 id 索引。
  Future<Map<String, Map<String, Object?>>> readAllRows(
    Database db,
    String type,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(kEntityTable[type]!);
    return <String, Map<String, Object?>>{
      for (final Map<String, Object?> r in rows) r['id']! as String: r,
    };
  }

  /// camelCase 同步 JSON → snake_case 实体行（排除同步元数据键）。
  Map<String, Object?> toEntityRow(Map<String, Object?> syncJson) =>
      <String, Object?>{
        for (final MapEntry<String, Object?> e in syncJson.entries)
          if (e.key != 'rev' &&
            e.key != 'deviceId' &&
            e.key != 'sortOrder' &&
            !kLocalOnlyJsonKeys.contains(e.key))
            snakeCaseField(e.key): e.value,
      };
}

/// 行 Map → 同步 JSON（camelCase），排除非业务键（与 intent_resolver 的
/// `_rowToSyncJson` 同规则；该函数是库私有，这里按公开规则重写一份，
/// 两边由测试锁定一致）。
Map<String, Object?> rowToSyncJson(Map<String, Object?> row) =>
    <String, Object?>{
      for (final MapEntry<String, Object?> e in row.entries)
        if (e.key != 'last_synced_json' &&
            e.key != 'rev' &&
            e.key != 'device_id' &&
            e.key != 'sort_order' &&
            !kLocalOnlyRowColumns.contains(e.key))
          camelFieldName(e.key): e.value,
    };

/// camelCase → snake_case（`dueDate` → `due_date`）。写表用。
String snakeCaseField(String field) => field.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (Match m) => '_${m.group(0)!.toLowerCase()}',
    );

/// base_json 字符串 → 实体 Map；null / 空返回 null。
Map<String, Object?>? decodeBaseJson(String? baseJson) {
  if (baseJson == null) return null;
  return (jsonDecode(baseJson) as Map<Object?, Object?>).cast<String, Object?>();
}

/// jsonEncode 的别名占位：实体 JSON 都是小对象，普通 jsonEncode 够用；
/// 独立包装便于将来统一压缩/加密策略。
String jsonEncodeLegacy(Object? value) => jsonEncode(value);

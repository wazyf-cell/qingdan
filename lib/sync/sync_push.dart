/// 同步引擎的推送侧：把意图上传到云端，并落基线、消费 op-log。
///
/// 从 sync_engine.dart 拆出的职责（原 555 行 → 编排 / 拉取 / 推送三文件）：
/// 本文件只管「确定要推的东西怎么上去」，含条件写、412 冲突收敛、墓碑。
/// 拆开是为了能单独测试推送路径（双端测试里 `_pushUpsert` 的 412 分支
/// 是最难通过端到端触发的路径之一）。
library;

import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../data/sync_state_dao.dart';
import 'intent_resolver.dart';
import 'merge_engine.dart';
import 'sync_backend.dart';
import 'sync_report.dart';
import 'sync_serializer.dart';
import 'sync_state_writer.dart';

/// 推送器：一个实例绑定一个数据库与一个（已套计数的）backend。
class SyncPusher {
  // lint `prefer_initializing_formals` 在本类不适用：构造参数是公开类型
  // （backend / report），字段是私有（_backend / _report）；初始化形参要求
  // 二者同名，无法改写。
  // ignore_for_file: prefer_initializing_formals
  SyncPusher({
    required Database db,
    required SyncBackend backend,
    required SyncReport report,
  })  : _db = db,
        _backend = backend,
        _report = report,
        _stateDao = SyncStateDao(db);

  final Database _db;
  final SyncBackend _backend;
  final SyncReport _report;
  final SyncStateDao _stateDao;
  final SyncStateWriter _stateWriter = const SyncStateWriter();

  /// 上传一个 upsert 意图（条件写）。见类注释与 §5.4 第 3–4 步。
  Future<void> pushUpsert(
    SyncIntent intent,
    String deviceId,
    SyncStateRow? baseRow,
  ) async {
    // rev 盖章：sync_state 行数即本设备写基线次数，+1 保证单调递增。
    final int rev = (baseRow?.rev ?? 0) + 1;
    final Map<String, Object?> payload =
        stampSyncMeta(intent, rev: rev, deviceId: deviceId);
    final List<int> bytes = encodeEntityJson(payload);
    final String path = entityRemotePath(intent.entityType, intent.entityId);
    final String? ifMatch = baseRow?.baseEtag;

    String? newEtag;
    try {
      newEtag = await _backend.put(path, bytes, ifMatchEtag: ifMatch);
      _report.uploaded++;
    } on PreconditionFailedException {
      // 对端在我们上次同步之后写过该实体（本地 base 过期）。原则：云端
      // 已接收的变更不丢——把云端最新内容当远端重跑三路合并，合并结果
      // 再上传；若云端就是最新，合并结果 == 云端 → 本轮不再上传，等下轮
      // 拉取阶段自然对齐（unchanged / takeRemote 都不产生上传）。
      await _resolvePreconditionFailure(intent, payload, baseRow, deviceId, path);
      return;
    } catch (e) {
      _report.errors.add(e);
      return;
    }

    // 上传成功：落基线 + 消费 op-log（同事务，§5.4 第 4 步）。
    await _stateWriter.writeBase(
      db: _db,
      stateDao: _stateDao,
      entityType: intent.entityType,
      entityId: intent.entityId,
      baseJson: jsonEncodeLegacy(payload),
      baseEtag: newEtag,
      deviceId: deviceId,
    );
    consumeOpLogs(intent);
  }

  /// 412 分支：以对端为准重新收敛。抽成独立方法是因为它是**唯一**会被
  /// 端到端测试之外单独验证的复杂分支（多一次 get、可能多一次 put）。
  Future<void> _resolvePreconditionFailure(
    SyncIntent intent,
    Map<String, Object?> payload,
    SyncStateRow? baseRow,
    String deviceId,
    String path,
  ) async {
    final Map<String, Object?> remoteJson =
        decodeEntityJson((await _backend.get(path)).bytes);
    final MergeResult result = mergeEntity(
      current: payload,
      remote: remoteJson,
      base: decodeBaseJson(baseRow?.baseJson),
    );
    _report.conflicts += result.conflictedFields.length;

    if (result.type == MergeOutcomeType.takeRemote ||
        identical(result.merged, remoteJson)) {
      // 云端为准：本地 adopt 远端内容 + 落基线，不上传。
      final Map<String, Object?>? row =
          await _stateWriter.readRow(_db, intent.entityType, intent.entityId);
      if (row != null) {
        final ({List<int> bytes, String? etag}) again =
            await _backend.get(path);
        await _stateWriter.writeRemoteState(
          db: _db,
          stateDao: _stateDao,
          type: intent.entityType,
          entityId: intent.entityId,
          merged: remoteJson,
          baseEtag: again.etag,
          deviceId: deviceId,
        );
      }
      return;
    }

    final List<int> retry = encodeEntityJson(result.merged);
    try {
      final String? newEtag = await _backend.put(path, retry);
      _report.uploaded++;
      await _stateWriter.writeRemoteState(
        db: _db,
        stateDao: _stateDao,
        type: intent.entityType,
        entityId: intent.entityId,
        merged: result.merged,
        baseEtag: newEtag,
        deviceId: deviceId,
      );
      consumeOpLogs(intent);
    } catch (e) {
      _report.errors.add(e);
    }
  }

  /// 推送一个物理删除意图：删远端文件 + 写墓碑 + 清基线 + 消费 op-log。
  Future<void> pushDelete(SyncIntent intent) async {
    final String path = entityRemotePath(intent.entityType, intent.entityId);
    final String tombPath = tombstoneRemotePath(intent.entityId);
    // 本地已物理删（A 通道的前提），删远端文件 + 写墓碑。条件删的 ifMatch
    // 拿不到（本地没有远端快照），无条件删：ObjectNotFound 视为已删成功。
    try {
      await _backend.delete(path);
    } on ObjectNotFoundException {
      // 对端已删：正是我们要的终态。
    } catch (e) {
      _report.errors.add(e);
      return;
    }
    try {
      await _backend.put(
        tombPath,
        encodeTombstoneJson(
          entityType: intent.entityType,
          deletedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );
      _report.uploaded++;
    } catch (e) {
      _report.errors.add(e);
      return;
    }
    // 远端删除成功：本地实体行已不存在（物理删先于同步），只需清基线 +
    // 消费 op-log。基线行保留 rev（见 SyncStateDao.clearBaseIn 注释）。
    await _stateDao.clearBaseIn(_db, intent.entityType, intent.entityId);
    consumeOpLogs(intent);
  }

  /// 把参与本次意图推导的 op-log 行标 uploaded = 1。
  ///
  /// 注意：不在落基线的事务里（upsertBaseIn 是独立自动提交）——标记失败
  /// 只会导致下轮多推一次（幂等），不会丢数据；而把上传请求和本地事务绑成
  /// 一个跨 IO 的事务反而制造长事务。权衡后选择最终一致。
  void consumeOpLogs(SyncIntent intent) {
    if (intent.sourceOpLogIds.isEmpty) return;
    unawaited(
      _db
          .update(
        'op_log',
        <String, Object?>{
          'uploaded': 1,
          'uploaded_time': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        where:
            'id IN (${List.filled(intent.sourceOpLogIds.length, '?').join(',')})',
        whereArgs: intent.sourceOpLogIds,
      )
          .catchError((Object e) {
        // 标记失败只导致下轮多推一次（幂等），不丢数据；记进报告可见。
        _report.errors.add(e);
        return 0;
      }),
    );
  }
}

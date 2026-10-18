/// 同步引擎的拉取侧：列出远端、逐实体三路合并、写回本地、消费墓碑。
///
/// 从 sync_engine.dart 拆出的职责（原 555 行 → 编排 / 拉取 / 推送三文件）：
/// 本文件只管「云端有什么、和本地怎么合」。含 [_pullOne] 的四个分支
/// （本地无 → 插入；unchanged / takeRemote / merged / takeLocal）与墓碑处理。
library;

import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../data/sync_state_dao.dart';
import 'intent_resolver.dart';
import 'merge_engine.dart';
import 'sync_backend.dart';
import 'sync_report.dart';
import 'sync_serializer.dart';
import 'sync_state_writer.dart';

/// 拉取器：一个实例绑定一个数据库与一个（已套计数的）backend。
class SyncPuller {
  // lint `prefer_initializing_formals` 在本类不适用：构造参数是公开类型
  // （backend / report），字段是私有（_backend / _report）；初始化形参要求
  // 二者同名，无法改写。字段本身在下方已声明。
  // ignore_for_file: prefer_initializing_formals
  SyncPuller({
    required Database db,
    required SyncBackend backend,
    required SyncReport report,
    required SyncStateWriter stateWriter,
  })  : _db = db,
        _backend = backend,
        _report = report,
        _writer = stateWriter,
        _stateDao = SyncStateDao(db);

  final Database _db;
  final SyncBackend _backend;
  final SyncReport _report;
  final SyncStateWriter _writer;
  final SyncStateDao _stateDao;

  /// 拉取一个类型的远端状态并合并进本地。
  Future<void> pull(
    String type,
    String deviceId,
    Map<String, SyncStateRow> bases,
    List<SyncIntent> intents,
  ) async {
    // 本轮要删除的实体不参与合并（远端内容无意义，墓碑见 pullTombstones）。
    final Set<String> deleting = <String>{
      for (final SyncIntent i in intents)
        if (i.kind == SyncIntentKind.delete) i.entityId,
    };

    final String ns = 'entities/$type';
    final List<RemoteObject> remoteList = await _backend.list(ns);
    final Map<String, RemoteObject> byId = <String, RemoteObject>{
      for (final RemoteObject o in remoteList)
        if (entityIdOf(o.path, type) != null) entityIdOf(o.path, type)!: o,
    };

    for (final MapEntry<String, RemoteObject> entry in byId.entries) {
      final String entityId = entry.key;
      if (deleting.contains(entityId)) continue;
      try {
        await _pullOne(type, entityId, deviceId, bases[entityId]);
      } catch (e) {
        _report.errors.add(e);
      }
    }
    await pullTombstones(type, deviceId);
  }

  /// 单个远端实体 → 本地（插入 / 合并写回 / 不动）。
  Future<void> _pullOne(
    String type,
    String entityId,
    String deviceId,
    SyncStateRow? baseRow,
  ) async {
    final ({List<int> bytes, String? etag}) got =
        await _backend.get(entityRemotePath(type, entityId));
    final Map<String, Object?> remote = decodeEntityJson(got.bytes);

    final Map<String, Object?>? currentRow =
        await _writer.readRow(_db, type, entityId);
    final Map<String, Object?>? base = decodeBaseJson(baseRow?.baseJson);

    if (currentRow == null) {
      // 本地无、base 无 → 纯新增（设备2 首见设备1 建的任务走这里）。
      // 本地无但 base 有：本地在别处被物理删且 op-log 未消费——保守起见
      // 仍插入远端内容（物理删以墓碑/A 通道为准），避免拉取误删数据。
      if (base == null) {
        await _writer.insertRemote(
          db: _db,
          stateDao: _stateDao,
          type: type,
          remote: remote,
          deviceId: deviceId,
          etag: got.etag,
        );
        _report.downloaded++;
      }
      return;
    }

    final MergeResult result = mergeEntity(
      current: rowToSyncJson(currentRow),
      remote: remote,
      base: base,
    );
    _report.conflicts += result.conflictedFields.length;
    switch (result.type) {
      case MergeOutcomeType.unchanged:
        break;
      case MergeOutcomeType.takeRemote:
      case MergeOutcomeType.merged:
        // takeRemote/merged 都改了本地状态：写表 + 落基线（用远端 etag）
        // 同一事务。takeRemote 时 merged == remote 的业务内容。
        await _writer.writeRemoteState(
          db: _db,
          stateDao: _stateDao,
          type: type,
          entityId: entityId,
          merged: result.merged,
          baseEtag: got.etag,
          deviceId: deviceId,
        );
        _report.downloaded++;
        if (result.type == MergeOutcomeType.merged) _report.merged++;
      case MergeOutcomeType.takeLocal:
        // 本地更新：不写库；上传由意图推送环节收尾。
        break;
    }
  }

  /// 远端墓碑 → 本地实体物理删 + 清基线（同事务，不写 op-log，理由见
  /// sync_state_writer.dart 的库注释）。
  Future<void> pullTombstones(String type, String deviceId) async {
    final List<RemoteObject> tombstones = await _backend.list('tombstones');
    for (final RemoteObject o in tombstones) {
      final String? entityId = tombstoneIdOf(o.path);
      if (entityId == null) continue;
      final Map<String, Object?>? currentRow =
          await _writer.readRow(_db, type, entityId);
      if (currentRow == null) continue; // 本地本就没有（或已处理过）
      try {
        final Map<String, Object?> tomb =
            decodeTombstoneJson((await _backend.get(o.path)).bytes);
        if (tomb['type'] != type) continue; // 墓碑属于别的类型
        await _writer.deleteLocal(_db, _stateDao, type, entityId);
        _report.downloaded++;
      } catch (e) {
        _report.errors.add(e);
      }
    }
  }

  /// `entities/<type>/<id>.json` → id；不匹配返回 null。
  ///
  /// 扁平布局（2026-09-30 起）：原先正则多一段 `[^/]+/`（hash 前缀层），
  /// 与 entityRemotePath 一并改掉——两处必须同步，否则远端每个实体都认不出，
  /// 表现为静默丢弃全部远端数据。
  String? entityIdOf(String path, String type) {
    final RegExpMatch? m =
        RegExp('^entities/${RegExp.escape(type)}/(.+)\\.json\$').firstMatch(path);
    return m?.group(1);
  }

  /// `tombstones/<id>.json` → id；不匹配返回 null。
  String? tombstoneIdOf(String path) {
    final RegExpMatch? m =
        RegExp('^tombstones/(.+)\\.json\$').firstMatch(path);
    return m?.group(1);
  }
}

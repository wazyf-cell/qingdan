/// 同步引擎（M2，方案设计 §5.4：op-log + 字段级 LWW + 三路合并，云盘哑存储）。
///
/// 本文件只放**流程编排**；拉取、推送、本地表访问分别拆到：
///   - `sync_pull.dart`   SyncPuller   —— 列远端、三路合并、写回本地、消费墓碑
///   - `sync_push.dart`   SyncPusher   —— 条件写 upsert、412 收敛、墓碑、op-log 消费
///   - `sync_state_writer.dart`        —— 同步专用本地写入（**刻意不写 op-log**）
///   - `sync_serializer.dart`          —— 实体 ↔ JSON、云端路径
///   - `sync_report.dart`              —— 报告结构 + 请求计数装饰器
///
/// 主流程（每类型 task/list/subtask/tag 独立处理）：
/// 1. 推导意图：B = base vs current 终态 diff（intent_resolver），A = op-log
///    未上传物理删（兜底），convergeIntents 合并（A 优先）；
/// 2. 拉取远端：逐类型 list + get，本地无/基线无 → 插入本地；本地有 →
///    三路合并（merge_engine）写回；远端墓碑 → 本地物理删；
/// 3. 推送意图：upsert 走条件写（ifMatch = 上次成功的 etag），delete 走
///    条件删 + 写墓碑；412（对端先写过）时把云端最新内容当作远端重跑
///    合并，以对端为准收敛；
/// 4. 落基线：**与本地写同一事务**（见 sync_state_writer.dart），并消费
///    参与推导的 op-log 行（sourceOpLogIds）。
library;

import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../data/device_id.dart';
import '../data/sync_state_dao.dart';
import '../domain/op_log_entry.dart';
import 'intent_resolver.dart';
import 'sync_backend.dart';
import 'sync_pull.dart';
import 'sync_push.dart';
import 'sync_report.dart';
import 'sync_serializer.dart';
import 'sync_state_writer.dart';

/// 同步引擎。一个实例绑定一台设备的本地库；可复用（每次 [sync] 独立）。
class SyncEngine {
  SyncEngine({required SyncBackend backend, required Database db})
      : _db = db,
        _stateDao = SyncStateDao(db),
        _backend = CountingSyncBackend(backend, SyncReport()),
        _writer = const SyncStateWriter() {
    _puller = SyncPuller(
      db: db,
      backend: _backend,
      report: _report,
      stateWriter: _writer,
    );
    _pusher = SyncPusher(db: db, backend: _backend, report: _report);
  }

  final Database _db;
  final SyncStateDao _stateDao;
  final CountingSyncBackend _backend;
  final SyncStateWriter _writer;
  late final SyncPuller _puller;
  late final SyncPusher _pusher;

  /// 报告由 [CountingSyncBackend] 与本引擎共享同一实例（构造期传入）。
  SyncReport get _report => _backend.report;

  /// 执行一次完整同步（先拉后推），返回报告。
  Future<SyncReport> sync() async {
    final Stopwatch clock = Stopwatch()..start();
    try {
      // fail-fast：先确认后端就绪（WebDAV = 根目录存在且凭据可用），
      // 再做任何数据请求。路径配错时在这里以明确文案失败，避免先烧掉
      // 一轮请求才在 409/412 上炸出误导性错误（实测教训，见 ensureRoot）。
      await _backend.ensureReady();
      final String deviceId = await DeviceId.ensureDeviceId(_db);
      // 逐类型独立跑完「意图 → 拉 → 推 → 落基线」。类型间不共享中间状态，
      // 一个类型失败不阻断其他类型（errors 记录，报告可见）。
      for (final String type in kEntityTypes) {
        try {
          await _syncType(type, deviceId);
        } catch (e) {
          _report.errors.add(e);
        }
      }
      // manifest 只在有数据变化时写：纯查询轮询不该每次都烧一个 PUT 请求。
      if (_report.hasChanges) {
        try {
          await _writeManifest();
        } catch (e) {
          _report.errors.add(e);
        }
      }
    } finally {
      _report.durationMs = clock.elapsedMilliseconds;
    }
    return _report;
  }

  // ---------- 单类型流程 ----------

  Future<void> _syncType(String type, String deviceId) async {
    // ---- 意图推导（B + A）----
    final Map<String, Map<String, Object?>> currentRows =
        await _writer.readAllRows(_db, type);
    final Map<String, SyncStateRow> bases = await _stateDao.findAllFor(type);
    final List<SyncIntent> stateIntents = resolveFromState(
      entityType: type,
      currentRows: currentRows,
      baseJsonByEntityId: <String, String?>{
        for (final MapEntry<String, SyncStateRow> e in bases.entries)
          e.key: e.value.baseJson,
      },
    );
    final Map<String, List<String>> physicalDeletes =
        await _readPhysicalDeletes(type);
    final List<SyncIntent> intents = convergeIntents(
      entityType: type,
      stateIntents: stateIntents,
      physicalDeletes: physicalDeletes,
    );

    // ---- 拉取远端并合并写回本地 ----
    await _puller.pull(type, deviceId, bases, intents);

    // ---- 推送意图 ----
    // 推送前重读当前行：拉取阶段的合并可能已改写本地状态（如并入远端字段），
    // 意图 payload 还是拉取前的旧值，直接推会把合并成果冲掉。
    final Map<String, Map<String, Object?>> latestRows =
        await _writer.readAllRows(_db, type);
    for (final SyncIntent intent in intents) {
      if (intent.kind == SyncIntentKind.delete) {
        await _pusher.pushDelete(intent);
      } else {
        final Map<String, Object?>? row = latestRows[intent.entityId];
        if (row == null) continue; // 拉取阶段被远端墓碑删掉了：意图作废
        final SyncIntent fresh = SyncIntent(
          entityType: intent.entityType,
          entityId: intent.entityId,
          kind: SyncIntentKind.upsert,
          payload: rowToSyncJson(row),
          sourceOpLogIds: intent.sourceOpLogIds,
          resolvedFromKind: intent.resolvedFromKind,
        );
        await _pusher.pushUpsert(fresh, deviceId, bases[intent.entityId]);
      }
    }
  }

  // ---------- 读 ----------

  /// 未上传 op-log 行 → OpLogEntry 列表（A 通道输入）。
  Future<Map<String, List<String>>> _readPhysicalDeletes(String type) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'op_log',
      where: "entity_type = ? AND operation = 'delete' AND uploaded = 0",
      whereArgs: <Object?>[type],
    );
    return resolvePhysicalDeletes(
      entityType: type,
      unconsumedOpLog: <OpLogEntry>[
        for (final Map<String, Object?> r in rows) OpLogEntry.fromMap(r),
      ],
    );
  }

  // ---------- manifest ----------

  Future<void> _writeManifest() async {
    final List<RemoteObject> existing = await _backend.list('manifest.json');
    final Map<String, Object?> manifest = <String, Object?>{
      'lastSyncedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      'uploaded': _report.uploaded,
      'downloaded': _report.downloaded,
      'merged': _report.merged,
      'conflicts': _report.conflicts,
      'requests': _report.requests,
    };
    final List<int> bytes = encodeEntityJson(manifest);
    // manifest 用条件写防并发双端互踩：etag 不匹配（对端刚写过）就放弃——
    // manifest 只是观测辅助，不值得为它做合并或重试。
    final String? ifMatch = existing.isEmpty ? null : existing.first.etag;
    try {
      await _backend.put('manifest.json', bytes, ifMatchEtag: ifMatch);
    } on PreconditionFailedException {
      // 对端先写了：丢弃本次 manifest，不影响数据同步。
    }
  }
}

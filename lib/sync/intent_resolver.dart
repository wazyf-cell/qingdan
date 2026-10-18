/// 同步意图推导器（M2，方案设计 §三「意图推导定案」/ §5.4）。
///
/// 纯函数、零 IO：不 import sqflite、不碰数据库，输入全部由调用方
/// （同步引擎）从 `sync_state` / 实体表 / op_log 读好后传入。
///
/// 分层定案（v1.4 评审）：
/// - 来源 B（主）：base（`sync_state.base_json`）vs current（实体行）的
///   **终态 diff** → CREATE / CONTENT / ORDER / MOVE / TRASH / RESTORE 六态。
///   输入是终态快照对而非事件序列，天然收敛、无顺序依赖：
///   「进回收站 → 恢复」diff 结果为空（TRASH 与 RESTORE 免费抵消），
///   「反复改优先级 A→B→A」diff 只剩终值，「创建→改名→删进回收站」
///   一次 diff 直接得 TRASH 终态。
/// - 来源 A（兜底）：op-log 中 `operation='delete'` 的未上传流水，只负责
///   **物理删**（清单/标签/子任务/任务彻底删——这些实体没了就无从 diff，
///   A 是它们删除的唯一同步通道）。
/// - 两者按 (entity_type, entity_id) 求并，A 的 delete 优先。
///
/// ⚠️ 不建独立意图表：意图在同步时实时推导（§5.4），本文件不持久化任何状态。
/// ⚠️ 与 `merge_engine.dart` 的共享边界（`SyncIntent` 等）待 S6 串联时统一，
///    本文件内的定义暂不对外承诺为共享 API。
library;

import 'dart:convert';

import '../data/row_diff.dart' show camelFieldName;
import '../domain/op_log_entry.dart';

/// 同步意图的传输态。六态判定只影响 `resolvedFromKind`（调试/测试用），
/// 传输层实际塌缩为两态：整实体 JSON PUT（upsert）或删文件（delete）。
enum SyncIntentKind { upsert, delete }

/// 一条同步意图：对远端要做的一件事。
class SyncIntent {
  const SyncIntent({
    required this.entityType,
    required this.entityId,
    required this.kind,
    this.payload,
    this.sourceOpLogIds = const <String>[],
    this.resolvedFromKind,
  });

  /// 实体类型：'task' | 'list' | 'subtask' | 'tag' | 'task_tag'（与 op_log 一致）。
  final String entityType;
  final String entityId;
  final SyncIntentKind kind;

  /// upsert 时的实体同步 JSON（camelCase 业务字段，形如
  /// `{"id","title","modifiedTime",...}`）。
  ///
  /// ⚠️ 不含 `rev` / `deviceId` / `sortOrder`：rev 来自 sync_state 自增、
  /// deviceId 来自 `_meta`，纯函数拿不到这两个运行时值，由同步引擎在
  /// 上传前写入（§5.4 要求实体 JSON 含 `{id, rev, deviceId, modifiedTime}`）；
  /// sortOrder 按 §5.3 从同步 JSON 排除（顺序走独立的 `order/<listId>.json`
  /// 实体，本里程碑不实现 order 同步，只保证它不出现在 payload 里）。
  final Map<String, Object?>? payload;

  /// 参与本次推导的 op-log id（落基线时同步引擎据此把流水标 `uploaded=1`，
  /// §5.4 第 4 步）。来源 B 产出的意图此列表为空。
  final List<String> sourceOpLogIds;

  /// 调试/测试用：CREATE / CONTENT / ORDER / MOVE / TRASH / RESTORE / DELETE 之一。
  final String? resolvedFromKind;
}

/// diff 时跳过的行列名（snake_case，来自实体表行 Map）。
///
/// - `rev` / `device_id`：同步元数据，**绝不能当业务字段参与 diff**——
///   否则两端 rev 永不相等 → 每轮同步都判定「有变更」→ 死循环上传；
/// - `sort_order`：§5.3 定案，顺序走 order 实体，不随任务上传；
/// - `last_synced_json`：M1 遗留列，v3 起被 sync_state 取代，不再读写。
/// 注意 `id` **不在此列**：payload 是上传的实体 JSON，必须含
/// `{id, ..., modifiedTime}`（§5.4）；diff 侧 id 由 `_kJsonSkipKeys` 排除。
const Set<String> _kRowSkipKeys = <String>{
  'last_synced_json',
  'rev',
  'device_id',
  'sort_order',
  // 批次是本地簿记、`import_batches` 不同步 → 这列上了云也没人能把行落库
  // （外键指向对端不存在的行，必 787）。M4a S6。
  'import_batch_id',
};

/// diff 时跳过的同步 JSON 键（camelCase，来自 `sync_state.base_json`）。
/// 同 `_kRowSkipKeys`，`sortOrder` 也从 payload 排除（§5.3）。
const Set<String> _kJsonSkipKeys = <String>{
  'id',
  'rev',
  'deviceId',
  'sortOrder',
  'importBatchId', // 与 _kRowSkipKeys 的 import_batch_id 成对，见 M4a S6
};

/// 来源 B：base vs current 的终态 diff。
///
/// [currentRows]：entityId → 当前行 Map（DAO 查询的原始行，snake_case 列名；
/// 物理删的实体调用方自然查不到，即「已剔除」）。软删任务（deleted=1 的行）
/// **必须包含在内**，否则 TRASH 推不出来。
/// [baseJsonByEntityId]：entityId → base JSON 串；null = 从未同步（→ CREATE）。
///
/// 返回按 entityId 升序排列的意图列表；同一实体至多一条（收敛核心）。
/// **本函数不产出 delete**：current 不存在而 base 存在 = 物理删，统一由
/// 来源 A 兜底（见 [resolvePhysicalDeletes]），两条路径语义不重叠。
List<SyncIntent> resolveFromState({
  required String entityType,
  required Map<String, Map<String, Object?>> currentRows,
  required Map<String, String?> baseJsonByEntityId,
}) {
  final List<SyncIntent> intents = <SyncIntent>[];
  final List<String> ids = currentRows.keys.toList()..sort();
  for (final String id in ids) {
    final Map<String, Object?> current = _rowToSyncJson(currentRows[id]!);
    final String? baseStr = baseJsonByEntityId[id];
    if (baseStr == null) {
      intents.add(SyncIntent(
        entityType: entityType,
        entityId: id,
        kind: SyncIntentKind.upsert,
        payload: current,
        resolvedFromKind: 'CREATE',
      ));
      continue;
    }
    final Map<String, Object?> base =
        (jsonDecode(baseStr) as Map<Object?, Object?>)
            .cast<String, Object?>();
    final Set<String> changed = _changedFields(base, current);
    if (changed.isEmpty) continue; // 终态相同：TRASH/RESTORE、A→B→A 在此免费抵消
    intents.add(SyncIntent(
      entityType: entityType,
      entityId: id,
      kind: SyncIntentKind.upsert,
      payload: current,
      resolvedFromKind: _resolvedKind(base, current, changed),
    ));
  }
  return intents;
}

/// 来源 A：op-log 中未上传的 `operation='delete'` 流水 → 物理删集合。
///
/// 返回 entityId → 参与判定的 op-log id 列表（落基线时标 `uploaded=1` 用）；
/// 未上传流水里同一实体可能有多条 delete 记录，全部收进列表一并消费。
/// 防御性跳过 `uploaded == true` 的记录（调用方按约定传未上传流水）。
Map<String, List<String>> resolvePhysicalDeletes({
  required String entityType,
  required List<OpLogEntry> unconsumedOpLog,
}) {
  final Map<String, List<String>> deletes = <String, List<String>>{};
  for (final OpLogEntry e in unconsumedOpLog) {
    if (e.entityType != entityType) continue;
    if (e.operation != OpLogOperation.delete.value) continue;
    if (e.uploaded) continue;
    deletes.putIfAbsent(e.entityId, () => <String>[]).add(e.id);
  }
  return deletes;
}

/// 合并两个来源：A 的 delete 优先（覆盖 B 对同一实体产出的任何意图）。
///
/// 返回按 entityId 升序的意图列表，每实体至多一条。
List<SyncIntent> convergeIntents({
  required String entityType,
  required List<SyncIntent> stateIntents,
  required Map<String, List<String>> physicalDeletes,
}) {
  final Map<String, SyncIntent> byId = <String, SyncIntent>{
    for (final SyncIntent i in stateIntents) i.entityId: i,
  };
  final List<SyncIntent> merged = <SyncIntent>[];
  final List<String> ids = <String>{...byId.keys, ...physicalDeletes.keys}
      .toList()
    ..sort();
  for (final String id in ids) {
    final List<String>? opLogIds = physicalDeletes[id];
    if (opLogIds != null) {
      merged.add(SyncIntent(
        entityType: entityType,
        entityId: id,
        kind: SyncIntentKind.delete,
        sourceOpLogIds: List<String>.unmodifiable(opLogIds),
        resolvedFromKind: 'DELETE',
      ));
    } else {
      merged.add(byId[id]!);
    }
  }
  return merged;
}

/// 实体行 Map → 同步 JSON：列名转 camelCase，跳过非业务键（见 `_kRowSkipKeys`，
/// 其中含 `sort_order` —— payload 里不该有它，§5.3）。
Map<String, Object?> _rowToSyncJson(Map<String, Object?> row) =>
    <String, Object?>{
      for (final MapEntry<String, Object?> e in row.entries)
        if (!_kRowSkipKeys.contains(e.key)) camelFieldName(e.key): e.value,
    };

/// 逐字段比对 base 与 current（键空间已同为 camelCase），返回变化字段集合。
/// 空集合 = 无业务变化 = 不产意图。
Set<String> _changedFields(
  Map<String, Object?> base,
  Map<String, Object?> current,
) {
  final Set<String> keys = <String>{...base.keys, ...current.keys}
    ..removeAll(_kJsonSkipKeys);
  return <String>{
    for (final String k in keys)
      // SQLite 行里 bool 存 0/1，同步 JSON 里是 true/false，归一后再比。
      if (_norm(base[k]) != _norm(current[k])) k,
  };
}

/// 六态判定（单一终态，优先级从高到低）：
/// 1. `deleted` 变化 → TRASH（false→true）或 RESTORE（true→false）——
///    删除态是终态语义的最高优先级（「改名后删进回收站」整条记 TRASH）；
/// 2. `listId` 变化 → MOVE；
/// 3. `sortOrder` 变化 → ORDER（§5.3 排除 sort_order 后本态实际不会出现，
///    枚举值保留以对齐方案设计 §三 的六态命名）;
/// 4. 其余任意业务字段变化 → CONTENT。
String _resolvedKind(
  Map<String, Object?> base,
  Map<String, Object?> current,
  Set<String> changed,
) {
  if (changed.contains('deleted')) {
    return _truthy(current['deleted']) ? 'TRASH' : 'RESTORE';
  }
  if (changed.contains('listId')) return 'MOVE';
  if (changed.contains('sortOrder')) return 'ORDER';
  return 'CONTENT';
}

/// SQLite 行值 → 可与 JSON 值直比的形式：bool 归一为 0/1，其余原样。
/// （列表/Map 值走 Dart `==`；本项目的实体字段不含嵌套容器，够用。）
Object? _norm(Object? v) => v is bool ? (v ? 1 : 0) : v;

/// 0/1、true/false 归一的真值判定。
bool _truthy(Object? v) => v == true || v == 1;
